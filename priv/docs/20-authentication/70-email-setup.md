---
icon: hero-envelope
---

# Email Setup

[Email Implementation Docs](https://hexdocs.pm/swoosh/Swoosh.html)

## Choose an Email Provider

Recommended providers:

| Provider | Free tier |
|---|---|
| [Resend](https://resend.com) | 3,000 emails/month |
| [SendGrid](https://sendgrid.com) | 100 emails/day |
| [Mailgun](https://mailgun.com) | 5,000 emails/month |

## Configure Email Secrets

Set these environment variables based on your provider:

```bash
# For Resend:
GAMEND_MAIL_SMTP_USERNAME="resend"
GAMEND_MAIL_SMTP_PASSWORD="your_resend_api_key"
GAMEND_MAIL_SMTP_RELAY="smtp.resend.com"
GAMEND_MAIL_SMTP_PORT=465
GAMEND_MAIL_SMTP_SSL=true
GAMEND_MAIL_SMTP_TLS=never
# Sender configuration (recommended for delivery)
GAMEND_MAIL_SMTP_FROM_NAME="My App"
GAMEND_MAIL_SMTP_FROM_EMAIL="no-reply@yourdomain.com"
```

### From address and domain verification

Many email providers require that the "From" address or sending domain be verified in your SMTP provider dashboard before they'll accept or relay mail (you may see errors like "450 domain not verified"). Configure `GAMEND_MAIL_SMTP_FROM_NAME` and `GAMEND_MAIL_SMTP_FROM_EMAIL` so that your messages use a verified sender and avoid delivery rejections.

If you're not sure what to use, set `GAMEND_MAIL_SMTP_FROM_EMAIL` to an address in a domain you control (eg. `no-reply@yourdomain.com` ) and verify that domain with your provider.

Tip: you can review and test the current runtime SMTP settings in the admin [Admin Configuration](/admin/config) page.

For other providers, adjust the SMTP settings accordingly. The app will automatically detect when email is configured.
