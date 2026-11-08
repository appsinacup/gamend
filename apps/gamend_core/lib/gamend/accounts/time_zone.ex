defmodule Gamend.Accounts.TimeZone do
  @moduledoc """
  A user's time zone, for "their day" and "their evening": an IANA name
  (`"Europe/Bucharest"`) kept in their private preferences
  (`Gamend.Accounts.Preferences`), taken from the browser
  (`Intl.DateTimeFormat().resolvedOptions().timeZone`, sent on connect) or
  chosen in settings. A zone chosen by hand (`choose/2`) stays until the user
  goes back to automatic: the browser no longer overwrites it
  (`manual?/1`). Unknown or unset, everything falls back to UTC.

  The `tz` database is passed to `DateTime.shift_zone/3` explicitly, so a
  host needs no global `:time_zone_database` config.
  """

  alias Gamend.Accounts.Preferences
  alias Gamend.Accounts.User

  @priv "priv"

  @db Tz.TimeZoneDatabase
  @key "timezone"
  @manual "timezone_manual"
  @names_key {__MODULE__, :names}

  @doc "Whether `name` is a time zone the database knows."
  @spec valid?(term()) :: boolean()
  def valid?(name) when is_binary(name) and byte_size(name) in 1..64 do
    match?({:ok, _}, DateTime.shift_zone(DateTime.utc_now(), name, @db))
  end

  def valid?(_name), do: false

  @doc "A user's time zone, or nil when unknown."
  @spec of(User.t() | nil) :: String.t() | nil
  def of(%User{} = user) do
    case Preferences.get(user)[@key] do
      name when is_binary(name) -> if valid?(name), do: name
      _ -> nil
    end
  end

  def of(_user), do: nil

  @doc "Save a user's time zone; an unknown name is refused, the same one is a no-op."
  @spec put(User.t(), String.t()) :: {:ok, User.t()} | {:error, :invalid_time_zone | term()}
  def put(%User{} = user, name) do
    cond do
      not valid?(name) -> {:error, :invalid_time_zone}
      of(user) == name -> {:ok, user}
      true -> Preferences.update(user, &Map.put(&1, @key, name))
    end
  end

  @doc """
  The user's own pick: `name` is kept and the browser stops replacing it;
  `nil` goes back to automatic (the browser's zone, from the next visit).
  """
  @spec choose(User.t(), String.t() | nil) :: {:ok, User.t()} | {:error, term()}
  def choose(%User{} = user, nil), do: Preferences.update(user, &Map.delete(&1, @manual))

  def choose(%User{} = user, name) do
    if valid?(name),
      do: Preferences.update(user, &Map.merge(&1, %{@key => name, @manual => true})),
      else: {:error, :invalid_time_zone}
  end

  @doc "Whether the user picked their time zone by hand (`choose/2`)."
  @spec manual?(User.t() | nil) :: boolean()
  def manual?(user), do: Preferences.get(user)[@manual] == true

  @doc """
  Every time zone a person picks from, sorted: the IANA zones of
  `zone1970.tab` (one per region, not every alias), plus `UTC`. Read once
  from the `tz` package's own data and kept.
  """
  @spec names() :: [String.t()]
  def names do
    case :persistent_term.get(@names_key, nil) do
      nil ->
        names = read_names()
        :persistent_term.put(@names_key, names)
        names

      names ->
        names
    end
  end

  defp read_names do
    :tz
    |> Application.app_dir(@priv)
    |> Path.join("tzdata*/zone1970.tab")
    |> Path.wildcard()
    |> Enum.sort()
    |> List.last()
    |> case do
      nil ->
        ["UTC"]

      path ->
        path
        |> File.stream!()
        |> Stream.reject(&String.starts_with?(&1, "#"))
        |> Stream.map(&(&1 |> String.split("\t") |> Enum.at(2)))
        |> Stream.reject(&is_nil/1)
        |> Enum.map(&String.trim/1)
        |> Kernel.++(["UTC"])
        |> Enum.uniq()
        |> Enum.sort()
    end
  end

  @doc """
  `utc` (default now) in a user's or a zone's local time; UTC when the zone
  is unknown.
  """
  @spec local(User.t() | String.t() | nil, DateTime.t()) :: DateTime.t()
  def local(user_or_zone, utc \\ DateTime.utc_now())

  def local(%User{} = user, utc), do: local(of(user), utc)

  def local(zone, utc) when is_binary(zone) do
    case DateTime.shift_zone(utc, zone, @db) do
      {:ok, local} -> local
      _ -> utc
    end
  end

  def local(_zone, utc), do: utc

  @doc "The user's local date (UTC's when their zone is unknown)."
  @spec local_date(User.t() | String.t() | nil, DateTime.t()) :: Date.t()
  def local_date(user_or_zone, utc \\ DateTime.utc_now()),
    do: user_or_zone |> local(utc) |> DateTime.to_date()

  @doc """
  The moment `date` begins for a user or a zone, as a UTC DateTime (UTC
  midnight when the zone is unknown). Where midnight does not exist (a clock
  change at 00:00), the first moment after it.
  """
  @spec day_start(User.t() | String.t() | nil, Date.t()) :: DateTime.t()
  def day_start(%User{} = user, date), do: day_start(of(user), date)

  def day_start(zone, %Date{} = date) when is_binary(zone) do
    naive = NaiveDateTime.new!(date, ~T[00:00:00])

    case DateTime.from_naive(naive, zone, @db) do
      {:ok, local} -> DateTime.shift_zone!(local, "Etc/UTC", @db)
      {:ambiguous, first, _second} -> DateTime.shift_zone!(first, "Etc/UTC", @db)
      {:gap, _before, just_after} -> DateTime.shift_zone!(just_after, "Etc/UTC", @db)
      {:error, _reason} -> DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
    end
  end

  def day_start(_zone, %Date{} = date), do: DateTime.new!(date, ~T[00:00:00], "Etc/UTC")

  @doc "The hour (0-23) it is for the user now."
  @spec local_hour(User.t() | String.t() | nil, DateTime.t()) :: 0..23
  def local_hour(user_or_zone, utc \\ DateTime.utc_now()), do: local(user_or_zone, utc).hour
end
