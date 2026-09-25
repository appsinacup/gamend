defmodule Gamend.Accounts.LoginLockouts do
  @moduledoc """
  Per-account lockout after repeated failed password sign-ins.

  The per-IP `auth` rate limit caps how fast one address can guess; it does
  nothing against guesses spread over many addresses, which is what a botnet
  aimed at one account does. So failures are also counted per email address:
  `auth.lockout_attempts` of them within `auth.lockout_window_minutes` lock
  password sign-in for that address for `auth.lockout_minutes`. A correct
  password clears the count.

  ## What the lock does and does not do

  - It is keyed by the address, not by an account: an address nobody
    registered counts and locks the same way, so a lock tells no one which
    addresses exist.
  - While locked, the password is not even checked, and a correct one is
    refused too: otherwise the lock would still answer "right" or "wrong".
  - Only password sign-in is locked. An emailed login link and provider
    sign-ins still work, so the owner of a locked account can still get in
    while someone else is failing at the password. That is also why the lock
    cannot be turned into a way to keep a player out.

  Counts live in the database, so they hold across every instance.
  `Gamend.Retention` prunes rows whose window and lock have both run out.
  """

  import Ecto.Query

  alias Gamend.Accounts.LoginLockout
  alias Gamend.Repo

  @doc """
  `:ok` when `email` may try a password, or `{:locked, seconds}` until it may.
  """
  @spec check(String.t()) :: :ok | {:locked, pos_integer()}
  def check(email) when is_binary(email) do
    if enabled?() do
      now = DateTime.utc_now(:second)

      unlocks_at =
        Repo.one(
          from(l in LoginLockout,
            where: l.key_hash == ^key(email) and l.unlocks_at > ^now,
            select: l.unlocks_at
          )
        )

      if unlocks_at, do: {:locked, max(DateTime.diff(unlocks_at, now), 1)}, else: :ok
    else
      :ok
    end
  end

  @doc """
  Count a failed password for `email`. Answers `{:locked, seconds}` when this
  failure is the one that locks it, `:ok` otherwise.
  """
  @spec record_failure(String.t()) :: :ok | {:locked, pos_integer()}
  def record_failure(email) when is_binary(email) do
    if enabled?() do
      key = key(email)

      {:ok, result} =
        Gamend.Lock.serialize("login_lockout", Base.encode16(key), fn -> count_failure(key) end)

      result
    else
      :ok
    end
  end

  @doc "Forget `email`'s failures and lift its lock: a correct password, or an admin."
  @spec clear(String.t()) :: :ok
  def clear(email) when is_binary(email) do
    query = from(l in LoginLockout, where: l.key_hash == ^key(email))

    # Checked first: this runs on every successful sign-in, and on SQLite even a
    # DELETE that matches nothing takes the write lock.
    if Repo.exists?(query), do: Repo.delete_all(query)
    :ok
  end

  @doc "Rows whose window and lock have both run out. For `Gamend.Retention`."
  @spec expired_query() :: Ecto.Query.t()
  def expired_query do
    # A row is written on every failure, and a lock starts on the failure that
    # set it, so an `updated_at` older than both the window and the lock means
    # both are over.
    minutes = max(window_minutes(), lockout_minutes())
    cutoff = DateTime.add(DateTime.utc_now(:second), -minutes, :minute)

    from(l in LoginLockout, where: l.updated_at < ^cutoff)
  end

  # Inside `Lock.serialize/3`, so two failures at once cannot both read the
  # same count.
  defp count_failure(key) do
    now = DateTime.utc_now(:second)
    window_opened = DateTime.add(now, -window_minutes(), :minute)

    row =
      Repo.one(from(l in LoginLockout, where: l.key_hash == ^key)) || %LoginLockout{key_hash: key}

    {failures, started} =
      if row.window_started_at && DateTime.after?(row.window_started_at, window_opened),
        do: {row.failures + 1, row.window_started_at},
        else: {1, now}

    # The failure that locks also starts a fresh count, so once the lock runs
    # out the address gets the full number of attempts again.
    {changes, result} =
      if failures >= attempts() do
        unlocks_at = DateTime.add(now, lockout_minutes(), :minute)

        {%{failures: 0, window_started_at: now, unlocks_at: unlocks_at},
         {:locked, DateTime.diff(unlocks_at, now)}}
      else
        {%{failures: failures, window_started_at: started}, :ok}
      end

    # `force: true` stamps `updated_at` even when nothing else changed: the
    # retention prune reads it.
    row |> Ecto.Changeset.change(changes) |> Repo.insert_or_update!(force: true)
    result
  end

  defp key(email), do: :crypto.hash(:sha256, email |> String.trim() |> String.downcase())

  defp enabled?, do: attempts() > 0
  defp attempts, do: Gamend.Settings.get(Gamend.Accounts, :lockout_attempts)
  defp window_minutes, do: max(Gamend.Settings.get(Gamend.Accounts, :lockout_window_minutes), 1)
  defp lockout_minutes, do: max(Gamend.Settings.get(Gamend.Accounts, :lockout_minutes), 1)
end
