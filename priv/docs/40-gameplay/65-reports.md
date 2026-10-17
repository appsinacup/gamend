---
icon: hero-flag
---

# Reports

Players tell you what is wrong with the game itself: a page that broke, a
word with the wrong translation, an image that does not match. `/report` is
the form, `POST /api/v1/reports` the same thing for a game client, and
`/admin/reports` the queue. No account is needed on the website.

These are not chat reports (see [Chat](/docs/chat)): those are about a player
and lead to a mute or a warning. A report here is about content and leads to
a fix.

## What a report holds

| Field | |
|---|---|
| `kind` | What it is about. Core has `page`; a host adds its own |
| `topic` | One of the kind's topics (`translation`, `audio`…), or none |
| `subject` | The kind's snapshot of what was reported, taken when it was filed |
| `subject_ref` | The kind's short key for it; the queue groups duplicates on it |
| `data` | The kind's extra fields, such as a suggested correction |
| `description` | What the reporter wrote (2,000 characters) |
| `email` | Where to send a reply, if they gave one. Prefilled with the account's |
| `client` | Browser, screen size: what a bug report needs and nobody types |
| `attachments` | Up to the kind's number of images |
| `user_id` | The reporter, or nil for a visitor |

Nothing else about the sender is stored: no IP, no visitor id. The hourly
cap per IP is counted in memory.

## Adding a kind

A kind is a module implementing `Gamend.Reports.Kind`, listed in config:

```elixir
config :gamend_core, :report_kinds, [MyGame.Reports.Word]
```

```elixir
defmodule MyGame.Reports.Word do
  @behaviour Gamend.Reports.Kind
  @behaviour GamendWeb.Reports.KindUI
  use GamendWeb, :html

  @impl Gamend.Reports.Kind
  def key, do: "word"
  def topics, do: ~w(translation audio image other)
  def max_attachments, do: 1
  def ui, do: __MODULE__

  # Check what was sent, and snapshot it: the word may be renamed before
  # anyone reads the report.
  def cast(%{"subject" => %{"id" => id}, "data" => data}, _context) do
    case MyGame.Words.get(id) do
      nil -> {:error, :no_word}
      word -> {:ok, %{subject_ref: "word/#{id}", subject: %{"text" => word.text}, data: Map.take(data, ["suggestion"])}}
    end
  end

  @impl GamendWeb.Reports.KindUI
  def label, do: gettext("A word")
  def description, do: gettext("Translation, audio or image")
  def icon, do: "hero-language"
  def subject_component, do: MyGame.Reports.WordPicker
  def fields("translation"), do: [%{name: "suggestion", label: gettext("Better translation")}]
  def fields(_topic), do: []
end
```

A kind with the key `page` replaces core's. A kind whose `ui/0` is nil (or
missing) is API-only: a game client can file it, the website does not offer
it.

### On `/report`

The page draws each kind as a card. Once one is picked it draws the kind's
subject component, the topics as chips, the kind's fields for the picked
topic, then core's own: description, email, images, send.

The **subject component** is a `Phoenix.LiveComponent` that owns how the
subject is chosen: a search, a picker, a plain field. It renders its own
`<form>`, gets `query` (the page's URL params, so a deep link like
`/report?kind=word&id=42` can preselect), `topic`, `locale` and
`current_scope`, and tells the page what is chosen:

```elixir
send(self(), {:report_subject, %{"id" => "42"}})  # or nil when cleared
```

That map is what `cast/2` receives under `"subject"`. A component whose own
control implies a topic (a "this word is missing" button) can pick it with
`send(self(), {:report_topic, "missing"})`.

### In the queue

`admin_subject/1` draws what a report is about (it gets `report`);
`subject_label/1` says it in a few words, for the reply a reporter receives.
`export/1` answers `{filename, content_type, body}` for the reports the admin
has filtered, for a kind whose fixes happen somewhere else (a spreadsheet, a
translation tool). `error_message/1` turns your `cast/2` errors into words for
the reporter.

## Limits

| Setting | Default | |
|---|---|---|
| `GAMEND_REPORTS_ENABLED` | true | |
| `GAMEND_REPORTS_IP_HOURLY_LIMIT` | 10 | per IP, in memory |
| `GAMEND_REPORTS_USER_DAILY_LIMIT` | 20 | per account, counted on rows |
| `GAMEND_REPORTS_DAILY_LIMIT` | 500 | across everyone |
| `GAMEND_REPORTS_MAX_ATTACHMENT_BYTES` | 2,000,000 | per image |
| `GAMEND_REPORTS_RETENTION_DAYS` | 180 | closed reports, from when they were closed |

A signed-in player cannot file the same open report twice (same kind, topic
and subject). A hidden field catches form-filling bots: they are thanked and
nothing is stored.

## Images

PNG, JPEG or WebP, checked by their bytes. The browser shrinks a screenshot
before sending it (at most 1600 px wide, WebP where it can), which also drops
a photo's location data. Images are stored under `reports/<id>/`, which is
never a public storage prefix: only an admin reads them, at
`/admin/reports/:id/attachments/:n`.

## Hooks

| Hook | |
|---|---|
| `before_report_create(attrs)` | Pipeline. `{:ok, attrs}` files it, changed or not; `{:error, reason}` refuses it |
| `after_report_created(report)` | Fire-and-forget |
| `after_report_resolved(report)` | Fire-and-forget, each time an open report is closed |

A report reopened and closed again calls `after_report_resolved` again, so a
reward paid from it needs an idempotency key on the report id:

```elixir
def after_report_resolved(%{status: "fixed", user_id: user_id, id: id}) when is_binary(user_id) do
  Gamend.Economy.grant(user_id, "coins", 20, idempotency_key: "report:#{id}")
end

def after_report_resolved(_report), do: :ok
```

Say so where the reporter looks. `config :gamend_core, :report_reward,
{MyGame.Reports, :reward_text}` is called with `:promise` (a line the report
page shows a signed-in reader, in their locale: "When we fix it, you get 20
coins.") and `:paid` (the sentence the default reply to a fixed report ends
on: "You got 20 coins."). Unset, or a blank answer, says nothing. Core pays
nothing itself.

## Closing a report

From the queue: **Fixed**, **Duplicate** or **Won't fix**. Each takes a note
for admins and, when the reporter had an account, a reply sent as a
notification (`report_resolved`). Admins get one standing "N reports are
waiting" notification (`report`) whose count moves.

Deleting an account deletes the reports it filed, images included: a report
can carry an email address and a screenshot.

## API

```http
GET  /api/v1/reports/kinds
POST /api/v1/reports
```

Both need a token (a device token is enough). `kinds` answers
`{data: {kinds: [{key, topics, max_attachments, max_attachment_bytes}]}}`.
The body of `POST` is the report's
fields, with images as base64 strings in `attachments`. Answers `201` with
`{id, kind, status}`; `400 invalid_report`, `409 already_reported`,
`429 report_limit`, `503 reports_disabled`.
