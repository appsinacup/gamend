# `Gamend.Push.DeliveryWorker`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/push/delivery_worker.ex#L1)

Delivers one push message to one token. One job per token is deliberate:
FCM v1 and APNs are one-request-per-token anyway, and it buys exact
per-token Oban retry/backoff — a half-delivered batch job would re-push
duplicates on retry.

Fires `after_push_sent` on every terminal outcome (delivered, token
disabled, permanent failure, or retries exhausted) — never on a transient
error that will retry — and records it for the admin (`Gamend.Sent`), as
the job's `"sent"` says (`Gamend.Push.send_to_user/3`'s options).

---

*Consult [api-reference.md](api-reference.md) for complete listing*
