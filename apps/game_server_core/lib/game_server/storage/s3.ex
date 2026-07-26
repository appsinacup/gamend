defmodule GameServer.Storage.S3 do
  @moduledoc """
  S3-compatible storage via ExAws.

  Works with AWS S3, Cloudflare R2, Backblaze B2, MinIO, and DigitalOcean Spaces
  — set `bucket`, `region`, and (for non-AWS) `endpoint` in config. Uploads use
  presigned `PUT` URLs so clients upload straight to the bucket.
  """

  @behaviour GameServer.Storage.Adapter

  alias ExAws.S3

  @impl true
  def put(key, data, opts) do
    s3_opts =
      [
        content_type: Keyword.get(opts, :content_type),
        cache_control: Keyword.get(opts, :cache_control)
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    case bucket() |> S3.put_object(key, IO.iodata_to_binary(data), s3_opts) |> request() do
      {:ok, _} -> {:ok, key}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def get(key) do
    case bucket() |> S3.get_object(key) |> request() do
      {:ok, %{body: body}} -> {:ok, body}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def delete(key) do
    case bucket() |> S3.delete_object(key) |> request() do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def exists?(key) do
    match?({:ok, _}, bucket() |> S3.head_object(key) |> request())
  end

  @impl true
  def url(key, opts) do
    case GameServer.Settings.get(GameServer.Storage, :public_url) do
      nil ->
        {:ok, url} =
          S3.presigned_url(aws_config(), :get, bucket(), key,
            expires_in: Keyword.get(opts, :expires_in, 3600)
          )

        url

      base ->
        "#{String.trim_trailing(base, "/")}/#{key}"
    end
  end

  @impl true
  def presigned_upload(key, opts) do
    expires_in = Keyword.get(opts, :expires_in, 600)
    content_type = Keyword.get(opts, :content_type)

    case S3.presigned_url(aws_config(), :put, bucket(), key, expires_in: expires_in) do
      {:ok, url} ->
        headers = if content_type, do: %{"content-type" => content_type}, else: %{}
        {:ok, %{method: "PUT", url: url, headers: headers, key: key, expires_in: expires_in}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def list(opts) do
    prefix = Keyword.get(opts, :prefix) || ""
    offset = Keyword.get(opts, :offset, 0)
    limit = Keyword.get(opts, :limit, 50)

    object_stream(prefix)
    |> Stream.map(&to_object/1)
    |> Enum.slice(offset, limit)
  end

  @impl true
  def usage(opts \\ []) do
    prefix = Keyword.get(opts, :prefix) || ""

    object_stream(prefix)
    |> Enum.reduce(%{count: 0, bytes: 0}, fn obj, acc ->
      %{count: acc.count + 1, bytes: acc.bytes + parse_size(obj)}
    end)
  end

  defp object_stream(prefix) do
    bucket()
    |> S3.list_objects(prefix: prefix)
    |> ExAws.stream!(aws_config_overrides())
  end

  defp to_object(obj) do
    %{
      key: Map.get(obj, :key),
      size: parse_size(obj),
      last_modified: parse_time(obj[:last_modified])
    }
  end

  defp parse_size(obj) do
    case obj |> Map.get(:size, "0") |> to_string() |> Integer.parse() do
      {n, _} -> n
      :error -> 0
    end
  end

  defp parse_time(nil), do: nil

  defp parse_time(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp request(op), do: ExAws.request(op, aws_config_overrides())

  defp aws_config, do: ExAws.Config.new(:s3, aws_config_overrides())

  defp aws_config_overrides do
    cfg = config()

    [
      access_key_id: cfg[:access_key_id],
      secret_access_key: cfg[:secret_access_key],
      region: cfg[:region] || "auto"
    ]
    |> maybe_endpoint(cfg[:endpoint])
  end

  # For R2 / MinIO / Spaces, point ExAws at a custom endpoint host.
  defp maybe_endpoint(opts, endpoint) when is_binary(endpoint) and endpoint != "" do
    uri = URI.parse(endpoint)

    Keyword.merge(opts,
      scheme: "#{uri.scheme}://",
      host: uri.host,
      port: uri.port
    )
  end

  defp maybe_endpoint(opts, _), do: opts

  # Credentials are required only once the adapter is actually s3 — a
  # deployment on local disk should not be asked for a bucket. Silently
  # degrading to local instead would lose every upload on the next redeploy,
  # so these fail the boot rather than warn.
  use GameServer.Settings.Provider,
    app: :game_server_core,
    group: :storage,
    label: "Storage"

  @s3_selected {[:storage, :adapter], :s3}

  setting(:bucket, :string, required: :prod, when: @s3_selected)
  setting(:access_key_id, :string, secret: true, required: :prod, when: @s3_selected)
  setting(:secret_access_key, :string, secret: true, required: :prod, when: @s3_selected)

  setting(:region, :string,
    default: "auto",
    doc: "Region, or \"auto\" for services that do not use one (R2, MinIO)."
  )

  setting(:endpoint, :string,
    doc: "Custom endpoint, e.g. https://<account>.r2.cloudflarestorage.com."
  )

  defp bucket do
    config()[:bucket] || raise "GameServer.Storage.S3 :bucket is not configured"
  end

  defp config, do: Application.get_env(:game_server_core, __MODULE__, [])
end
