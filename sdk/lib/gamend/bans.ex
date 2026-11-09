defmodule Gamend.Bans do
  @moduledoc ~S"""
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


  **Note:** This is an SDK stub. Calling these functions will raise an error.
  The actual implementation runs on the Gamend.
  """

  @doc ~S"""
    The active ban on an account, or nil. Queries only when the cache holds one,
    so it is cheap to ask on every request.
    
  """
  @spec account_ban(String.t()) :: Gamend.Bans.Ban.t() | nil
  def account_ban(_user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Bans.account_ban/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    The active ban on `subject`, or nil: for showing its end and reason. A chat
    ban names its reach with `:scope` and `:scope_ref_id`.
    
  """
  @spec active(Gamend.Bans.Ban.kind(), String.t(), keyword()) :: Gamend.Bans.Ban.t() | nil
  def active(_kind, _subject, _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Bans.active/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Whether `ban` is in force now.
  """
  @spec active?(Gamend.Bans.Ban.t()) :: boolean()
  def active?(_ban) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :erlang.phash2(make_ref(), 2) == 0

      _ ->
        raise "Gamend.Bans.active?/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Bans `subject` until `:expires_at` (a `DateTime`, `nil` for permanent).
    
    Options: `:expires_at` (a `DateTime` or an ISO 8601 string), `:reason`
    (shown to the banned player), `:source` (`:admin` by default, see
    `Gamend.Bans.Ban`), `:by` (the person's user id), and for a chat ban
    `:scope` and `:scope_ref_id`. The ban applies on this instance at once and on
    the others within moments.
    
    An account ban needs an existing user that is not an admin: banning an admin
    would let one admin lock another (or themselves) out of the console.
    
  """
  @spec ban(Gamend.Bans.Ban.kind(), String.t(), keyword()) ::
          {:ok, Gamend.Bans.Ban.t()} | {:error, Ecto.Changeset.t()}
  def ban(_kind, _subject, _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if reason = Application.get_env(:gamend_sdk, :stub_error),
          do: {:error, reason},
          else:
            {:ok,
             %Gamend.Bans.Ban{
               id: "",
               kind: :account,
               subject: "",
               user_id: nil,
               expires_at: nil,
               reason: nil,
               source: :plugin,
               scope: nil,
               scope_ref_id: nil,
               banned_by: nil,
               lifted_at: nil,
               lifted_by: nil,
               inserted_at: ~U[1970-01-01 00:00:00Z],
               updated_at: ~U[1970-01-01 00:00:00Z]
             }}

      _ ->
        raise "Gamend.Bans.ban/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Whether an IP or account `subject` is banned now: an ETS read, no query.
  """
  @spec banned?(Gamend.Bans.Ban.kind(), String.t()) :: boolean()
  def banned?(_kind, _subject) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :erlang.phash2(make_ref(), 2) == 0

      _ ->
        raise "Gamend.Bans.banned?/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    The ids of the accounts banned now, as a subquery: `Gamend.Accounts.Search`'s `banned` facet.
  """
  @spec banned_user_ids() :: Ecto.Query.t()
  def banned_user_ids() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Bans.banned_user_ids/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    How many bans `list/2` would page through.
  """
  @spec count(map()) :: non_neg_integer()
  def count(_filters \\ %{}) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Bans.count/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Tells of a ban that ran out: drops it from the cache, tells the player
    (`account_unbanned`, `chat_unmuted`) and runs `after_ban_lifted/1`. Run by
    `Gamend.Bans.ExpiryWorker` at `expires_at`. `:noop` for a ban lifted or
    replaced first (that already told), `{:not_yet, seconds}` for one still in
    force.
    
  """
  @spec expire(Gamend.Bans.Ban.t()) :: :ok | :noop | {:not_yet, pos_integer()}
  def expire(_ban) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Bans.expire/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    The `expires_at` for a ban lasting `ttl_ms` from now; nil for `:infinity`.
  """
  @spec expires_after(non_neg_integer() | :infinity) :: DateTime.t() | nil
  def expires_after(_ttl_ms) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Bans.expires_after/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    One ban, with its users, or nil.
  """
  @spec get(Ecto.UUID.t()) :: Gamend.Bans.Ban.t() | nil
  def get(_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Bans.get/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Ends the active ban on `subject`, if it has one. `:by` is the person's user
    id; a chat ban names its reach with `:scope` and `:scope_ref_id`. Answers the
    bans it ended (none, or one).
    
  """
  @spec lift(Gamend.Bans.Ban.kind(), String.t(), keyword()) :: {:ok, [Gamend.Bans.Ban.t()]}
  def lift(_kind, _subject, _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Bans.lift/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Ends this ban's target's active ban: the ban itself while it is in force (a
    target banned again since has a newer one, which this lifts). `opts` as for
    `lift/3`: `:by`.
    
  """
  @spec lift_ban(
          Gamend.Bans.Ban.t(),
          keyword()
        ) :: {:ok, [Gamend.Bans.Ban.t()]}
  def lift_ban(_ban, _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Bans.lift_ban/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Bans, ended ones too, newest first, with the banned user and the people who
    placed and lifted them. Filters (string or atom keys): `kind` (`:ip`,
    `:account` or `:chat`, or the string), `user_id`, `subject`, `scope`,
    `scope_ref_id`, and `active` (true: only the bans in force). `opts` are
    `Gamend.Query.page/2`'s: `page`, `page_size`.
    
  """
  @spec list(
          map(),
          keyword()
        ) :: [Gamend.Bans.Ban.t()]
  def list(_filters \\ %{}, _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Bans.list/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Every active ban, of one kind or all, newest first.
  """
  @spec list_active(Gamend.Bans.Ban.kind() | nil) :: [Gamend.Bans.Ban.t()]
  def list_active(_kind \\ nil) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Bans.list_active/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Whether `user_id` may not send in this chat: muted everywhere, or in this
    lobby, group or party. An ETS read, run on every outgoing message.
    
  """
  @spec muted?(String.t(), String.t() | nil, String.t() | nil) :: boolean()
  def muted?(_user_id, _chat_type, _chat_ref_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :erlang.phash2(make_ref(), 2) == 0

      _ ->
        raise "Gamend.Bans.muted?/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Deletes bans that ended (lifted or expired) more than `days` ago; an active
    ban is never deleted. `days` of 0 keeps them all. Answers the rows deleted.
    Run by `Gamend.Retention` with `bans_days`.
    
  """
  @spec prune(integer()) :: non_neg_integer()
  def prune(_days) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Bans.prune/1 is a stub - only available at runtime on Gamend"
    end
  end
end
