# `Gamend.Reports.Notices`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/reports/notices.ex#L1)

The notifications reports send: one standing "N reports waiting" alert per
admin, and a reply to a reporter who had an account.

Same trick as `Gamend.Chat.Moderation.Notices`: the notification table
upserts on `(sender_id, recipient_id, title)` and each notice is sent with
the recipient as its own sender, so an admin keeps one alert whose count
moves rather than one per report, and a reporter one "reviewed" entry.

# `admin_title`

```elixir
@spec admin_title() :: String.t()
```

Title of the admin alert (constant, so alerts collapse into one).

# `default_reporter_message`

```elixir
@spec default_reporter_message(String.t(), String.t() | nil) :: String.t()
```

A starting point for the reply, by the status the report was closed with.
A fixed one ends on what the host pays for it (`Gamend.Reports.reward_text/1`).

# `notify_admins`

```elixir
@spec notify_admins(non_neg_integer()) :: :ok
```

Tell every admin how many reports are open, with a link to the queue
(`"url"`, which `/notifications` and a push open). Nothing is sent at zero:
an emptied queue leaves the last alert as it was, read or not.

# `notify_reporter`

```elixir
@spec notify_reporter(Ecto.UUID.t(), String.t(), String.t()) :: :ok
```

Send `message` to the player who filed a report, under `title` (core's
"Your report was reviewed", or the kind's: `Gamend.Reports.reply_title/1`).

# `reporter_title`

```elixir
@spec reporter_title() :: String.t()
```

Title of the reply a reporter receives.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
