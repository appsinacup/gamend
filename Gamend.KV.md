# `Gamend.KV`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/kv.ex#L1)

Generic key/value storage.

This is intentionally minimal and un-opinionated.

If you want namespacing, encode it in `key` (e.g. `"my_game:key1"`).
If you want per-user values, pass `user_id: ...` to `get/2`, `put/4`, and `delete/2`.
If you want per-lobby values, pass `lobby_id: ...` to the same functions.
You can also pass both to scope a key to a user within a lobby.

This module uses the app cache (`Gamend.Cache`) as a best-effort read cache.
Writes update the cache and deletes evict it.

# `attrs`

```elixir
@type attrs() :: %{
  :key =&gt; String.t(),
  optional(:user_id) =&gt; String.t(),
  optional(:lobby_id) =&gt; String.t(),
  :value =&gt; value(),
  optional(:metadata) =&gt; metadata()
}
```

Attributes used when creating or updating entries.

Expected keys (atom keys recommended):
- `:key` — the entry key (`String.t()`)
  - `:user_id` — optional user id (`String.t()`)
  - `:lobby_id` — optional lobby id (`String.t()`)
- `:value` — the stored value (`value()`)
- `:metadata` — optional metadata (`metadata()`)

# `list_opts`

```elixir
@type list_opts() :: [
  page: pos_integer(),
  page_size: pos_integer(),
  user_id: Ecto.UUID.t(),
  lobby_id: Ecto.UUID.t(),
  global_only: boolean(),
  key: String.t()
]
```

Options accepted by `list_entries/1` and `count_entries/1`.

Keys (all optional):
- `:page` — page number (`pos_integer()`, defaults to `1`)
- `:page_size` — page size (`pos_integer()`, defaults to `50`)
- `:user_id` — filter by user id (`Ecto.UUID.t()`)
- `:lobby_id` — filter by lobby id (`Ecto.UUID.t()`)
- `:global_only` — when true, only return global entries (where `user_id` and `lobby_id` are `nil`) (`boolean()`)
- `:key` — substring filter (`String.t()`)

# `metadata`

```elixir
@type metadata() :: map()
```

Metadata stored alongside a value. Typically a small map with auxiliary fields.

# `payload`

```elixir
@type payload() :: %{value: value(), metadata: metadata()}
```

Payload returned by `get/1` and `get/2`.

# `value`

```elixir
@type value() :: map()
```

Value stored for a key. This is an arbitrary map and should contain JSON-serializable data.

# `count_entries`

```elixir
@spec count_entries(list_opts()) :: non_neg_integer()
```

Count the number of entries that match the optional filter.

Accepts the same options as `list_entries/1` (see `t:list_opts/0`). Returns a non-negative integer.

# `create_entry`

```elixir
@spec create_entry(attrs()) ::
  {:ok, Gamend.KV.Entry.t()} | {:error, Ecto.Changeset.t()}
```

Create a new `Entry` from `attrs` (expecting `key`, optional `user_id`/`lobby_id`,
`value`, `metadata`).
Returns `{:ok, entry}` or `{:error, changeset}`.

# `delete`

```elixir
@spec delete(String.t(), keyword()) :: :ok
```

Delete the entry at `key`.

Pass `user_id: id` or `lobby_id: id` in `opts` to delete a scoped key. Returns `:ok`.

# `delete_entry`

```elixir
@spec delete_entry(Ecto.UUID.t()) :: :ok
```

Delete an entry by its `id`.

Returns `:ok` whether or not the entry existed.

# `delete_lobby_entries`

```elixir
@spec delete_lobby_entries(Ecto.UUID.t()) :: non_neg_integer()
```

Delete every entry scoped to a lobby, in one statement: for deleting the lobby.

The per-entry cache invalidations and `kv_deleted` broadcasts wait for the
enclosing transaction to commit (`Gamend.AfterCommit`). One `delete/2` per
entry cost a statement and two cache round-trips each while the caller held
the lobby's lock. Returns the number of entries deleted.

# `delete_user_lobby_entries`

```elixir
@spec delete_user_lobby_entries(Ecto.UUID.t(), Ecto.UUID.t()) :: non_neg_integer()
```

Delete every entry a user holds inside one lobby.

Called when a user stops being a member of a lobby, so per-member lobby state
(ready flags, loadouts, character picks) does not survive a leave and rejoin.
Entries scoped to the lobby alone, or to the user alone, are left untouched.

Returns the number of entries deleted.

# `get`

```elixir
@spec get(String.t(), keyword()) :: {:ok, payload()} | :error
```

Retrieve the value and metadata stored for `key`.

Pass `user_id: id` or `lobby_id: id` in `opts` to scope the lookup.
Returns `{:ok, %{value: map(), metadata: map()}}` when found, or `:error` when not present.

# `get_entry`

```elixir
@spec get_entry(Ecto.UUID.t()) :: Gamend.KV.Entry.t() | nil
```

Fetch an `Entry` by its `id`.
Returns the `Entry` struct or `nil` if not found.

# `list_entries`

```elixir
@spec list_entries(list_opts()) :: [Gamend.KV.Entry.t()]
```

List key/value entries with optional pagination and filtering.

Supported options: `:page`, `:page_size`, `:user_id`, `:lobby_id`, `:global_only`,
and `:key` (substring filter).
See `t:list_opts/0` for the expected option types.
Returns a list of `Entry` structs ordered by most recently updated.

# `put`

```elixir
@spec put(String.t(), value(), metadata()) ::
  {:ok, Gamend.KV.Entry.t()} | {:error, Ecto.Changeset.t()}
```

# `put`

```elixir
@spec put(String.t(), value(), metadata(), list_opts()) ::
  {:ok, Gamend.KV.Entry.t()} | {:error, Ecto.Changeset.t()}
```

Store `value` with optional `metadata` at `key`.

When using the 4-arity, supported options include `user_id: id` or `lobby_id: id` to scope
the entry.
Returns `{:ok, entry}` on success or `{:error, changeset}` on validation failure.

# `subscribe`

```elixir
@spec subscribe(String.t(), keyword()) :: :ok | {:error, term()}
```

Subscribe the current process to changes for a specific key/scope.

# `unsubscribe`

```elixir
@spec unsubscribe(String.t(), keyword()) :: :ok | {:error, term()}
```

Unsubscribe the current process from changes for a specific key/scope.

# `update_entry`

```elixir
@spec update_entry(Ecto.UUID.t(), attrs()) ::
  {:ok, Gamend.KV.Entry.t()}
  | {:error, :not_found}
  | {:error, Ecto.Changeset.t()}
```

Update an existing entry by `id` with `attrs`.
Returns `{:ok, entry}`, `{:error, :not_found}` if missing, or `{:error, changeset}` on validation error.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
