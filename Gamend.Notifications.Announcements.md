# `Gamend.Notifications.Announcements`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/notifications/announcements.ex#L1)

One notice to every player at once (`Gamend.Notifications.announce_to_all/1`),
sent from the admin console or the admin API.

Each player gets it through `Gamend.Notifications.notify/3` in the
"announcements" group (`Gamend.Notifications.Preferences`), so their choices
for it apply: the site's row always, the phone unless they turned it off,
email only if they turned it on. `"site_only"` sends neither.

Who: every activated account that is not banned, guests included.

Delivery is one `Gamend.Notifications.AnnouncementWorker` job per batch of
accounts, in id order: a job sends its batch, then queues the next one. A
send to many players never holds one long job, and a restart picks up at the
batch it was on. A batch that fails is retried whole, which repeats nothing a
player sees twice: the site's row is the player's own (sender = recipient)
and upserted on its title, a second push replaces the first on the device
(one collapse key per group), and the email is unique per hour.

The same title as an earlier announcement refreshes that row (new text,
unread again) rather than adding a second one.

# `changeset`

```elixir
@spec changeset(map()) :: Ecto.Changeset.t()
```

The form behind an announcement: `title` (required), `content`, `url` (a
path on this site the notice leads to, such as `/news`) and `site_only`.

# `count_audience`

```elixir
@spec count_audience() :: non_neg_integer()
```

How many accounts an announcement goes to: every activated one.

# `send_to_all`

```elixir
@spec send_to_all(map()) :: {:ok, non_neg_integer()} | {:error, Ecto.Changeset.t()}
```

Queue `attrs` (see `changeset/1`) for every player. Answers how many
accounts it is going to (banned ones are skipped as it reaches them).

---

*Consult [api-reference.md](api-reference.md) for complete listing*
