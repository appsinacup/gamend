# `Gamend.Payments.Settings`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/payments/settings.ex#L1)

Store credentials, per provider.

`environment` is the global switch between sandbox and real money; each
provider's keys are selected from it, so a sandbox key in production (or the
reverse) is a configuration error rather than a silent test transaction.

These are namespaced away from `Gamend.OAuth.Providers` deliberately:
Apple issues *different* keys for Sign in with Apple and the App Store Server
API, from different portals, and the two must not share one name.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
