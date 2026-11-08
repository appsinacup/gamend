defmodule Gamend.Bans do
  @moduledoc """
  Bans: an IP address, an account or a chat sender kept out for a while, or
  for good.

  The `bans` table is the source of truth and keeps every ban after it ends,
  so a target's history is its rows. `Gamend.Bans.Cache` holds the active ones
  in ETS for the per-request check (`banned?/2`), and carries each change to
  the other instances over PubSub (`Gamend.Bans.Sync` applies them there and
  loads the table at boot).

  Placing a ban on a target that already has one ends the old one (lifted by
  whoever placed the new one) and starts the new one, so a target has at most
  one active ban. A target is the kind, the subject and, for a chat ban, its
  reach (`Gamend.Bans.Ban.target/4`): a global mute and a mute in one lobby are
  two targets.

      Gamend.Bans.ban(:ip, "1.2.3.4", expires_at: Gamend.Bans.expires_after(:timer.hours(24)))
      Gamend.Bans.ban(:account, user.id, expires_at: in_a_week, reason: "Cheating", by: admin.id)
      Gamend.Bans.ban(:chat, user.id, scope: "lobby", scope_ref_id: lobby.id, source: :room)
      Gamend.Bans.lift(:account, user.id, by: admin.id)
      Gamend.Bans.banned?(:ip, "1.2.3.4")

  An IP ban's subject is the address as the web layer keys it (an IPv6 one as
  its /64, `GamendWeb.Plugs.IpBan`); an account or chat ban's is the user id.

  ## Chat bans (mutes)

  A chat ban silences a sender everywhere (`scope: "global"`, friend DMs
  included) or in one lobby, group or party (`scope` and `scope_ref_id`).
  `Gamend.Chat.mute_user/4` and `unmute_user/3` are chat's way in, with the
  room rules; `muted?/3` is the per-message check. Placing and lifting one
  tells the player `{:chat_muted, ban}` and `{:chat_unmuted, ...}`, the user
  channel's `chat_muted` and `chat_unmuted`.

  ## Account bans

  A banned account still signs in, and can read and delete itself; everything
  else refuses it (the web layer: `GamendWeb.Plugs.AccountBan` on the API, the
  channels, `GamendWeb.UserAuth` on the website). Placing and lifting one
  tells the account on its user topic, `{:account_banned, ban}` and
  `{:account_unbanned, user_id}`, which the user channel passes on as the
  `account_banned` and `account_unbanned` events.

  ## Hooks and plugins

  A plugin bans and lifts with these functions (`source: :plugin`), and hears
  of every ban through two fire-and-forget hooks: `after_ban_created/1`, and
  `after_ban_lifted/1` once for every ban that ends, lifted, replaced or
  expired. A ban with an end schedules a job for it (`Gamend.Bans.ExpiryWorker`),
  so an expiry is told like a lift: the hook, and `account_unbanned` or
  `chat_unmuted`.
  """

  import Ecto.Query

  alias Gamend.Accounts.User
  alias Gamend.AfterCommit
  alias Gamend.Bans.Ban
  alias Gamend.Bans.Cache
  alias Gamend.Bans.ExpiryWorker
  alias Gamend.Repo

  require Gamend.Bans.BanKind, as: BanKind
  require Gamend.Bans.BanScope, as: BanScope
  require Gamend.Chat.ChatType, as: ChatType

  @doc """
  Bans `subject` until `:expires_at` (a `DateTime`, `nil` for permanent).

  Options: `:expires_at` (a `DateTime` or an ISO 8601 string), `:reason`
  (shown to the banned player), `:source` (`:admin` by default, see
  `Gamend.Bans.Ban`), `:by` (the person's user id), and for a chat ban
  `:scope` and `:scope_ref_id`. The ban applies on this instance at once and on
  the others within moments.

  An account ban needs an existing user that is not an admin: banning an admin
  would let one admin lock another (or themselves) out of the console.
  """
  @spec ban(Ban.kind(), String.t(), keyword()) :: {:ok, Ban.t()} | {:error, Ecto.Changeset.t()}
  def ban(kind, subject, opts \\ []) when is_binary(subject) do
    now = DateTime.utc_now(:second)

    attrs = %{
      kind: kind,
      subject: subject,
      user_id: if(kind in [:account, :chat], do: subject),
      scope: Keyword.get(opts, :scope),
      scope_ref_id: Keyword.get(opts, :scope_ref_id),
      expires_at: opts |> Keyword.get(:expires_at) |> truncate(),
      reason: Keyword.get(opts, :reason),
      source: Keyword.get(opts, :source, :admin),
      banned_by: Keyword.get(opts, :by)
    }

    target = Ban.target(kind, subject, attrs.scope, attrs.scope_ref_id)

    AfterCommit.transact(fn ->
      replaced = lift_rows(target, now, Keyword.get(opts, :by))

      changeset =
        %Ban{}
        |> Ban.changeset(attrs)
        |> validate_future(now)
        |> validate_account(kind, subject)

      with {:ok, ban} <- Repo.insert(changeset),
           :ok <- schedule_expiry(ban) do
        AfterCommit.defer(fn ->
          Cache.put(ban)
          tell(:placed, ban)
          Enum.each(replaced, &dispatch(:after_ban_lifted, &1))
          dispatch(:after_ban_created, ban)
        end)

        {:ok, ban}
      end
    end)
  end

  @doc """
  Ends this ban's target's active ban: the ban itself while it is in force (a
  target banned again since has a newer one, which this lifts). `opts` as for
  `lift/3`: `:by`.
  """
  @spec lift_ban(Ban.t(), keyword()) :: {:ok, [Ban.t()]}
  def lift_ban(%Ban{} = ban, opts \\ []),
    do: lift(ban.kind, ban.subject, [scope: ban.scope, scope_ref_id: ban.scope_ref_id] ++ opts)

  @doc """
  Ends the active ban on `subject`, if it has one. `:by` is the person's user
  id; a chat ban names its reach with `:scope` and `:scope_ref_id`. Answers the
  bans it ended (none, or one).
  """
  @spec lift(Ban.kind(), String.t(), keyword()) :: {:ok, [Ban.t()]}
  def lift(kind, subject, opts \\ []) when is_atom(kind) and is_binary(subject) do
    target =
      Ban.target(kind, subject, Keyword.get(opts, :scope), Keyword.get(opts, :scope_ref_id))

    AfterCommit.transact(fn ->
      lifted = lift_rows(target, DateTime.utc_now(:second), Keyword.get(opts, :by))

      AfterCommit.defer(fn ->
        Cache.delete(target)
        Enum.each(lifted, &tell(:ended, &1))
        Enum.each(lifted, &dispatch(:after_ban_lifted, &1))
      end)

      {:ok, lifted}
    end)
  end

  @doc """
  Tells of a ban that ran out: drops it from the cache, tells the player
  (`account_unbanned`, `chat_unmuted`) and runs `after_ban_lifted/1`. Run by
  `Gamend.Bans.ExpiryWorker` at `expires_at`. `:noop` for a ban lifted or
  replaced first (that already told), `{:not_yet, seconds}` for one still in
  force.
  """
  @spec expire(Ban.t()) :: :ok | :noop | {:not_yet, pos_integer()}
  def expire(%Ban{lifted_at: nil, expires_at: %DateTime{} = expires_at} = ban) do
    case DateTime.diff(expires_at, DateTime.utc_now(), :millisecond) do
      left when left > 0 ->
        {:not_yet, div(left + 999, 1000)}

      _ended ->
        Cache.delete(Ban.target(ban))
        tell(:ended, ban)
        dispatch(:after_ban_lifted, ban)
        :ok
    end
  end

  def expire(%Ban{}), do: :noop

  @doc "Whether an IP or account `subject` is banned now: an ETS read, no query."
  @spec banned?(Ban.kind(), String.t()) :: boolean()
  def banned?(kind, subject) when is_binary(subject),
    do: Cache.active?(Ban.target(kind, subject, nil, nil))

  @doc """
  Whether `user_id` may not send in this chat: muted everywhere, or in this
  lobby, group or party. An ETS read, run on every outgoing message.
  """
  @spec muted?(String.t(), String.t() | nil, String.t() | nil) :: boolean()
  def muted?(user_id, chat_type, chat_ref_id) when is_binary(user_id) do
    Cache.active?(Ban.target(:chat, user_id, BanScope.global(), nil)) or
      (chat_type in [ChatType.lobby(), ChatType.group(), ChatType.party()] and
         is_binary(chat_ref_id) and
         Cache.active?(Ban.target(:chat, user_id, chat_type, chat_ref_id)))
  end

  @doc """
  The active ban on `subject`, or nil: for showing its end and reason. A chat
  ban names its reach with `:scope` and `:scope_ref_id`.
  """
  @spec active(Ban.kind(), String.t(), keyword()) :: Ban.t() | nil
  def active(kind, subject, opts \\ []) when is_binary(subject) do
    target =
      Ban.target(kind, subject, Keyword.get(opts, :scope), Keyword.get(opts, :scope_ref_id))

    DateTime.utc_now(:second)
    |> active_query()
    |> of_target(target)
    |> order_by([b], desc: b.inserted_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  The active ban on an account, or nil. Queries only when the cache holds one,
  so it is cheap to ask on every request.
  """
  @spec account_ban(String.t()) :: Ban.t() | nil
  def account_ban(user_id) when is_binary(user_id) do
    if banned?(:account, user_id), do: active(:account, user_id)
  end

  @doc "Every active ban, of one kind or all, newest first."
  @spec list_active(Ban.kind() | nil) :: [Ban.t()]
  def list_active(kind \\ nil) do
    DateTime.utc_now(:second)
    |> active_query()
    |> of_kind(kind)
    |> order_by([b], desc: b.inserted_at)
    |> Repo.all()
  end

  @doc """
  Bans, ended ones too, newest first, with the banned user and the people who
  placed and lifted them. Filters (string or atom keys): `kind` (`:ip`,
  `:account` or `:chat`, or the string), `user_id`, `subject`, `scope`,
  `scope_ref_id`, and `active` (true: only the bans in force). `opts` are
  `Gamend.Query.page/2`'s: `page`, `page_size`.
  """
  @spec list(map(), keyword()) :: [Ban.t()]
  def list(filters \\ %{}, opts \\ []) do
    filters
    |> filtered()
    |> order_by([b], desc: b.inserted_at, desc: b.id)
    |> Gamend.Query.page(opts)
    |> preload([:user, :banned_by_user, :lifted_by_user])
    |> Repo.all()
  end

  @doc "How many bans `list/2` would page through."
  @spec count(map()) :: non_neg_integer()
  def count(filters \\ %{}), do: filters |> filtered() |> Repo.aggregate(:count, :id)

  @doc "One ban, with its users, or nil."
  @spec get(Ecto.UUID.t()) :: Ban.t() | nil
  def get(id), do: Ban |> Repo.get(id) |> Repo.preload([:user, :banned_by_user, :lifted_by_user])

  @doc "The ids of the accounts banned now, as a subquery: `Gamend.Accounts.Search`'s `banned` facet."
  @spec banned_user_ids() :: Ecto.Query.t()
  def banned_user_ids do
    DateTime.utc_now(:second)
    |> active_query()
    |> where([b], b.kind == :account)
    |> select([b], b.user_id)
  end

  @doc "Whether `ban` is in force now."
  @spec active?(Ban.t()) :: boolean()
  def active?(%Ban{lifted_at: nil, expires_at: nil}), do: true

  def active?(%Ban{lifted_at: nil, expires_at: %DateTime{} = expires_at}),
    do: DateTime.after?(expires_at, DateTime.utc_now())

  def active?(%Ban{}), do: false

  @doc "The `expires_at` for a ban lasting `ttl_ms` from now; nil for `:infinity`."
  @spec expires_after(non_neg_integer() | :infinity) :: DateTime.t() | nil
  def expires_after(:infinity), do: nil

  def expires_after(ttl_ms) when is_integer(ttl_ms),
    do: DateTime.utc_now(:second) |> DateTime.add(ttl_ms, :millisecond) |> truncate()

  @doc """
  Deletes bans that ended (lifted or expired) more than `days` ago; an active
  ban is never deleted. `days` of 0 keeps them all. Answers the rows deleted.
  Run by `Gamend.Retention` with `bans_days`.
  """
  @spec prune(integer()) :: non_neg_integer()
  def prune(days) when not is_integer(days) or days <= 0, do: 0

  def prune(days) do
    cutoff = DateTime.add(DateTime.utc_now(:second), -days, :day)

    {count, _} =
      Repo.delete_all(
        from(b in Ban,
          where:
            (not is_nil(b.lifted_at) and b.lifted_at < ^cutoff) or
              (not is_nil(b.expires_at) and b.expires_at < ^cutoff)
        )
      )

    count
  end

  # ── Private ────────────────────────────────────────────────────────────────

  # The player hears of their own ban on their user topic; an IP has no one to
  # tell. A ban that ends by being replaced is not told: the new one is.
  defp tell(:placed, %Ban{kind: :account} = ban),
    do: broadcast(ban.subject, {:account_banned, ban})

  defp tell(:placed, %Ban{kind: :chat} = ban), do: broadcast(ban.subject, {:chat_muted, ban})

  defp tell(:ended, %Ban{kind: :account} = ban),
    do: broadcast(ban.subject, {:account_unbanned, ban.subject})

  defp tell(:ended, %Ban{kind: :chat} = ban) do
    broadcast(
      ban.subject,
      {:chat_unmuted, %{user_id: ban.subject, scope: ban.scope, scope_ref_id: ban.scope_ref_id}}
    )
  end

  defp tell(_event, %Ban{}), do: :ok

  defp broadcast(user_id, message),
    do: Gamend.Broadcast.best_effort("user:#{user_id}", message, "ban")

  # Hooks never run inside the write: queued after it, in a task.
  defp dispatch(hook, %Ban{} = ban) do
    Gamend.Async.run(fn -> Gamend.Hooks.internal_call(hook, [ban]) end)
    :ok
  end

  # The job that tells of the ban's end, inserted in the ban's own transaction
  # so a ban is never written without it. A permanent ban has none.
  defp schedule_expiry(%Ban{expires_at: nil}), do: :ok

  defp schedule_expiry(%Ban{id: id, expires_at: expires_at}) do
    case Gamend.Jobs.enqueue(ExpiryWorker, %{"ban_id" => id}, scheduled_at: expires_at) do
      {:ok, _job} -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp lift_rows(target, now, by) do
    rows =
      now
      |> active_query()
      |> of_target(target)
      |> Repo.all()

    if rows != [] do
      ids = Enum.map(rows, & &1.id)

      Repo.update_all(from(b in Ban, where: b.id in ^ids),
        set: [lifted_at: now, lifted_by: by, updated_at: now]
      )
    end

    Enum.map(rows, &%{&1 | lifted_at: now, lifted_by: by, updated_at: now})
  end

  defp active_query(now) do
    from(b in Ban, where: is_nil(b.lifted_at) and (is_nil(b.expires_at) or b.expires_at > ^now))
  end

  defp of_kind(query, nil), do: query
  defp of_kind(query, kind), do: where(query, [b], b.kind == ^kind)

  defp of_target(query, {kind, subject, nil}),
    do: where(query, [b], b.kind == ^kind and b.subject == ^subject and is_nil(b.scope))

  defp of_target(query, {:chat, subject, BanScope.global()}),
    do:
      where(
        query,
        [b],
        b.kind == :chat and b.subject == ^subject and b.scope == ^BanScope.global()
      )

  # A room scope with no room never matches a row; the changeset refuses it.
  defp of_target(query, {:chat, subject, {scope, nil}}) do
    where(
      query,
      [b],
      b.kind == :chat and b.subject == ^subject and b.scope == ^scope and is_nil(b.scope_ref_id)
    )
  end

  defp of_target(query, {:chat, subject, {scope, ref}}) do
    where(
      query,
      [b],
      b.kind == :chat and b.subject == ^subject and b.scope == ^scope and b.scope_ref_id == ^ref
    )
  end

  defp filtered(filters) do
    get = fn key ->
      Gamend.Parse.blank_to_nil(Map.get(filters, key) || Map.get(filters, to_string(key)))
    end

    query =
      if get.(:active) in [true, "true"],
        do: active_query(DateTime.utc_now(:second)),
        else: from(b in Ban)

    query
    |> of_kind(kind_filter(get.(:kind)))
    |> then(fn q -> if id = get.(:user_id), do: where(q, [b], b.user_id == ^id), else: q end)
    |> then(fn q -> if s = get.(:subject), do: where(q, [b], b.subject == ^s), else: q end)
    |> then(fn q -> if s = get.(:scope), do: where(q, [b], b.scope == ^s), else: q end)
    |> then(fn q ->
      if r = get.(:scope_ref_id), do: where(q, [b], b.scope_ref_id == ^to_string(r)), else: q
    end)
  end

  defp kind_filter(kind) when kind in [:ip, :account, :chat], do: kind
  defp kind_filter(BanKind.ip()), do: :ip
  defp kind_filter(BanKind.account()), do: :account
  defp kind_filter(BanKind.chat()), do: :chat
  defp kind_filter(_), do: nil

  # An account ban is for a user that exists and is not an admin.
  defp validate_account(changeset, :account, user_id) do
    case Ecto.UUID.cast(user_id) do
      {:ok, id} ->
        case Repo.get(User, id) do
          nil -> Ecto.Changeset.add_error(changeset, :subject, "is not a user")
          %User{is_admin: true} -> Ecto.Changeset.add_error(changeset, :subject, "is an admin")
          %User{} -> changeset
        end

      :error ->
        Ecto.Changeset.add_error(changeset, :subject, "is not a user id")
    end
  end

  defp validate_account(changeset, _kind, _subject), do: changeset

  # A ban that ends before it starts would be stored and never apply.
  defp validate_future(changeset, now) do
    Ecto.Changeset.validate_change(changeset, :expires_at, fn :expires_at, expires_at ->
      if DateTime.after?(expires_at, now), do: [], else: [expires_at: "must be in the future"]
    end)
  end

  # A string (an API's ISO 8601) is cast by the changeset, which says when it
  # is not one.
  defp truncate(%DateTime{} = at), do: DateTime.truncate(at, :second)
  defp truncate(other), do: other
end
