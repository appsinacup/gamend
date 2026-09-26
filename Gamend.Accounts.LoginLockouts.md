# `Gamend.Accounts.LoginLockouts`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/accounts/login_lockouts.ex#L1)

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

# `check`

```elixir
@spec check(String.t()) :: :ok | {:locked, pos_integer()}
```

`:ok` when `email` may try a password, or `{:locked, seconds}` until it may.

# `clear`

```elixir
@spec clear(String.t()) :: :ok
```

Forget `email`'s failures and lift its lock: a correct password, or an admin.

# `expired_query`

```elixir
@spec expired_query() :: Ecto.Query.t()
```

Rows whose window and lock have both run out. For `Gamend.Retention`.

# `record_failure`

```elixir
@spec record_failure(String.t()) :: :ok | {:locked, pos_integer()}
```

Count a failed password for `email`. Answers `{:locked, seconds}` when this
failure is the one that locks it, `:ok` otherwise.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
