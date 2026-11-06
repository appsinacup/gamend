defmodule Gamend.Storage.Adapter do
  @moduledoc """
  Behaviour for object-storage backends.

  Implemented by `Gamend.Storage.Local` (disk, the dev default) and
  `Gamend.Storage.S3` (any S3-compatible service — AWS S3, Cloudflare R2,
  Backblaze B2, MinIO, DigitalOcean Spaces). Callers go through the
  `Gamend.Storage` facade, never an adapter directly.
  """

  @type key :: String.t()

  @typedoc """
  An upload ticket handed to a client so it can upload bytes directly to the
  backend (S3/R2) or to the local upload endpoint — the client flow is identical
  either way.
  """
  @type presigned :: %{
          method: String.t(),
          url: String.t(),
          headers: %{optional(String.t()) => String.t()},
          key: key(),
          expires_in: pos_integer()
        }

  @typedoc "A stored object's metadata, as listed by the admin tools."
  @type object :: %{
          key: key(),
          size: non_neg_integer(),
          last_modified: DateTime.t() | nil
        }

  @typedoc "What the backend reports about a stored object without fetching it."
  @type stat :: %{size: non_neg_integer(), content_type: String.t() | nil}

  @callback put(key(), iodata(), keyword()) :: {:ok, key()} | {:error, term()}
  @doc """
  The object's bytes. An object that is not there is `{:error, :not_found}`
  on every backend; any other error is the backend failing.
  """
  @callback get(key()) :: {:ok, binary()} | {:error, :not_found | term()}
  @callback delete(key()) :: :ok | {:error, term()}
  @callback exists?(key()) :: boolean()
  @callback url(key(), keyword()) :: String.t()
  @callback presigned_upload(key(), keyword()) :: {:ok, presigned()} | {:error, term()}

  @doc "One page of objects. Opts: `:prefix`, `:offset`, `:limit`."
  @callback list(keyword()) :: [object()]

  @doc "Total object count and byte size. Opts: `:prefix`."
  @callback usage(keyword()) :: %{count: non_neg_integer(), bytes: non_neg_integer()}

  @doc """
  Size and stored content type of one object, without downloading it.

  `content_type` is whatever the backend recorded; the local adapter keeps no
  per-object metadata and always reports `nil`.
  """
  @callback stat(key()) :: {:ok, stat()} | {:error, term()}

  @doc "Deletes every object under `prefix`. Returns how many were removed."
  @callback delete_prefix(String.t()) :: {:ok, non_neg_integer()} | {:error, term()}
end
