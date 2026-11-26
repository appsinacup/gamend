# `Gamend.Sent.SentKind`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/sent/sent_kind.ex#L1)

What a sent email or push was (`Gamend.Sent`): the account's own emails, a
notification, a digest of them, an admin's test, or a push a plugin sent
(`other`).

# `t`

```elixir
@type t() :: String.t()
```

# `account_approved`
*macro* 

# `all`

```elixir
@spec all() :: [t()]
```

Every value.

# `change_email`
*macro* 

# `confirm_account`
*macro* 

# `deletion_warning`
*macro* 

# `digest`
*macro* 

# `login_code`
*macro* 

# `login_link`
*macro* 

# `notification`
*macro* 

# `other`
*macro* 

# `password_code`
*macro* 

# `test`
*macro* 

---

*Consult [api-reference.md](api-reference.md) for complete listing*
