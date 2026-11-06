# `Gamend.Chat.Moderation`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/chat/moderation.ex#L1)

Chat word filter and mutes.

The enforcement side of chat moderation: an admin-managed blocklist checked
against every outgoing message, and mutes that silence a sender globally or
in one lobby/group/party. Both are checked in `Gamend.Chat.send_message/2`
before the message is persisted, so nothing unmoderated reaches the database
or PubSub. A mute is a chat ban (`Gamend.Bans`, kind `:chat`).

Reports live in `Gamend.Chat.Reports`.

Blocklist writes go to the database first and are then mirrored into
`Gamend.Chat.Moderation.Cache` (ETS + PubSub), which is what the per-message
path actually reads; mutes are cached by `Gamend.Bans.Cache`.

# `bundled_languages`

```elixir
@spec bundled_languages() :: [String.t()]
```

Languages with a bundled word list available to import.

The lists are vendored under `priv/chat_filter/<lang>.txt`; nothing is loaded
until an admin imports it.

# `check_content`

```elixir
@spec check_content(String.t()) ::
  {:ok, String.t(), [String.t()]} | {:error, :blocked_content}
```

Run `content` through the blocklist.

Returns `{:error, :blocked_content}` when a `block` word matches,
`{:ok, content, flagged_words}` otherwise — `content` has any `mask` hits
replaced with `***`, and `flagged_words` is non-empty when a `flag` word
matched (the caller files a report once the message is persisted).

Masking works on whole whitespace-separated tokens, because a hit is found in
the normalized form and its offsets do not map back onto the original text.
If a masked message still matches (a multi-word phrase that no single token
covers) it is blocked rather than sent through half-masked.

# `count_filter_words`

```elixir
@spec count_filter_words(map()) :: non_neg_integer()
```

Count blocklist entries matching `filters`.

# `count_mutes`

```elixir
@spec count_mutes(map()) :: non_neg_integer()
```

Count mutes matching `filters`.

# `create_filter_word`

```elixir
@spec create_filter_word(map()) ::
  {:ok, Gamend.Chat.FilterWord.t()}
  | {:error, :too_many_filter_words | Ecto.Changeset.t()}
```

Add a word to the blocklist.

Rejected with `{:error, :too_many_filter_words}` once
`max_chat_filter_words` is reached.

# `delete_filter_word`

```elixir
@spec delete_filter_word(Gamend.Chat.FilterWord.t()) ::
  {:ok, Gamend.Chat.FilterWord.t()} | {:error, Ecto.Changeset.t()}
```

Remove a blocklist entry.

# `delete_filter_words_by_lang`

```elixir
@spec delete_filter_words_by_lang(String.t()) :: non_neg_integer()
```

Delete every blocklist entry with the given `lang` tag. Returns the count.

# `get_filter_word`

```elixir
@spec get_filter_word(Ecto.UUID.t()) :: Gamend.Chat.FilterWord.t() | nil
```

Fetch one blocklist entry.

# `get_mute`

```elixir
@spec get_mute(Ecto.UUID.t()) :: Gamend.Bans.Ban.t() | nil
```

Fetch one mute.

# `hits`

```elixir
@spec hits(String.t()) :: [{String.t(), String.t(), String.t()}]
```

Every blocklist entry matching `content`, as `[{word, severity, match_mode}]`.

Exposed for the admin "test a phrase" box so it reports exactly what the
runtime path would do.

# `import_bundled_list`

```elixir
@spec import_bundled_list(String.t(), String.t()) ::
  {:ok, non_neg_integer()}
  | {:error, :unknown_language | :too_many_filter_words | File.posix()}
```

Import the bundled list for `lang`.

Every word goes through the normal changeset, so `max_chat_filter_word_len`
applies and duplicates are skipped. Returns `{:ok, imported_count}` or
`{:error, :unknown_language | :too_many_filter_words}`, or the file error
when the list cannot be read.

# `list_filter_words`

```elixir
@spec list_filter_words(map(), keyword()) :: [Gamend.Chat.FilterWord.t()]
```

List blocklist entries. Filters: `:word`, `:severity`, `:lang`.

# `list_mutes`

```elixir
@spec list_mutes(map(), keyword()) :: [Gamend.Bans.Ban.t()]
```

List mutes, newest first. Filters: `:user_id`, `:scope`, `:scope_ref_id`,
`:active` (when true, only mutes in force).

# `mute_user`

```elixir
@spec mute_user(Ecto.UUID.t(), String.t(), Ecto.UUID.t() | nil, map()) ::
  {:ok, Gamend.Bans.Ban.t()} | {:error, Ecto.Changeset.t()}
```

Mute `user_id`.

`scope` is `"global"` (every chat, `scope_ref_id` nil) or one of `"lobby"`,
`"group"`, `"party"` with the room id as `scope_ref_id`. `attrs` may carry
`expires_at` (nil means permanent), `reason`, `muted_by` (who did it) and
`source` (`:admin`, `:room` for a room's own authority, `:plugin` by
default; see `Gamend.Bans.Ban`).

Re-muting an already-muted user replaces the existing mute, so a moderator
can extend or shorten one without unmuting first.

# `muted?`

```elixir
@spec muted?(Ecto.UUID.t(), String.t(), Ecto.UUID.t() | nil) :: boolean()
```

Whether `user_id` is currently muted for the given chat (ETS read).

# `unmute_user`

```elixir
@spec unmute_user(Ecto.UUID.t(), String.t(), Ecto.UUID.t() | nil, Ecto.UUID.t() | nil) ::
  {:ok, non_neg_integer()}
```

Lift a mute. Returns `{:ok, count}` — 0 when the user was not muted.

# `update_filter_word`

```elixir
@spec update_filter_word(Gamend.Chat.FilterWord.t(), map()) ::
  {:ok, Gamend.Chat.FilterWord.t()} | {:error, Ecto.Changeset.t()}
```

Update a blocklist entry.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
