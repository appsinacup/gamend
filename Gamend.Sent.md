# `Gamend.Sent`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/sent.ex#L1)

What went out: one row per email (`Gamend.Accounts.UserNotifier`) and per
push to a device (`Gamend.Push.DeliveryWorker`), for the admin's Sent card
on `/admin/notifications`.

A row keeps what the person got, so the admin can see it in its own look:
an email's `Gamend.Mail.Message` (`message/1` rebuilds it, and
`Gamend.Mail.Message.to_html/1` draws it in today's email layout), a push's
title and text. What would let someone else act as the reader is hidden
before it is stored: a sign-in or confirmation link, a code, an unsubscribe
link.

An announcement's sends share its id (`batch_id`), so `list_lines/2` shows
one send to everyone as one line, and `list/2` with `"batch_id"` lists who
got it.

Recording never stops a send: a row that cannot be written is logged and
left out. Rows go after `GAMEND_RETENTION_SENT_MESSAGES_DAYS` (30), and with
their user.

# `line`

```elixir
@type line() :: %{
  key: Ecto.UUID.t(),
  batch?: boolean(),
  count: non_neg_integer(),
  failed: non_neg_integer(),
  kind: String.t(),
  group_key: String.t() | nil,
  subject: String.t() | nil,
  last_at: DateTime.t(),
  row: Gamend.Sent.SentMessage.t() | nil
}
```

# `count`

```elixir
@spec count(map()) :: non_neg_integer()
```

How many rows `list/2` pages through.

# `count_lines`

```elixir
@spec count_lines(map()) :: non_neg_integer()
```

How many lines `list_lines/2` pages through.

# `get`

```elixir
@spec get(term()) :: Gamend.Sent.SentMessage.t() | nil
```

One row, with its user.

# `list`

```elixir
@spec list(map(), keyword()) :: [Gamend.Sent.SentMessage.t()]
```

Rows, newest first, with their users. `filters` (string keys, all optional):
`"channel"`, `"kind"`, `"status"`, `"failed"` (`true`: anything not sent),
`"batch_id"`, `"user_id"`, `"search"` (part of the address or subject).

# `list_lines`

```elixir
@spec list_lines(map(), keyword()) :: [line()]
```

The rows as lines, newest first: one per email or push, and one per
announcement, which carries how many went and how many did not. A line of
one send carries its row. Same `filters` as `list/2`.

# `message`

```elixir
@spec message(Gamend.Sent.SentMessage.t()) :: Gamend.Mail.Message.t() | nil
```

An email row's message, rebuilt from what was stored; nil for a push.

# `record_email`

```elixir
@spec record_email(
  String.t(),
  String.t() | nil,
  String.t() | nil,
  Gamend.Mail.Message.t(),
  keyword()
) ::
  {:ok, Gamend.Sent.SentMessage.t()} | {:error, term()}
```

Record an email that was sent (or failed). `opts`: `:user_id`, `:group`,
`:batch`, `:status` (`sent`), `:reason`, and `:secrets`, the strings to hide
wherever they appear (a link that signs in, an unsubscribe link). A code is
always hidden.

# `record_push`

```elixir
@spec record_push(String.t(), String.t(), map(), map(), String.t(), keyword()) ::
  {:ok, Gamend.Sent.SentMessage.t()} | {:error, term()}
```

Record one push to one device: `message` is the push as it was queued
(`Gamend.Push.Message.to_map/1`), `device` the token's `platform` and
`provider`. `opts`: `:group`, `:batch`, `:reason`.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
