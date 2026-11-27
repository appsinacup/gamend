defmodule Gamend.Accounts.TimeZone do
  @moduledoc """
  A user's time zone, for "their day" and "their evening": an IANA name
  (`"Europe/Bucharest"`) kept in their private preferences
  (`Gamend.Accounts.Preferences`), taken from the browser
  (`Intl.DateTimeFormat().resolvedOptions().timeZone`, sent on connect), a
  client's device (`put_device/2`) or chosen in settings. A zone chosen by
  hand (`choose/2`) stays until the user goes back to automatic: neither the
  browser nor a device replaces it (`manual?/1`). Unknown or unset,
  everything falls back to UTC.

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
  The zone a client's device says the user is in
  (`Gamend.Accounts.Preferences.put_client/3`), saved when
  `device_change/2` says so (a page's on connect is saved with its locale
  in one write); an unknown name is refused.
  """
  @spec put_device(User.t(), String.t()) ::
          {:ok, User.t()} | {:error, :invalid_time_zone | term()}
  def put_device(%User{} = user, name) do
    cond do
      not valid?(name) -> {:error, :invalid_time_zone}
      device_change(user, name) -> Preferences.update(user, &with_device(&1, name))
      true -> {:ok, user}
    end
  end

  @doc """
  The zone worth writing from what a device says (`name`), nil for none: a
  known zone, not the user's already, and the user picked none by hand
  (`manual?/1`). Read from `user` as it was, so the write itself goes
  through `with_device/2`.
  """
  @spec device_change(User.t(), term()) :: String.t() | nil
  def device_change(%User{} = user, name) do
    if valid?(name) and not manual?(user) and of(user) != name, do: name
  end

  @doc """
  The preferences map `prefs` as it is at the write, with a device's
  `name` (nil for none) unless the user picked a zone by hand: for
  `Gamend.Accounts.Preferences.update/2`'s function, so a pick made
  meanwhile stays.
  """
  @spec with_device(map(), String.t() | nil) :: map()
  def with_device(prefs, name) when is_binary(name) do
    if prefs[@manual] == true, do: prefs, else: Map.put(prefs, @key, name)
  end

  def with_device(prefs, nil), do: prefs

  @doc """
  The user's own pick: `name` is kept and the browser stops replacing it;
  `nil` goes back to automatic (the browser's zone, from the next visit).
  """
  @spec choose(User.t(), String.t() | nil) :: {:ok, User.t()} | {:error, term()}
  def choose(%User{} = user, name) do
    if is_nil(name) or valid?(name),
      do: Preferences.update(user, &chosen(&1, name)),
      else: {:error, :invalid_time_zone}
  end

  @doc """
  The preferences map `prefs` with the user's pick (`choose/2`): `name`
  kept by hand, nil back to automatic (the zone stays until a device
  sends its own), `:keep` as it is. For a writer that
  saves it with other preferences at once.
  """
  @spec chosen(map(), String.t() | nil | :keep) :: map()
  def chosen(prefs, :keep), do: prefs
  def chosen(prefs, nil), do: Map.delete(prefs, @manual)

  def chosen(prefs, name) when is_binary(name),
    do: Map.merge(prefs, %{@key => name, @manual => true})

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
