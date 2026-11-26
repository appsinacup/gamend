# `Gamend.Sent.SentStatus`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/sent/sent_status.ex#L1)

How a send ended (`Gamend.Sent`): `sent`, `failed` (the relay or the push
provider refused it, or it ran out of retries), or `invalid` (the device's
token is dead and was turned off).

# `t`

```elixir
@type t() :: String.t()
```

# `all`

```elixir
@spec all() :: [t()]
```

Every value.

# `failed`
*macro* 

# `invalid`
*macro* 

# `sent`
*macro* 

---

*Consult [api-reference.md](api-reference.md) for complete listing*
