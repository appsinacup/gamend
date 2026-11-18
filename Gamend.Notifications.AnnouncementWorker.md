# `Gamend.Notifications.AnnouncementWorker`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/notifications/announcement_worker.ex#L1)

Sends one batch of an announcement (`Gamend.Notifications.Announcements`)
and queues the next. Unique per announcement (`"id"`) and cursor
(`"after"`), forever: a job rescued after a crash cannot start a second
chain behind the first.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
