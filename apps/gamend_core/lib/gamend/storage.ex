defmodule Gamend.Storage do
  @moduledoc """
  Object storage for user uploads (avatars, and future user-generated content).

  A thin facade over a configured backend so game code never depends on where
  bytes live:

    * `Gamend.Storage.Local` — local disk, the default (great for dev and
      single-node deploys).
    * `Gamend.Storage.S3` — any S3-compatible service (AWS S3, Cloudflare
      R2, Backblaze B2, MinIO, DigitalOcean Spaces).

  Select the backend with `GAMEND_STORAGE_ADAPTER` (`local` | `s3`); see the
  settings docs for the full `GAMEND_STORAGE_*` variable list.

  ## What may be stored

  Uploaded bytes come from users, so nothing about them is trusted:

    * the *key* is server-chosen (`build_key/3`), never taken from the client -
      that is what fixes the extension, and with it the content type the object
      is served as;
    * the declared content type must be in the allow-list (`validate_upload/3`),
      and the bytes must actually be that format (`sniff_content_type/1`);
    * size is capped per object (`max_upload_bytes`) and per owner prefix
      (`max_upload_bytes_per_owner`).

  We never decode an image server-side, so there is no image-parser attack
  surface here; the risk being defended against is serving attacker-chosen bytes
  under an attacker-chosen type from our own origin.

  ## Direct uploads

  Clients never stream bytes through the app. The server issues an upload ticket
  and the client uploads straight to the backend:

      key = Storage.build_key("avatars", user.id, "me.png")
      {:ok, ticket} = Storage.presigned_upload(key, content_type: "image/png")
      # -> client PUTs the file to ticket.url, then tells the server `key` is ready

  The ticket shape is identical for local disk and S3, so the client code does
  not change between environments.

  ## What is checked, and where

  The two backends do not offer the same guarantees at upload time, so the
  checks are deliberately split:

    * **At ticket time** (both backends) the declared content type must be one
      we accept, and the key - including its extension - is server-chosen.
    * **At upload time** (local only) the size cap, the owner quota and
      `sniff_content_type/1` all run, because the bytes pass through us.
    * **At confirm time** (both backends) size and magic bytes are re-checked
      against the *stored* object, and a failing one is deleted.

  That last step is not redundant. An S3 presigned PUT goes straight to the
  bucket, so nothing in this application sees those bytes and ExAws does not
  sign the content type - confirm is the only point at which the server can
  still refuse. Anything that persists an object's URL must therefore go through
  `GamendWeb.Uploads.confirm/5` rather than trusting a key it was handed.
  """

  alias Gamend.Storage.Adapter

  # Conservative default allow-list; callers can override per upload.
  @default_content_types ~w(image/png image/jpeg image/webp image/gif)

  # Cache policy, keyed by key-prefix (first match wins). Avatars and entity
  # icons get a fresh random key on every change (see `build_key/3`), so their
  # URL is content-unique and safe to cache forever; everything else
  # revalidates via ETag by default. Override with
  # `config :gamend_core, Gamend.Storage, cache_policies: [...],
  # default_cache_control: "..."`.
  @immutable "public, max-age=31536000, immutable"
  @default_cache_policies [{"avatars/", @immutable}, {"icons/", @immutable}]
  @default_cache_control "public, max-age=0, must-revalidate"

  # `cache_policies` and `default_cache_control` above stay host-config-only:
  # they are prefix/policy lists, not scalars an env var can carry.
  use Gamend.Settings.Provider,
    app: :gamend_core,
    group: :storage,
    label: "Storage"

  setting(:adapter, :atom,
    values: [:local, :s3],
    default: :local,
    doc: "Backend for avatars and uploads: local | s3 (any S3-compatible service)."
  )

  setting(:public_url, :string,
    doc: "CDN or base URL serving stored objects, whichever backend is behind it."
  )

  setting(:upload_ttl_seconds, :integer,
    default: 600,
    doc:
      "How long an upload ticket stays valid, in seconds. Raise it for large uploads " <>
        "over slow connections."
  )

  # An S3 bucket with no `public_url` is private, and its objects are reached
  # through `/storage/<key>`, which redirects to a link signed for this long.
  setting(:signed_url_seconds, :integer,
    default: 3600,
    doc:
      "Lifetime of the signed link /storage/<key> redirects to, for an S3 bucket with " <>
        "no public_url. S3 caps it at 604800 (7 days)."
  )

  @adapters %{local: Gamend.Storage.Local, s3: Gamend.Storage.S3}

  @doc "The configured backend module (defaults to `Gamend.Storage.Local`)."
  @spec adapter() :: module()
  def adapter, do: Map.fetch!(@adapters, Gamend.Settings.get(__MODULE__, :adapter))

  @doc false
  def config, do: Application.get_env(:gamend_core, __MODULE__, [])

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

  @doc """
  A readable URL for `key`, safe to store: it does not expire.

  For an S3 bucket with no `public_url` that is `/storage/<key>`, which
  redirects to a freshly signed link. Pass `signed: true` for the signed link
  itself, which lasts `signed_url_seconds` and must not be stored.
  """
  @spec url(Adapter.key(), keyword()) :: String.t()
  def url(key, opts \\ []), do: adapter().url(key, opts)

  @doc "Seconds an upload ticket stays valid (`upload_ttl_seconds`)."
  @spec upload_ttl_seconds() :: pos_integer()
  def upload_ttl_seconds, do: max(Gamend.Settings.get(__MODULE__, :upload_ttl_seconds), 1)

  @doc "Seconds a signed read link stays valid (`signed_url_seconds`), at most S3's 7 days."
  @spec signed_url_seconds() :: pos_integer()
  def signed_url_seconds,
    do: Gamend.Settings.get(__MODULE__, :signed_url_seconds) |> max(1) |> min(604_800)

  @doc "An upload ticket for the client (see the module doc)."
  @spec presigned_upload(Adapter.key(), keyword()) ::
          {:ok, Adapter.presigned()} | {:error, term()}
  def presigned_upload(key, opts \\ []), do: adapter().presigned_upload(key, opts)

  @doc """
  One page of stored objects (admin use). Opts: `:prefix`, and `:page` and
  `:page_size` -- clamped through `Gamend.Limits` like every other listing --
  or the adapter's own `:offset` and `:limit`.
  """
  @spec list_objects(keyword()) :: [Adapter.object()]
  def list_objects(opts \\ []) do
    if Keyword.has_key?(opts, :page) or Keyword.has_key?(opts, :page_size) do
      page = Gamend.Limits.clamp_page(Keyword.get(opts, :page))
      size = Gamend.Limits.clamp_page_size(Keyword.get(opts, :page_size))

      opts
      |> Keyword.drop([:page, :page_size])
      |> Keyword.merge(offset: (page - 1) * size, limit: size)
      |> adapter().list()
    else
      adapter().list(opts)
    end
  end

  @doc "Total object count and byte size. Opts: `:prefix`."
  @spec usage(keyword()) :: %{count: non_neg_integer(), bytes: non_neg_integer()}
  def usage(opts \\ []), do: adapter().usage(opts)

  @doc "Size and stored content type of `key`, without downloading it."
  @spec stat(Adapter.key()) :: {:ok, Adapter.stat()} | {:error, term()}
  def stat(key), do: adapter().stat(key)

  @doc "Deletes every object under `prefix`. Returns how many were removed."
  @spec delete_prefix(String.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def delete_prefix(prefix), do: adapter().delete_prefix(prefix)

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
  The image content type `data` actually is, read from its magic bytes
  (`nil` when it is not one of the formats we accept).

  A declared `Content-Type` is only a header; this is what the bytes say.
  """
  @spec sniff_content_type(binary()) :: String.t() | nil
  def sniff_content_type(<<0x89, "PNG\r\n", 0x1A, "\n", _::binary>>), do: "image/png"
  def sniff_content_type(<<0xFF, 0xD8, 0xFF, _::binary>>), do: "image/jpeg"
  def sniff_content_type(<<"GIF87a", _::binary>>), do: "image/gif"
  def sniff_content_type(<<"GIF89a", _::binary>>), do: "image/gif"
  def sniff_content_type(<<"RIFF", _size::32, "WEBP", _::binary>>), do: "image/webp"
  def sniff_content_type(data) when is_binary(data), do: nil

  @doc """
  Validate an upload's content type and size before issuing a ticket.

  Options: `:content_types` (allow-list, defaults to common images),
  `:max_bytes` (defaults to `GAMEND_LIMITS_MAX_UPLOAD_BYTES`).
  """
  @spec validate_upload(String.t(), non_neg_integer(), keyword()) ::
          :ok | {:error, :unsupported_content_type | :too_large}
  def validate_upload(content_type, size, opts \\ []) do
    allowed = Keyword.get(opts, :content_types, @default_content_types)
    max = Keyword.get(opts, :max_bytes, Gamend.Limits.get(:max_upload_bytes))

    cond do
      content_type not in allowed -> {:error, :unsupported_content_type}
      size > max -> {:error, :too_large}
      true -> :ok
    end
  end
end
