# `Gamend.Payments.Params`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/payments/params.ex#L1)

Shape-wrangling shared by `Gamend.Payments` and its provider adapters.

Every provider receives a JSON body from somewhere outside — Apple's signed
notifications, Google's RTDN envelopes, Steam's form responses — and each one
needed the same four things: string-keyed maps, an epoch-millis timestamp as
an ISO-8601 string, a positive integer with a fallback, and a required
non-empty string.

So each one had them. `normalize_params/1` and its `normalize_nested/1`
existed verbatim in four modules (Apple twice, once in `Apple.JWS`),
`millis_to_iso8601/1` and `parse_positive_int/2` in two, `required_binary/2`
in two. None of the copies had drifted yet, which is the only reason this is
a tidy-up rather than a bug hunt.

# `currency_decimals`

```elixir
@spec currency_decimals(String.t() | nil) :: 0 | 2 | 3
```

How many decimals `currency`'s minor unit has: 2 for most, 0 for JPY, 3 for KWD.

# `datetime_iso`

```elixir
@spec datetime_iso(term()) :: String.t() | nil
```

A `DateTime` as ISO-8601; `nil` for anything else.

# `merge_payload`

```elixir
@spec merge_payload(map(), map()) :: map()
```

A stored provider payload with newer fields merged over it.

# `millis_to_iso8601`

```elixir
@spec millis_to_iso8601(term()) :: String.t() | nil
```

Epoch milliseconds as an ISO-8601 string; `nil` when it is not one.

# `milliunits_to_minor`

```elixir
@spec milliunits_to_minor(term(), String.t() | nil) :: non_neg_integer() | nil
```

A price in milliunits (a thousandth of the currency's unit: Apple's
`price`, 1990 for 1.99) in the currency's minor unit, rounded; nil when
either is missing.

# `normalize`

```elixir
@spec normalize(term()) :: term()
```

Recursively string-keys a map, so a body that arrived as atoms and one that
arrived as JSON can be read the same way.

# `normalize_currency`

```elixir
@spec normalize_currency(String.t() | nil) :: String.t() | nil
```

An ISO 4217 code in upper case.

# `normalize_private_key`

```elixir
@spec normalize_private_key(String.t()) :: String.t()
```

Turns the literal `\n` sequences a PEM key picks up when it travels through an
environment variable back into real newlines.

# `parse_datetime`

```elixir
@spec parse_datetime(term()) :: DateTime.t() | nil
```

An ISO-8601 string, or a `DateTime`, as a second-precision `DateTime`; `nil` otherwise.

# `parse_int`

```elixir
@spec parse_int(term()) :: integer() | nil
```

An integer, or an integer written as a string. See `Gamend.Parse.integer/1`.

# `parse_positive_int`

```elixir
@spec parse_positive_int(term(), integer()) :: integer()
```

A positive integer, or `default` when the value is missing or not one.

# `present?`

```elixir
@spec present?(term()) :: boolean()
```

Whether `value` is a non-empty string.

# `put_if_present`

```elixir
@spec put_if_present(map(), term(), term(), boolean()) :: map()
```

Puts `value` under `key` when `condition` is true and the value is a non-empty string.

# `required_binary`

```elixir
@spec required_binary(map(), String.t()) :: {:ok, String.t()} | {:error, atom()}
```

Fetches `key` as a non-empty string, or `{:error, :missing_<key>}`.

# `required_value`

```elixir
@spec required_value(map(), term()) :: {:ok, String.t()} | {:error, atom()}
```

A non-empty string, or an integer as its string, at `key`; `{:error, :missing_<key>}` otherwise.

# `unix_seconds_to_datetime`

```elixir
@spec unix_seconds_to_datetime(term()) :: DateTime.t() | nil
```

Epoch seconds (integer or string) as a second-precision `DateTime`; `nil` when it is not one.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
