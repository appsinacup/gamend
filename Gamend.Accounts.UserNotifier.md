# `Gamend.Accounts.UserNotifier`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/accounts/user_notifier.ex#L1)

Small helpers used to deliver transactional emails for the Accounts flow
(confirmation, magic link, and email change instructions).

These functions are thin wrappers over the configured application Mailer.

# `deliver_account_activated`

Deliver a notification that the user's account has been activated by an admin.
Silently returns `{:ok, :no_email}` if the user has no email address.

# `deliver_confirmation_instructions`

Deliver the email that confirms an account: a link, and with `code` the
same confirmation as six digits to type into the game. A magic link sent to
an account not yet confirmed comes here too, with no code.

# `deliver_inactivity_warning`

Warn a user that their account will be deleted after `days` of inactivity.

Sent by `Gamend.Accounts.InactivityNotifier` ahead of the retention
sweep; signing in resets the clock, so the action the mail asks for is just
"log in".

# `deliver_login_instructions`

Deliver instructions to log in with a magic link.

# `deliver_notification`

A notification the user chose to get by email
(`Gamend.Notifications.notify/3`). `unsubscribe_url` ends the body and goes
in the `List-Unsubscribe` headers too (RFC 8058 one-click), so a mail
client's own "Unsubscribe" button works without opening the site.

# `deliver_reset_code`

Deliver the six digits a game asks for to set a new password: a password
forgotten, on a client with no page to open a link in.

# `deliver_test_email`

Send a simple test email to the given recipient address. Used by admin tools
to verify SMTP configuration and delivery.
Returns the same shape as `deliver/3`.

# `deliver_update_email_instructions`

Deliver instructions to update a user email.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
