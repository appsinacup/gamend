# `Gamend.Accounts.TimeZone`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/accounts/time_zone.ex#L1)

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

# `choose`

```elixir
@spec choose(Gamend.Accounts.User.t(), String.t() | nil) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, term()}
```

The user's own pick: `name` is kept and the browser stops replacing it;
`nil` goes back to automatic (the browser's zone, from the next visit).

# `chosen`

```elixir
@spec chosen(map(), String.t() | nil | :keep) :: map()
```

The preferences map `prefs` with the user's pick (`choose/2`): `name`
kept by hand, nil back to automatic (the zone stays until a device
sends its own), `:keep` as it is. For a writer that
saves it with other preferences at once.

# `day_start`

```elixir
@spec day_start(Gamend.Accounts.User.t() | String.t() | nil, Date.t()) :: DateTime.t()
```

The moment `date` begins for a user or a zone, as a UTC DateTime (UTC
midnight when the zone is unknown). Where midnight does not exist (a clock
change at 00:00), the first moment after it.

# `device_change`

```elixir
@spec device_change(Gamend.Accounts.User.t(), term()) :: String.t() | nil
```

The zone worth writing from what a device says (`name`), nil for none: a
known zone, not the user's already, and the user picked none by hand
(`manual?/1`). Read from `user` as it was, so the write itself goes
through `with_device/2`.

# `local`

```elixir
@spec local(Gamend.Accounts.User.t() | String.t() | nil, DateTime.t()) :: DateTime.t()
```

`utc` (default now) in a user's or a zone's local time; UTC when the zone
is unknown.

# `local_date`

```elixir
@spec local_date(Gamend.Accounts.User.t() | String.t() | nil, DateTime.t()) ::
  Date.t()
```

The user's local date (UTC's when their zone is unknown).

# `local_hour`

```elixir
@spec local_hour(Gamend.Accounts.User.t() | String.t() | nil, DateTime.t()) :: 0..23
```

The hour (0-23) it is for the user now.

# `manual?`

```elixir
@spec manual?(Gamend.Accounts.User.t() | nil) :: boolean()
```

Whether the user picked their time zone by hand (`choose/2`).

# `names`

```elixir
@spec names() :: [String.t()]
```

Every time zone a person picks from, sorted: the IANA zones of
`zone1970.tab` (one per region, not every alias), plus `UTC`. Read once
from the `tz` package's own data and kept.

# `of`

```elixir
@spec of(Gamend.Accounts.User.t() | nil) :: String.t() | nil
```

A user's time zone, or nil when unknown.

# `put`

```elixir
@spec put(Gamend.Accounts.User.t(), String.t()) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, :invalid_time_zone | term()}
```

Save a user's time zone; an unknown name is refused, the same one is a no-op.

# `put_device`

```elixir
@spec put_device(Gamend.Accounts.User.t(), String.t()) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, :invalid_time_zone | term()}
```

The zone a client's device says the user is in
(`Gamend.Accounts.Preferences.put_client/3`), saved when
`device_change/2` says so (a page's on connect is saved with its locale
in one write); an unknown name is refused.

# `valid?`

```elixir
@spec valid?(term()) :: boolean()
```

Whether `name` is a time zone the database knows.

# `with_device`

```elixir
@spec with_device(map(), String.t() | nil) :: map()
```

The preferences map `prefs` as it is at the write, with a device's
`name` (nil for none) unless the user picked a zone by hand: for
`Gamend.Accounts.Preferences.update/2`'s function, so a pick made
meanwhile stays.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
