# `Gamend.Sent.SentMessage`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/sent/sent_message.ex#L1)

One email or push that went out (`sent_messages`), written by `Gamend.Sent`.

  * `channel`: `email` or `push` (`Gamend.Notifications.NotificationChannel`);
  * `kind`: what it was (`Gamend.Sent.SentKind`);
  * `group_key`: the notification group it went out in, if any;
  * `batch_id`: the announcement it was part of, so one send to everyone
    reads as one line;
  * `address`: the email address, or the device (`ios · apns`);
  * `subject`: the email's subject or the push's title;
  * `body`: what it said, with sign-in links, codes and unsubscribe links
    hidden. An email's is its `Gamend.Mail.Message`, so the admin sees it in
    the email's look; a push's is its title, body, picture and data;
  * `status` (`Gamend.Sent.SentStatus`) and `reason` when it failed.

# `t`

```elixir
@type t() :: %Gamend.Sent.SentMessage{
  __meta__: term(),
  address: term(),
  batch_id: term(),
  body: term(),
  channel: term(),
  group_key: term(),
  id: term(),
  inserted_at: term(),
  kind: term(),
  reason: term(),
  status: term(),
  subject: term(),
  user: term(),
  user_id: term()
}
```

# `changeset`

```elixir
@spec changeset(t(), map()) :: Ecto.Changeset.t()
```

---

*Consult [api-reference.md](api-reference.md) for complete listing*
