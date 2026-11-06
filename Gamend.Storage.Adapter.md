# `Gamend.Storage.Adapter`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/storage/adapter.ex#L1)

Behaviour for object-storage backends.

Implemented by `Gamend.Storage.Local` (disk, the dev default) and
`Gamend.Storage.S3` (any S3-compatible service — AWS S3, Cloudflare R2,
Backblaze B2, MinIO, DigitalOcean Spaces). Callers go through the
`Gamend.Storage` facade, never an adapter directly.

# `key`

```elixir
@type key() :: String.t()
```

# `object`

```elixir
@type object() :: %{
  key: key(),
  size: non_neg_integer(),
  last_modified: DateTime.t() | nil
}
```

A stored object's metadata, as listed by the admin tools.

# `presigned`

```elixir
@type presigned() :: %{
  method: String.t(),
  url: String.t(),
  headers: %{optional(String.t()) =&gt; String.t()},
  key: key(),
  expires_in: pos_integer()
}
```

An upload ticket handed to a client so it can upload bytes directly to the
backend (S3/R2) or to the local upload endpoint — the client flow is identical
either way.

# `stat`

```elixir
@type stat() :: %{size: non_neg_integer(), content_type: String.t() | nil}
```

What the backend reports about a stored object without fetching it.

# `delete`

```elixir
@callback delete(key()) :: :ok | {:error, term()}
```

# `delete_prefix`

```elixir
@callback delete_prefix(String.t()) :: {:ok, non_neg_integer()} | {:error, term()}
```

Deletes every object under `prefix`. Returns how many were removed.

# `exists?`

```elixir
@callback exists?(key()) :: boolean()
```

# `get`

```elixir
@callback get(key()) :: {:ok, binary()} | {:error, :not_found | term()}
```

The object's bytes. An object that is not there is `{:error, :not_found}`
on every backend; any other error is the backend failing.

# `list`

```elixir
@callback list(keyword()) :: [object()]
```

One page of objects. Opts: `:prefix`, `:offset`, `:limit`.

# `presigned_upload`

```elixir
@callback presigned_upload(key(), keyword()) :: {:ok, presigned()} | {:error, term()}
```

# `put`

```elixir
@callback put(key(), iodata(), keyword()) :: {:ok, key()} | {:error, term()}
```

# `stat`

```elixir
@callback stat(key()) :: {:ok, stat()} | {:error, term()}
```

Size and stored content type of one object, without downloading it.

`content_type` is whatever the backend recorded; the local adapter keeps no
per-object metadata and always reports `nil`.

# `url`

```elixir
@callback url(key(), keyword()) :: String.t()
```

# `usage`

```elixir
@callback usage(keyword()) :: %{count: non_neg_integer(), bytes: non_neg_integer()}
```

Total object count and byte size. Opts: `:prefix`.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
