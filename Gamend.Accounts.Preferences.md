# `Gamend.Accounts.Preferences`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/accounts/preferences.ex#L1)

A user's private settings (`users.preferences`): what only they see and
change — notification choices (`Gamend.Notifications.Preferences`), their
time zone (`Gamend.Accounts.TimeZone`) and the site language they last used
(`locale/1`, for email written to them).

Kept out of `metadata` on purpose: metadata is sent to friends, lobby and
party members (`User.serialize_brief/1`), and a user's time zone or email
choices are nobody else's business. Every user serializer lists its fields,
and this one is in none of them.

Writes are serialized per user (`Gamend.Lock`) and re-read the row, so two
settings changed at once cannot lose each other.

Some are set by the page itself (`put_client/3`, `PUT /preferences`): the
site's theme, and whatever a host adds to
`config :gamend_core, :client_preferences` (a map of key to allowed
values, e.g. `%{"game_sounds" => ~w(on off)}`, or to a `{module,
function}` answering them, e.g. the languages the site serves). Only
those keys, with only those values, can be written that way. A client
also says its device's time zone that way (`"timezone"`, an IANA name):
kept as the browser's is (`Gamend.Accounts.TimeZone.put_device/2`),
unless the user chose one by hand.

Those, and the time zone, are what a client reads back, as the row
`preferences` (`row/1`, `Gamend.KV.Computed`): its owner's only, moved by
every change here, so a second device sees the theme or the sound change
the first made.

# `client_keys`

```elixir
@spec client_keys() :: %{required(String.t()) =&gt; [String.t()]}
```

The preferences a page may set (`put_client/3`) from a list: core's
`theme` and the host's `:client_preferences`, each with its allowed
values. The device's `"timezone"` is set there too, from any known zone.

# `get`

```elixir
@spec get(Gamend.Accounts.User.t() | nil) :: map()
```

A user's preferences map (string keys), empty when none are set.

# `locale`

```elixir
@spec locale(Gamend.Accounts.User.t() | nil) :: String.t() | nil
```

The site language the user last read in (a locale code), or nil.

# `put_client`

```elixir
@spec put_client(Gamend.Accounts.User.t(), String.t(), String.t()) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, term()}
```

Save a preference a page set: `{:ok, user}`, or `{:error, :invalid}` for a
key or value not in `client_keys/0`. The theme's `"system"` removes the
saved theme, so the device decides again. `"timezone"` is no key of
`client_keys/0`: its value is any known IANA zone, the device's, saved
unless the user picked one by hand (`TimeZone.put_device/2`); a host's
`:client_preferences` entry for it is not read.

# `row`

```elixir
@spec row(%{user_id: String.t() | nil}) :: map() | nil
```

The row `preferences` (`Gamend.KV.Computed`) for the user in `scope`:
what they set of `client_keys/0` (no theme where the device decides) and
their `"timezone"`, or nil with no such user.

# `theme`

```elixir
@spec theme(Gamend.Accounts.User.t() | nil) :: String.t() | nil
```

The theme the user saved, `"dark"` or `"light"`, or nil.

# `update`

```elixir
@spec update(Gamend.Accounts.User.t(), (map() -&gt; map())) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, term()}
```

Change a user's preferences: `fun` gets the current map and returns the
new one. `{:ok, user}` with the saved user; the row `preferences` moves.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
