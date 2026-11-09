# `Gamend.Reports`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/reports.ex#L1)

Reports about the game itself: a page that broke, a word that is wrong, an
image that does not match. Filed from `/report` or `POST /api/v1/reports`,
with or without an account, and worked from `/admin/reports`.

Not chat reports (`Gamend.Chat.Reports`): those are about a player and lead
to mutes and warnings. These are about content and lead to a fix.

## Kinds

What a report can be about is a `Gamend.Reports.Kind`. Core has `"page"`; a
host adds its own with `config :gamend_core, :report_kinds, [Mod, ...]`. A
configured kind with the key `"page"` replaces core's.

## Limits

Anyone may file one, so every path is capped: per IP per hour at the edge
(`ip_hourly_limit`, counted in memory by the web layer), per account per day
and across everyone per day here (`user_daily_limit`, `daily_limit`, counted
on committed rows, so a restart does not reset them). A signed-in player
cannot file the same open report twice. Nothing about a sender is stored
beyond what they typed and, when signed in, their user id.

## Hooks

  * `before_report_create/1` — pipeline: `{:ok, attrs}` to file it (changed
    or not), `{:error, reason}` to refuse it.
  * `after_report_created/1` — fire-and-forget.
  * `after_report_resolved/1` — fire-and-forget, each time an open report
    is closed (fixed, wontfix, duplicate). A report reopened and closed
    again fires it again, so anything it pays should carry an idempotency
    key on the report id.

## Rewards

Core pays nothing for a report. A host that pays from
`after_report_resolved/1` says so in its own words with
`config :gamend_core, :report_reward, {MyGame.Reports, :reward_text}`
(`reward_text/1` below): the report page shows the promise to a signed-in
reader, and the reply to a fixed report's reporter ends on the payment.

## Attachments

Images only (PNG, JPEG, WebP), checked by their bytes, stored under
`reports/<id>/`. That prefix is never in `Gamend.Storage`'s public list:
a screenshot can show anything, so only an admin reads it, through
`attachment/2`.

# `attachment`

```elixir
@spec attachment(Gamend.Reports.Report.t(), pos_integer()) ::
  {:ok, binary(), String.t()} | {:error, term()}
```

Attachment `index` (1-based) of `report`, as `{:ok, bytes, content_type}`.

# `count`

```elixir
@spec count(map()) :: non_neg_integer()
```

How many reports match `filters` (same filters as `list/2`).

# `count_by_status`

```elixir
@spec count_by_status() :: %{required(String.t()) =&gt; non_neg_integer()}
```

Reports per status, as `%{status => count}`.

# `count_open`

```elixir
@spec count_open() :: non_neg_integer()
```

How many reports are open.

# `create`

```elixir
@spec create(map(), map()) :: {:ok, Gamend.Reports.Report.t()} | {:error, term()}
```

File a report.

`params` (string keys): `"kind"`, `"topic"`, `"subject"` (map), `"data"`
(map), `"description"`, `"email"`.

`context`: `:user_id` (nil for a visitor), `:locale`, `:source` (`"web"` or
`"api"`), `:client` (a small map of browser facts), `:attachments` (a list
of image binaries).

Errors: `:unknown_kind`, `:invalid_topic`,
`:description_required`, `:too_many_attachments`, `:attachment_too_large`,
`:attachment_type`, `:daily_limit`, `:user_daily_limit`,
`:already_reported`, a kind's own `cast/2` reason, a hook's refusal, or a
changeset.

# `delete`

```elixir
@spec delete(Gamend.Reports.Report.t()) ::
  {:ok, Gamend.Reports.Report.t()} | {:error, term()}
```

Delete a report and its images.

# `description_required?`

```elixir
@spec description_required?(module(), String.t() | nil) :: boolean()
```

Whether a report of `kind` on `topic` must carry a description.

# `forget_user`

```elixir
@spec forget_user(Ecto.UUID.t()) :: non_neg_integer()
```

Delete every report `user_id` filed, images included. Called when the
account is deleted: a report can carry an email address and a screenshot,
and an erased account must not leave either behind.

# `get`

```elixir
@spec get(Ecto.UUID.t()) :: Gamend.Reports.Report.t() | nil
```

One report with its users loaded, or nil.

# `group_counts`

```elixir
@spec group_counts([Gamend.Reports.Report.t()]) :: %{
  required(tuple()) =&gt; non_neg_integer()
}
```

How many open reports share each listed report's group (kind, topic,
subject), as `%{{kind, topic, subject_ref} => count}`. Reports with no
subject key are not grouped.

# `group_key`

```elixir
@spec group_key(Gamend.Reports.Report.t()) :: tuple()
```

The group key `group_counts/1` answers under.

# `image_types`

```elixir
@spec image_types() :: [String.t()]
```

The image types an attachment may be.

# `kind`

```elixir
@spec kind(String.t() | nil) :: module() | nil
```

The kind module for `key`, or nil.

# `kinds`

```elixir
@spec kinds() :: [module()]
```

Every kind, configured ones first, core's `page` last unless replaced.

# `list`

```elixir
@spec list(map(), keyword()) :: [Gamend.Reports.Report.t()]
```

Reports, newest first. Filters: `:status`, `:kind`, `:topic`,
`:subject_ref`, `:user_id`, `:q` (text in the description or the subject
key). Opts: `:page` and `:page_size`; with no `:page`, the first
`Gamend.Query.unpaginated_limit/0` (an export).

# `prune`

```elixir
@spec prune() :: non_neg_integer()
```

The retention class: closed reports `retention_days` after they were
closed, images included. Answers how many were deleted.

# `resolve`

```elixir
@spec resolve(Gamend.Reports.Report.t(), String.t(), map()) ::
  {:ok, Gamend.Reports.Report.t()}
  | {:error, Ecto.Changeset.t() | :status_changed}
```

Close a report (`"fixed"`, `"wontfix"`, `"duplicate"`) or reopen it
(`"open"`).

`attrs`: `:resolved_by` (admin user id), `:note` (kept on the report, never
shown to the reporter), `:message` (sent to the reporter as a notification
when they had an account; nothing is sent when blank).

Closing an open report fires `after_report_resolved/1`.

The change is made from the status `report` holds, and only while the
report still has it: when another moderator closed or reopened it first,
nothing is written, nothing is sent and the answer is
`{:error, :status_changed}`.

# `resolved_config`

```elixir
@spec resolved_config(atom()) :: term()
```

The resolved value of a setting, for the web layer and tests.

# `reward_text`

```elixir
@spec reward_text(:promise | :paid) :: String.t() | nil
```

What the host says a fixed report earns, or nil when it says nothing.

`:promise` is the line the report page shows a signed-in reader, in the
reader's locale ("When we fix it, you get 25 coins."); `:paid` is the
sentence the reply to a fixed report ends on ("You got 25 coins."). Both
come from `config :gamend_core, :report_reward, {module, fun}`, called as
`fun.(which)`; a blank answer is nil.

# `ui`

```elixir
@spec ui(module()) :: module() | nil
```

The module that draws `kind` on the website, nil for an API-only kind.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
