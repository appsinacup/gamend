# `Gamend.Accounts.DeletionReason`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/accounts/deletion_reason.ex#L1)

Why a player deleted their own account: the optional answer on the
account settings page, counted by `Gamend.Accounts.request_deletion/2` as
the `reason` of `accounts.deletion_requested`. A fixed list, never free
text, so nothing the player typed outlives the account.

One reason per kind of cause, the set most account-deletion surveys share:
stopped using it, not a fit, switched away, it broke, privacy, other.

# `t`

```elixir
@type t() :: String.t()
```

# `all`

```elixir
@spec all() :: [t()]
```

Every value.

# `not_for_me`
*macro* 

# `not_using`
*macro* 

# `other`
*macro* 

# `other_app`
*macro* 

# `privacy`
*macro* 

# `problems`
*macro* 

---

*Consult [api-reference.md](api-reference.md) for complete listing*
