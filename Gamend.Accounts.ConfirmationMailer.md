# `Gamend.Accounts.ConfirmationMailer`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/accounts/confirmation_mailer.ex#L1)

Sends a new account's confirmation email, off the request.

Registration enqueues this in the transaction that inserts the user, so a
committed account always has its email queued and the transaction holds the
database for two inserts rather than an SMTP conversation. On SQLite the
repo has a single connection, and a registration that sent its mail inline
stalled every other query in the server for the length of the SMTP session.

The job mints the link token and the code itself: either in the job's args
would sit in the jobs table in the clear. A failed send is retried with
backoff, minting new ones each attempt (unused links expire; a new code
replaces the last). A job that outlives `timeout/1`
is killed, so a hung relay costs one `mailers` slot, never the database.

# `new_for`

```elixir
@spec new_for(
  Gamend.Accounts.User.t(),
  (String.t() -&gt; String.t()),
  module(),
  keyword()
) ::
  Ecto.Changeset.t()
```

The job for `user`. `confirmation_url_fun` maps an encoded token to its URL
and runs now, with a placeholder; `notifier` delivers. `opts` go to
`Oban.Worker.new/2` (a resend passes `:unique`), but for `code:`, which
sends only six digits, to an account confirmed or not: `:reset` to set a
new password (`Registration.request_password_reset/3`), `:login` to sign
in (`Registration.request_login_code/3`).

---

*Consult [api-reference.md](api-reference.md) for complete listing*
