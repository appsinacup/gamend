# `Gamend.Payments.Notices`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/payments/notices.ex#L1)

Telling a user about an entitlement given to them on purpose: a trial
lengthened by support, a reward. Only when the grant asks for it (`notify:
true` on `Gamend.Payments.grant_entitlement/3` or `extend_entitlement/3`, the
"Tell user" box on Admin > Payments).

An entitlement is written far more often than anyone wants to hear about it
(each Stripe renewal, a host's own bookkeeping in its metadata), so
`after_entitlement_changed` is not the place for this, and a write that did
not ask says nothing.

It goes out through `Gamend.Notifications.notify/3`, in core's `"payments"`
group, so the user's choices for that group, its unsubscribe link and its
limits hold: one row per title, refreshed rather than stacked, and one email
per subject an hour. The `before_entitlement_notice/2` hook can change the
words, the link or the group, or refuse to send it. It cannot go around
those limits, since it only answers what to send.

# `entitlement_given`

```elixir
@spec entitlement_given(Gamend.Payments.Entitlement.t()) :: :ok
```

Tell the owner of `entitlement`, in the background: a grant never fails for this.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
