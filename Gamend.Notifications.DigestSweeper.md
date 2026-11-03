# `Gamend.Notifications.DigestSweeper`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/notifications/digest_sweeper.ex#L1)

Hourly, queues the digest emails that are due
(`Gamend.Notifications.Digest.sweep/1`). `enabled: false` in the app config
keeps it supervised but idle, for test suites. Safe on several nodes at
once: the job is unique per user and group.

# `child_spec`

Returns a specification to start this module under a supervisor.

See `Supervisor`.

# `start_link`

---

*Consult [api-reference.md](api-reference.md) for complete listing*
