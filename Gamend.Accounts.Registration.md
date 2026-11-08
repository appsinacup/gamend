# `Gamend.Accounts.Registration`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/accounts/registration.ex#L1)

Creating an account and confirming it: registration, the generated username,
the first-user-is-admin rule and account activation, and email confirmation.

Split out of `Gamend.Accounts`, which still exposes every function here under
the same name.

# `change_user_registration`

```elixir
@spec change_user_registration(Gamend.Accounts.User.t(), map()) :: Ecto.Changeset.t()
```

# `change_user_registration_for_validation`

```elixir
@spec change_user_registration_for_validation(Gamend.Accounts.User.t(), map()) ::
  Ecto.Changeset.t()
```

A registration changeset for live form feedback, with the uniqueness query
skipped.

`change_user_registration/2` runs `unsafe_validate_unique`, which is right on
submit and wrong on every keystroke: the registration form's `validate` event
is neither rate-limited nor captcha'd, so running it there turned the form
into an unauthenticated oracle for "does this address have an account here?",
one query per character typed. Submitting still checks, and the unique index
is what actually enforces it.

Separate function rather than an option, because `mix gen.sdk` cannot generate
a stub for a function carrying two default arguments.

# `confirm_user`

```elixir
@spec confirm_user(Gamend.Accounts.User.t()) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, Ecto.Changeset.t()}
```

Confirms a user's email by setting confirmed_at timestamp.

## Examples

    iex> confirm_user(user)
    {:ok, %User{}}

# `confirm_user_by_code`

```elixir
@spec confirm_user_by_code(String.t(), String.t(), String.t()) ::
  {:ok, {Gamend.Accounts.User.t(), [Gamend.Accounts.UserToken.t()]}}
  | {:error, :invalid_code | {:locked, pos_integer()} | Ecto.Changeset.t()}
```

Confirms the unconfirmed account registered to `email` with the code from
its confirmation email, sets its password, and returns it signed in by the
caller (`POST /api/v1/register/confirm`).

The code is the proof that the caller reads the inbox, which is why the
password is set here and never at registration.

- `{:error, %Ecto.Changeset{}}` for a password the account would refuse.
  It is checked before the code, so it costs no attempt and says nothing
  about the code.
- `{:error, :invalid_code}` for a wrong, spent or expired code, an address
  with no unconfirmed account, or one already confirmed: the same answer,
  so it tells no one which addresses are registered.
- `{:error, {:locked, seconds}}`: a wrong code counts toward the address's
  sign-in lockout (`Gamend.Accounts.LoginLockouts`), shared with passwords.
  The failure that locks it also voids the code, so guessing needs a fresh
  email for every few tries; the link keeps working.

Success revokes every earlier token of the account, as a password change
does, and returns them so the caller can disconnect the sessions.

# `confirm_user_by_token`

```elixir
@spec confirm_user_by_token(String.t()) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, :invalid | :not_found}
```

Confirm a user by the token in the emailed link (context: "confirm").

Returns {:ok, user} when the token is valid and user was confirmed.
Returns {:error, :not_found} or {:error, :invalid} when token is invalid/expired.

Confirming spends the link and the code sent with it. An account confirmed
this way has no password: registration takes none, and one set before the
address was proved is removed, since whoever set it may not own the inbox
(an account registered when the API still took one, or a guest account
that was given an email). Its owner sets one in settings, where the link's
page signs them in, or confirms with the code instead.

# `deliver_user_confirmation_instructions`

```elixir
@spec deliver_user_confirmation_instructions(Gamend.Accounts.User.t(), (String.t() -&gt;
                                                                    String.t())) ::
  {:ok, Swoosh.Email.t()} | {:error, :already_confirmed | term()}
```

# `drop_email_taken`

```elixir
@spec drop_email_taken(Ecto.Changeset.t()) :: Ecto.Changeset.t()
```

`changeset` without the refusal `email_taken?/1` finds, valid when it was the only one.

# `email_taken?`

```elixir
@spec email_taken?(Ecto.Changeset.t()) :: boolean()
```

Whether `changeset` refuses its email because another account has it.

The person who typed the address may not learn that: it would say which
addresses have accounts. The caller answers as for a free address, and the
owner hears by email (`notify_existing_account/4`).

# `get_user_by_confirm_token`

```elixir
@spec get_user_by_confirm_token(String.t()) :: Gamend.Accounts.User.t() | nil
```

The account an emailed confirmation link belongs to, or `nil` for a link
that is malformed, spent or expired. It only reads: the page the link opens
shows the account, and confirming waits for its button
(`confirm_user_by_token/1`), so a mail scanner that opens every link in an
email confirms nothing and spends nothing.

# `notify_existing_account`

```elixir
@spec notify_existing_account(
  String.t(),
  (String.t() -&gt; String.t()),
  (String.t() -&gt; String.t()),
  module()
) :: :ok
```

Someone tried to sign up with `email`, which already has an account: the
confirmation again if it never confirmed, else a login link. In the
background, so the sign-up answers as soon as it does for a free address.

# `register_unconfirmed_user_and_deliver`

```elixir
@spec register_unconfirmed_user_and_deliver(
  Gamend.Types.user_registration_attrs(),
  (String.t() -&gt; String.t()),
  module()
) :: {:ok, Gamend.Accounts.User.t()} | {:error, Ecto.Changeset.t() | term()}
```

`register_user_and_deliver/3` for a game client (`POST /api/v1/register`):
every account it makes starts unconfirmed and is sent the email, the first
one too. A client has no page to sign the first account in, and with no
password it could not sign in any other way, so it confirms with the code
like everyone else (`confirm_user_by_code/3`). It still becomes the admin.

# `register_user`

```elixir
@spec register_user(Gamend.Types.user_registration_attrs()) ::
  {:ok, Gamend.Accounts.User.t()} | {:error, Ecto.Changeset.t()}
```

Registers a user.

## Attributes

See `t:Gamend.Types.user_registration_attrs/0` for available fields.

## Examples

    iex> register_user(%{email: "user@example.com", password: "secret123"})
    {:ok, %User{}}

    iex> register_user(%{email: "invalid"})
    {:error, %Ecto.Changeset{}}

# `register_user_and_deliver`

```elixir
@spec register_user_and_deliver(
  Gamend.Types.user_registration_attrs(),
  (String.t() -&gt; String.t()),
  module()
) :: {:ok, Gamend.Accounts.User.t()} | {:error, Ecto.Changeset.t() | term()}
```

Register a user and queue its confirmation email.

`confirmation_url_fun` maps an encoded token to the confirmation URL. The
email goes out from the `mailers` queue (`Gamend.Accounts.ConfirmationMailer`),
enqueued in the transaction that inserts the user: the call returns once
both are committed, without waiting on SMTP, and a failed send is retried
there. The email carries a link and a code (`confirm_user_by_code/3`).

The first user becomes the admin and is confirmed, with no email: the
browser form signs it in itself. A caller that cannot uses
`register_unconfirmed_user_and_deliver/3`.

No password is taken. Whoever registers an address has not shown they own
it, so a password chosen now could be someone else's, and it would sign them
into the account once the address's owner confirmed it. The password is set
after the inbox is proved: with the code, or in the settings the link opens.

# `resend_confirmation`

```elixir
@spec resend_confirmation(String.t(), (String.t() -&gt; String.t()), module()) :: :ok
```

Sends the confirmation email again, with a new code, to the unconfirmed
account registered to `email` (`POST /api/v1/register/resend`). Only the
newest code works; links already sent keep working until they expire.

Always `:ok`, whether or not such an account exists, so it tells no one
which addresses are registered. At most one email per account per minute
is queued; the rest are dropped.

# `upgrade_anonymous_user_and_deliver`

```elixir
@spec upgrade_anonymous_user_and_deliver(
  Gamend.Accounts.User.t(),
  Gamend.Types.user_registration_attrs(),
  (String.t() -&gt; String.t()),
  module()
) :: {:ok, Gamend.Accounts.User.t()} | {:error, Ecto.Changeset.t() | term()}
```

Sign-up for a visitor who is already playing on an anonymous account: the
email goes on THAT account, and the confirmation email is queued exactly as
for a new one. Same account id, so everything it holds stays; the link in the
email signs in to it on any device and confirms the address.

`{:error, :not_anonymous}` for an account that already has an identity.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
