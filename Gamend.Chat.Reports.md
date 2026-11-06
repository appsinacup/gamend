# `Gamend.Chat.Reports`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/chat/reports.ex#L1)

The chat report queue.

Players report a message through `report_message/3`; the word filter files its
own reports (with `reporter_id` nil) when a `flag` word matches. Moderators
work the queue from the admin console via `list_reports/2` and
`resolve_report/3`.

Reports keep a denormalized `reported_user_id` and `content_snapshot`, so the
queue still makes sense after the message itself is deleted.

# `count_by_status`

```elixir
@spec count_by_status() :: map()
```

Count reports grouped by status, as `%{status => count}`.

# `count_open_reports`

```elixir
@spec count_open_reports() :: non_neg_integer()
```

Count reports still awaiting a moderator.

# `count_recent_by_reporter`

```elixir
@spec count_recent_by_reporter(Ecto.UUID.t()) :: non_neg_integer()
```

Count reports filed by `reporter_id` in the last 24 hours.

Backs the per-player daily cap; unlike the rate limiter this is durable, so
it holds across restarts and every instance.

# `count_reports`

```elixir
@spec count_reports(map()) :: non_neg_integer()
```

Count reports matching `filters`.

# `delete_report`

```elixir
@spec delete_report(Gamend.Chat.Report.t()) ::
  {:ok, Gamend.Chat.Report.t()} | {:error, Ecto.Changeset.t()}
```

Delete a report outright (admin).

# `get_report`

```elixir
@spec get_report(Ecto.UUID.t()) :: Gamend.Chat.Report.t() | nil
```

Fetch one report with its associations loaded.

# `list_reports`

```elixir
@spec list_reports(map(), keyword()) :: [Gamend.Chat.Report.t()]
```

List reports, newest first. Filters: `:status`, `:reported_user_id`,
`:reporter_id`.

# `report_flagged_message`

```elixir
@spec report_flagged_message(Gamend.Chat.Message.t(), [String.t()]) ::
  {:ok, Gamend.Chat.Report.t()} | {:error, term()}
```

File a report on the word filter's behalf (`reporter_id` stays nil).

Called after the flagged message is committed — at filter time it has no id
yet.

# `report_message`

```elixir
@spec report_message(Ecto.UUID.t(), Ecto.UUID.t(), String.t() | nil) ::
  {:ok, Gamend.Chat.Report.t()} | {:error, term()}
```

File a report about `message_id` on behalf of `reporter_id`.

Returns `{:error, :not_found}` for an unknown message, `{:error, :own_message}`
when a player reports themselves, `{:error, :already_reported}` when they have
already reported that message, and `{:error, :report_daily_limit}` once they
are over `max_chat_reports_per_user_per_day`.

The daily cap is enforced here rather than only at the HTTP edge so that a
plugin calling this directly is bounded too. The edge keeps its own rate-limit
check: that one is a cheap in-memory gate, while this counts committed rows,
so it survives a restart and is shared by every instance. Either can reject.

# `resolve_report`

```elixir
@spec resolve_report(Gamend.Chat.Report.t() | Ecto.UUID.t(), String.t(), map()) ::
  {:ok, Gamend.Chat.Report.t()} | {:error, :not_found | Ecto.Changeset.t()}
```

Resolve a report: set its status, note who resolved it and when.

`status` is one of `Gamend.Chat.Report.statuses/0` other than `"open"`.

# `review_report`

```elixir
@spec review_report(Gamend.Chat.Report.t() | Ecto.UUID.t()) ::
  {:ok, Gamend.Chat.Report.t()} | {:error, term()}
```

Claim a report for review (`"open"` → `"reviewing"`).

Purely a signal to other moderators that someone has picked this one up; it
sets no resolution, so the report stays in the queue until it is dismissed or
actioned.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
