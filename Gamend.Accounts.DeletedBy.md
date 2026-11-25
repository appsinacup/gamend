# `Gamend.Accounts.DeletedBy`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/accounts/deleted_by.ex#L1)

Who or what deleted an account, the `by` of the `accounts.deleted` event
`Gamend.Accounts.delete_user/2` counts:

  * `self` — the player, from their settings or the API (`request_deletion/2`,
    at once or when the grace days run out);
  * `admin` — an admin, from the admin pages or the admin API;
  * `guest_merge` — a guest signed in to an account and was merged into it;
  * `orphan` — a provider-only account its identity's owner removed while
    linking that provider to the account they were signed in to;
  * `anonymous`, `unconfirmed`, `inactive` — a `Gamend.Retention` sweep.

# `t`

```elixir
@type t() :: String.t()
```

# `admin`
*macro* 

# `all`

```elixir
@spec all() :: [t()]
```

Every value.

# `anonymous`
*macro* 

# `guest_merge`
*macro* 

# `inactive`
*macro* 

# `orphan`
*macro* 

# `self`
*macro* 

# `unconfirmed`
*macro* 

---

*Consult [api-reference.md](api-reference.md) for complete listing*
