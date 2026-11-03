# `Gamend.Notifications.Digest`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/notifications/digest.ex#L1)

Emails that wait and go out together: a group with `email_every`
(`Gamend.Notifications.Preferences`) keeps its notices here, and one email
lists them.

The clock is the user's oldest waiting notice, per group: a `:week` digest
goes a week after the first notice in it. So nothing goes out with nothing
to say, and nobody needs a time zone or a send day. An hourly sweep
(`Gamend.Notifications.DigestSweeper`) queues what is due, and the web app's
job (`GamendWeb.Workers.NotificationDigest`) builds and sends it, deleting
only the rows it listed. A notice that arrives meanwhile waits for the next
one.

# `add`

```elixir
@spec add(String.t(), String.t(), map()) ::
  {:ok, Gamend.Notifications.DigestItem.t()} | {:error, term()}
```

Keep a notice for `user_id`'s next digest of `group`.

# `delete`

```elixir
@spec delete([Gamend.Notifications.DigestItem.t()]) :: non_neg_integer()
```

Delete exactly these rows: what arrived after they were read stays.

# `due`

```elixir
@spec due(DateTime.t()) :: [{String.t(), String.t()}]
```

The `{user_id, group}` pairs due at `now`. A group that no longer declares
`email_every` is due at once, so a host dropping it strands nothing.

# `items`

```elixir
@spec items(String.t(), String.t()) :: [Gamend.Notifications.DigestItem.t()]
```

What waits for `user_id` in `group`, oldest first.

# `sweep`

```elixir
@spec sweep(DateTime.t()) :: non_neg_integer()
```

Queue every digest due at `now`. Returns how many pairs were due.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
