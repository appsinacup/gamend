defmodule Gamend.Storage.S3 do
  @moduledoc """
  S3-compatible storage via ExAws.

  Works with AWS S3, Cloudflare R2, Backblaze B2, MinIO, and DigitalOcean Spaces
  — set `bucket`, `region`, and (for non-AWS) `endpoint` in config. Uploads use
  presigned `PUT` URLs so clients upload straight to the bucket.
  """

  @behaviour Gamend.Storage.Adapter

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

  # With no `public_url` the bucket is private. A signed link expires, so the URL
  # handed out to be stored is our own `/storage/<key>`, which redirects to a
  # fresh one: a signed link saved as a player's `profile_url` stopped loading an
  # hour after the upload.
  @impl true
  def url(key, opts) do
    case Gamend.Settings.get(Gamend.Storage, :public_url) do
      nil ->
        if Keyword.get(opts, :signed, false), do: signed_url(key), else: "/storage/#{key}"

      base ->
        "#{String.trim_trailing(base, "/")}/#{key}"
    end
  end

  defp signed_url(key) do
    {:ok, url} =
      S3.presigned_url(aws_config(), :get, bucket(), key,
        expires_in: Gamend.Storage.signed_url_seconds()
      )

    url
  end

  @impl true
  def presigned_upload(key, opts) do
    expires_in = Keyword.get_lazy(opts, :expires_in, &Gamend.Storage.upload_ttl_seconds/0)
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

  @impl true
  def stat(key) do
    case bucket() |> S3.head_object(key) |> request() do
      {:ok, %{headers: headers}} ->
        {:ok,
         %{
           size: headers |> header("content-length") |> to_size(),
           content_type: header(headers, "content-type")
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def delete_prefix(prefix) do
    keys = prefix |> object_stream() |> Enum.map(& &1.key)

    case bucket() |> S3.delete_all_objects(keys) |> ExAws.request(aws_config_overrides()) do
      {:ok, _} -> {:ok, length(keys)}
      {:error, reason} -> {:error, reason}
    end
  end

  # ExAws returns headers as a list of tuples, and header names are
  # case-insensitive per RFC 9110.
  defp header(headers, name) do
    Enum.find_value(headers, fn {k, v} ->
      if String.downcase(k) == name, do: v
    end)
  end

  defp to_size(nil), do: 0

  defp to_size(value) do
    case Integer.parse(value) do
      {size, _} -> size
      :error -> 0
    end
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
  use Gamend.Settings.Provider,
    app: :gamend_core,
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
    config()[:bucket] || raise "Gamend.Storage.S3 :bucket is not configured"
  end

  defp config, do: Application.get_env(:gamend_core, __MODULE__, [])
end
