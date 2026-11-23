# `Gamend.Accounts.Sessions`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/accounts/sessions.ex#L1)

Signing in and staying signed in: session and magic-link tokens, the emails
that carry them, and listing or revoking a user's sessions.

Split out of `Gamend.Accounts`, which still exposes every function here under
the same name. Revoking *every* token on a credential change stays there, next
to the writes that trigger it.

# `confirm_and_log_in`

```elixir
@spec confirm_and_log_in(Gamend.Accounts.User.t()) ::
  {:ok, {Gamend.Accounts.User.t(), [Gamend.Accounts.UserToken.t()]}}
  | {:error, Ecto.Changeset.t() | term()}
```

An account not yet confirmed, signed in by proof of its inbox (a magic
link, or the emailed code of `Gamend.Accounts.login_user_by_code/2`):
confirmed, its password dropped and every token revoked. Dropping the
password is what makes confirming safe (case 3 of
`login_user_by_magic_link/1`); a user without one is unchanged by it.

# `count_user_tokens`

```elixir
@spec count_user_tokens(Ecto.UUID.t()) :: non_neg_integer()
```

Counts tokens for a given user.

# `delete_user_session_token`

```elixir
@spec delete_user_session_token(binary()) :: :ok
```

Deletes the signed token with the given context.

# `deliver_login_instructions`

```elixir
@spec deliver_login_instructions(Gamend.Accounts.User.t(), (String.t() -&gt; String.t())) ::
  {:ok, Swoosh.Email.t()} | {:error, term()}
```

Delivers the magic link login instructions to the given user.

# `deliver_user_update_email_instructions`

```elixir
@spec deliver_user_update_email_instructions(
  Gamend.Accounts.User.t(),
  String.t(),
  (String.t() -&gt; String.t())
) :: {:ok, Swoosh.Email.t()} | {:error, term()}
```

Delivers the update email instructions to the given user.

## Examples

    iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm_email/#{&1}"))
    {:ok, %{to: ..., body: ...}}

# `generate_user_session_token`

```elixir
@spec generate_user_session_token(Gamend.Accounts.User.t()) :: binary()
```

Generates a session token.

# `get_user_by_magic_link_token`

```elixir
@spec get_user_by_magic_link_token(String.t()) :: Gamend.Accounts.User.t() | nil
```

Gets the user with the given magic link token.

# `get_user_by_session_token`

```elixir
@spec get_user_by_session_token(binary()) ::
  {Gamend.Accounts.User.t(), DateTime.t()} | nil
```

Gets the user with the given signed token.

If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.

# `list_user_tokens`

```elixir
@spec list_user_tokens(Ecto.UUID.t(), keyword()) :: [Gamend.Accounts.UserToken.t()]
```

Lists tokens for a given user, optionally filtered by context.

# `logged_in`

```elixir
@spec logged_in(Gamend.Accounts.User.t()) :: :ok
```

What a sign-in sets off, off the request: the hook and the quest event.

# `login_user_by_magic_link`

```elixir
@spec login_user_by_magic_link(String.t()) ::
  {:ok, {Gamend.Accounts.User.t(), [Gamend.Accounts.UserToken.t()]}}
  | {:error, :not_found | Ecto.Changeset.t() | term()}
```

Logs the user in by magic link.

There are three cases to consider:

1. The user has already confirmed their email. They are logged in
   and the magic link is expired.

2. The user has not confirmed their email. Opening the link proves they
   own the inbox, so the user gets confirmed, logged in, and all tokens -
   including session ones - are expired.

3. As 2, with a password set: registered when `POST /api/v1/register` still
   took one, or a guest account given an email, and never confirmed. The
   password is removed as the email is confirmed. Whoever set it did so
   before anyone proved they own the inbox, so it may be someone else's,
   and kept it would sign them into the account its owner has just claimed
   (the "Mixing magic link and password registration" section of
   `mix help phx.gen.auth`). The owner sets a new one in settings. The
   confirmation email's link removes it the same way
   (`Gamend.Accounts.confirm_user_by_token/1`); its code sets the password.

# `revoke_all_user_sessions`

```elixir
@spec revoke_all_user_sessions(Ecto.UUID.t()) :: {non_neg_integer(), nil}
```

Revokes all session tokens for a user (mass logout).

# `session_tokens`

```elixir
@spec session_tokens(Ecto.UUID.t()) :: [%{token: binary()}]
```

A user's browser session tokens, as `[%{token: binary}]`: what
`GamendWeb.UserAuth.disconnect_sessions/1` takes to close their open pages.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
