# `Gamend.Reports.Kind`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/reports/kind.ex#L1)

What a report can be about.

Core ships one kind, `"page"` (`Gamend.Reports.Kinds.Page`): something on a
page is broken or wrong. A host adds its own by implementing this behaviour
and listing the module:

    config :gamend_core, :report_kinds, [MyGame.Reports.Word]

A kind owns two things: which **topics** a report on it may pick ("the
translation is wrong", "the audio is wrong"), and how a submitted subject is
**checked and snapshotted** (`c:cast/2`). Everything else — storage, limits,
the admin queue, attachments, the API — is core's and the same for every
kind.

## `cast/2`

Gets the kind-specific params as sent (`"subject"` and `"data"` maps, plus
`"topic"`) and the context (`:user_id`, `:locale`, `:source`). Answers:

    {:ok, %{subject_ref: "ro/1234", subject: %{...}, data: %{...}}}

`subject_ref` is the short key duplicates group on, nil when nothing groups
them. `subject` is the snapshot shown in the queue — take it now, because
what was reported may be renamed or removed by the time anyone reads it.
`data` is the kind's extra fields, already trimmed and capped. An
`{:error, reason}` is shown to the reporter as "check what you entered".

## `take/1`, optional

Some reports are not for the queue: the host already has a place where
that kind of thing is worked (a word's translators, a support desk). A
kind that knows answers `:taken` from `c:take/1` and puts the report there
itself; core then stores no row, raises no admin alert, keeps no image and
answers `{:ok, :taken}` from `Gamend.Reports.create/2`, which the reporter
is told as a report received. `:file` files it as usual, `{:error, reason}`
refuses it. It gets the attrs as they would be inserted (string keys:
`kind`, `topic`, `subject_ref`, `subject`, `data`, `description`,
`user_id`, …), after `before_report_create/1`. A kind without it files
everything.

## `sources/0`, optional

Where a report of the kind may come from (`Gamend.Reports.ReportSource`):
core's report page (`web`), the API (`api`), the host's own code (`host`).
A kind left out of a source is not listed there and is refused from it as
an unknown kind. Without it, `web` and `api`. A kind only the host files
(an in-game survey on a page of its own) answers `[ReportSource.host()]`
and calls `Gamend.Reports.create/2` with `source: ReportSource.host()`.

## `reply_title/1`, optional

The title of the notification a reporter gets when a report of the kind
is closed with a reply (gets the report; its `locale` is the reporter's).
nil, or no callback, for core's "Your report was reviewed".

## The web side

`c:ui/0` names the module that draws the kind on `/report` and in the admin
queue (`GamendWeb.Reports.KindUI`). A kind with no UI is API-only: a game
client can file it, and nobody can from the website.

# `cast_result`

```elixir
@type cast_result() :: %{subject_ref: String.t() | nil, subject: map(), data: map()}
```

What `cast/2` answers on success.

# `cast`

```elixir
@callback cast(params :: map(), context :: map()) ::
  {:ok, cast_result()} | {:error, term()}
```

Check and snapshot a submitted subject. See the module doc.

# `description_required?`
*optional* 

```elixir
@callback description_required?(topic :: String.t() | nil) :: boolean()
```

Whether a report must say something in its description.

# `key`

```elixir
@callback key() :: String.t()
```

The kind's key, stored on every report (`"word"`). Lowercase, no spaces.

# `max_attachments`

```elixir
@callback max_attachments() :: non_neg_integer()
```

How many images a report may carry (0 = none).

# `reply_title`
*optional* 

```elixir
@callback reply_title(report :: Gamend.Reports.Report.t()) :: String.t() | nil
```

The reply notification's title for `report`, or nil for core's. See the module doc.

# `sources`
*optional* 

```elixir
@callback sources() :: [String.t()]
```

Where a report of the kind may be filed from. See the module doc.

# `take`
*optional* 

```elixir
@callback take(attrs :: map()) :: :file | :taken | {:error, term()}
```

Whether the host takes this report elsewhere instead of the queue. See the module doc.

# `topics`

```elixir
@callback topics() :: [String.t()]
```

The topics a report may pick, in display order. `[]` for none.

# `ui`
*optional* 

```elixir
@callback ui() :: module() | nil
```

The module that draws this kind (`GamendWeb.Reports.KindUI`), nil for API-only.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
