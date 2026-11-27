# `Gamend.Storage.Local`
[🔗](https://github.com/appsinacup/gamend/blob/v1.0.7/lib/gamend/storage/local.ex#L1)

Disk-backed storage — the default backend.

Files live under `GAMEND_STORAGE_DIR` (default `priv/storage`). Readable
URLs point at `GET /storage/<key>`, and an upload ticket at the app's own
`PUT /api/v1/storage/upload` (`upload_path/0`), a path with no host, so a
client sends it to the server it talks to. `GamendWeb.Uploads` signs the
ticket's key and content type into its `token`, which is all that route
takes: no session, as an S3 presigned `PUT` takes none.

# `root_dir`

```elixir
@spec root_dir() :: String.t()
```

Directory objects are written to.

Reads the declared `:dir` setting, so `GAMEND_STORAGE_DIR` and the documented
default are the single source of truth. The previous fallback here pointed at
the *application's* priv directory, which is a different path from the
declared `priv/storage` default — and inside a release it is a versioned
directory that a deploy replaces, silently taking every stored object with it.

# `upload_path`

```elixir
@spec upload_path() :: String.t()
```

The path a local upload ticket names: the app's own upload route.

---

*Consult [api-reference.md](api-reference.md) for complete listing*
