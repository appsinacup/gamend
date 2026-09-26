# `Gamend.Accounts.LoginLockout`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/accounts/login_lockout.ex#L1)

Failed password sign-ins for one email address, and the lock they set.

Fields:

- `key_hash` – SHA-256 of the normalized address; the lookup key. The address
  itself is never stored
- `failures` – failed attempts in the current window
- `window_started_at` – when the current window's first failure happened
- `unlocks_at` – nil, or when the lock the failures set runs out

See `Gamend.Accounts.LoginLockouts`.

# `t`

```elixir
@type t() :: %Gamend.Accounts.LoginLockout{
  __meta__: term(),
  failures: non_neg_integer(),
  id: String.t() | nil,
  inserted_at: DateTime.t() | nil,
  key_hash: binary() | nil,
  unlocks_at: DateTime.t() | nil,
  updated_at: DateTime.t() | nil,
  window_started_at: DateTime.t() | nil
}
```

A row of failed sign-ins for one address.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
