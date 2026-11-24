defmodule Gamend.Accounts.Presence do
  @moduledoc """
  Whether a user is online, and when they were last seen.

  Split out of `Gamend.Accounts`, which still exposes every function here under
  the same name. The writes themselves are coalesced by
  `Gamend.Accounts.PresenceWriter`.
  """

  import Ecto.Query, warn: false
  alias Gamend.Accounts
  alias Gamend.Accounts.PresenceWriter
  alias Gamend.Accounts.User
  alias Gamend.Repo

  @doc """
  Updates `last_seen_at` to now for the given user. Fire-and-forget — errors are ignored.
  Call on login (session or JWT) to track activity. Also records the UTC day
  for `Gamend.Analytics` (DAU / retention).
  """
  @spec touch_last_seen(User.t()) :: :ok
  def touch_last_seen(%User{} = user) do
    now = DateTime.utc_now(:second)

    case user |> Ecto.Changeset.change(last_seen_at: now) |> Repo.update() do
      {:ok, updated} -> Accounts.invalidate_user_cache(updated)
      _ -> :ok
    end

    # No stats-cache bust here any more: the only counter a login used to move
    # ("active in the last N days") now lives in `Gamend.Analytics`.
    Gamend.Analytics.record_activity(user.id, now)
  end

  @doc """
  Lightweight version of `touch_last_seen/1` that accepts a user ID directly.
  Performs a single UPDATE without loading the full struct first, setting
  `last_seen_at` to now. Fire-and-forget — errors are ignored.

  `is_online` is not touched: an offline to online move is `set_user_online/1`'s,
  which tells the user's lobby, party and friends and runs `after_user_online`.
  Written here, the flag came back with none of that, and a game's offline
  mark (a voyage's "disconnected" card) stayed up on a player back online.
  """
  @spec touch_last_seen_by_id(Ecto.UUID.t()) :: :ok
  def touch_last_seen_by_id(user_id) when is_binary(user_id) do
    now = DateTime.utc_now(:second)

    from(u in User, where: u.id == ^user_id)
    |> Repo.update_all(set: [last_seen_at: now])

    # Update the cached struct in place rather than busting it: this runs every
    # few minutes per connected socket, and a delete would force cold get_user
    # reads on the lobby/party/group hot paths right after each heartbeat. Other
    # nodes keep last_seen within the TTL, which is fine for presence data.
    case Gamend.Cache.get!({:accounts, :user, user_id}) do
      %User{} = cached ->
        _ =
          Gamend.Cache.put(
            {:accounts, :user, user_id},
            %{cached | last_seen_at: now},
            ttl: Accounts.user_cache_ttl_ms()
          )

      _ ->
        :ok
    end

    # One cache read per heartbeat; a row only on the first touch of a UTC day.
    Gamend.Analytics.record_activity(user_id, now)
  end

  @doc """
  Mark a user as online and update last_seen_at.

  Writes only on a real offline→online transition: reconnects and extra
  tabs/sockets while already online are no-ops, so reconnect storms don't
  hammer the `users` table (and the `after_user_online` hook fires once per
  session, not once per socket).

  Returns {:ok, user} on success.
  """
  @spec set_user_online(Ecto.UUID.t()) :: {:ok, User.t()} | {:error, term()}
  def set_user_online(user_id) when is_binary(user_id), do: set_presence(user_id, true)

  @doc """
  Mark a user as offline and update last_seen_at.

  Writes only on a real online→offline transition (see `set_user_online/1`).

  Returns {:ok, user} on success.
  """
  @spec set_user_offline(Ecto.UUID.t()) :: {:ok, User.t()} | {:error, term()}
  def set_user_offline(user_id) when is_binary(user_id), do: set_presence(user_id, false)

  # The no-op case — a reconnect, a second tab, a second device — is the common
  # one and is answered from the cached read, not an uncached `Repo.get` per
  # socket join. The cache is invalidated on every transition below, so a hit
  # that already reports the target state is authoritative.
  defp set_presence(user_id, target) do
    now = DateTime.utc_now(:second)

    case Accounts.get_user(user_id) do
      nil ->
        {:error, :not_found}

      %User{} = user ->
        # The buffered state, not the row: a player who disconnects inside the
        # flush window has to see their own pending connect, or the disconnect
        # reads as a no-op and the stale connect is what gets written.
        effective = PresenceWriter.pending(user_id, user.is_online)

        cond do
          effective == target ->
            {:ok, %{user | is_online: effective}}

          PresenceWriter.flush_ms() == 0 ->
            write_presence(user_id, target, now)

          true ->
            # The durable write is coalesced with every other transition in the
            # window; the caller gets the struct it would have got, and the
            # realtime push that follows it goes over PubSub, not the database.
            :ok = PresenceWriter.mark(user_id, target)
            pending = %{user | is_online: target, last_seen_at: now}
            # Keep other readers consistent with what is about to be written.
            _ = Accounts.cache_user(pending)

            {:ok, pending}
        end
    end
  end

  defp write_presence(user_id, target, now) do
    case Repo.get(User, user_id) do
      nil ->
        {:error, :not_found}

      %User{is_online: ^target} = user ->
        {:ok, user}

      user ->
        user
        |> Ecto.Changeset.change(is_online: target, last_seen_at: now)
        |> Repo.update()
        |> case do
          {:ok, updated} = ok ->
            after_presence_write(updated)
            ok

          err ->
            err
        end
    end
  end

  @doc false
  # Everything a real is_online transition owes the rest of the system. Shared
  # so a batched flush and a write-through produce identical side effects.
  @spec after_presence_write(User.t()) :: :ok
  def after_presence_write(%User{is_online: online?} = user) do
    Accounts.invalidate_user_cache(user)

    if online? do
      Gamend.Analytics.record_activity(user.id, user.last_seen_at || DateTime.utc_now(:second))
    end

    Accounts.broadcast_member_update(user)
    # member_update only reaches the user's lobby and party channels.
    # A friends list, chat sidebar or group roster is neither, so the
    # presence dot there never moved until a full reload; user:<id>
    # is the topic those surfaces can subscribe to per friend.
    Accounts.broadcast_user_update(user)

    hook = if online?, do: :after_user_online, else: :after_user_offline

    Gamend.Async.run(fn ->
      Gamend.Hooks.internal_call(hook, [user])
    end)

    :ok
  end
end
