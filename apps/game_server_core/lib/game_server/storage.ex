defmodule GameServer.Storage do
  @moduledoc """
  Object storage for user uploads (avatars, and future user-generated content).

  A thin facade over a configured backend so game code never depends on where
  bytes live:

    * `GameServer.Storage.Local` — local disk, the default (great for dev and
      single-node deploys).
    * `GameServer.Storage.S3` — any S3-compatible service (AWS S3, Cloudflare
      R2, Backblaze B2, MinIO, DigitalOcean Spaces).

  Select the backend with `STORAGE_ADAPTER` (`local` | `s3`); see the deployment
  docs for the full `STORAGE_*` variable list.

  ## Direct uploads

  Clients never stream bytes through the app. The server issues an upload ticket
  and the client uploads straight to the backend:

      key = Storage.build_key("avatars", user.id, "me.png")
      {:ok, ticket} = Storage.presigned_upload(key, content_type: "image/png")
      # -> client PUTs the file to ticket.url, then tells the server `key` is ready

  The ticket shape is identical for local disk and S3, so the client code does
  not change between environments.
  """

  alias GameServer.Storage.Adapter

  # Conservative default allow-list; callers can override per upload.
  @default_content_types ~w(image/png image/jpeg image/webp image/gif)

  # Cache policy, keyed by key-prefix (first match wins). Avatars and entity
  # icons get a fresh random key on every change (see `build_key/3`), so their
  # URL is content-unique and safe to cache forever; everything else
  # revalidates via ETag by default. Override with
  # `config :game_server_core, GameServer.Storage, cache_policies: [...],
  # default_cache_control: "..."`.
  @immutable "public, max-age=31536000, immutable"
  @default_cache_policies [{"avatars/", @immutable}, {"icons/", @immutable}]
  @default_cache_control "public, max-age=0, must-revalidate"

  # `cache_policies` and `default_cache_control` above stay host-config-only:
  # they are prefix/policy lists, not scalars an env var can carry.
  use GameServer.Settings.Provider,
    app: :game_server_core,
    group: :storage,
    label: "Storage"

  setting(:adapter, :atom,
    default: :local,
    doc: "Backend for avatars and uploads: local | s3 (any S3-compatible service)."
  )

  setting(:public_url, :string,
    doc: "CDN or base URL serving stored objects, whichever backend is behind it."
  )

  @adapters %{local: GameServer.Storage.Local, s3: GameServer.Storage.S3}

  @doc "The configured backend module (defaults to `GameServer.Storage.Local`)."
  @spec adapter() :: module()
  def adapter, do: Map.fetch!(@adapters, GameServer.Settings.get(__MODULE__, :adapter))

  @doc false
  def config, do: Application.get_env(:game_server_core, __MODULE__, [])

  @doc """
  The `Cache-Control` header for `key`, from the first matching prefix policy
  (or `default_cache_control` when none match). Used by the local serve route
  and set as S3 object metadata at upload.
  """
  @spec cache_control(Adapter.key()) :: String.t()
  def cache_control(key) do
    cfg = config()
    policies = Keyword.get(cfg, :cache_policies, @default_cache_policies)
    default = Keyword.get(cfg, :default_cache_control, @default_cache_control)

    Enum.find_value(policies, default, fn {prefix, cc} ->
      if String.starts_with?(key, prefix), do: cc
    end)
  end

  @spec put(Adapter.key(), iodata(), keyword()) :: {:ok, Adapter.key()} | {:error, term()}
  def put(key, data, opts \\ []) do
    # S3 serves objects directly, so the cache policy must ride along as object
    # metadata at upload. The local backend applies it at serve time instead.
    opts = Keyword.put_new(opts, :cache_control, cache_control(key))
    adapter().put(key, data, opts)
  end

  @spec get(Adapter.key()) :: {:ok, binary()} | {:error, term()}
  def get(key), do: adapter().get(key)

  @spec delete(Adapter.key()) :: :ok | {:error, term()}
  def delete(key), do: adapter().delete(key)

  @spec exists?(Adapter.key()) :: boolean()
  def exists?(key), do: adapter().exists?(key)

  @doc "A readable URL for `key` (public or signed, backend-dependent)."
  @spec url(Adapter.key(), keyword()) :: String.t()
  def url(key, opts \\ []), do: adapter().url(key, opts)

  @doc "An upload ticket for the client (see the module doc)."
  @spec presigned_upload(Adapter.key(), keyword()) ::
          {:ok, Adapter.presigned()} | {:error, term()}
  def presigned_upload(key, opts \\ []), do: adapter().presigned_upload(key, opts)

  @doc "One page of stored objects. Opts: `:prefix`, `:offset`, `:limit` (admin use)."
  @spec list_objects(keyword()) :: [Adapter.object()]
  def list_objects(opts \\ []), do: adapter().list(opts)

  @doc "Total object count and byte size. Opts: `:prefix`."
  @spec usage(keyword()) :: %{count: non_neg_integer(), bytes: non_neg_integer()}
  def usage(opts \\ []), do: adapter().usage(opts)

  @doc """
  Build a collision-resistant object key: `<namespace>/<owner_id>/<random><ext>`.

  The extension is taken (lower-cased) from `filename`; everything else is
  server-chosen so a client can't overwrite another object.
  """
  @spec build_key(String.t(), String.t(), String.t()) :: String.t()
  def build_key(namespace, owner_id, filename) do
    ext = filename |> Path.extname() |> String.downcase()
    rand = 16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    "#{namespace}/#{owner_id}/#{rand}#{ext}"
  end

  @doc ~S|File extension for a declared image content type ("" when unknown).|
  @spec extension_for(String.t()) :: String.t()
  def extension_for("image/png"), do: ".png"
  def extension_for("image/jpeg"), do: ".jpg"
  def extension_for("image/webp"), do: ".webp"
  def extension_for("image/gif"), do: ".gif"
  def extension_for(_content_type), do: ""

  @doc """
  Validate an upload's content type and size before issuing a ticket.

  Options: `:content_types` (allow-list, defaults to common images),
  `:max_bytes` (defaults to `LIMIT_MAX_UPLOAD_BYTES`).
  """
  @spec validate_upload(String.t(), non_neg_integer(), keyword()) ::
          :ok | {:error, :unsupported_content_type | :too_large}
  def validate_upload(content_type, size, opts \\ []) do
    allowed = Keyword.get(opts, :content_types, @default_content_types)
    max = Keyword.get(opts, :max_bytes, GameServer.Limits.get(:max_upload_bytes))

    cond do
      content_type not in allowed -> {:error, :unsupported_content_type}
      size > max -> {:error, :too_large}
      true -> :ok
    end
  end
end
