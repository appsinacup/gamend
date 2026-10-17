defmodule Gamend.StorageS3Test do
  @moduledoc """
  The S3 adapter (`Gamend.Storage.S3`) against a fake bucket behind ExAws's
  HTTP client: an object put, read, stat'd, listed, measured and deleted, a
  prefix deleted, a custom endpoint (R2, MinIO) addressed, URLs public or
  through our own `/storage/` redirect or signed, a presigned upload, and a
  bucket that answers errors handed back as errors.
  """
  use ExUnit.Case, async: false

  alias Gamend.Storage.S3

  # ExAws's HTTP client, answering from an in-memory bucket.
  defmodule FakeBucket do
    @behaviour ExAws.Request.HttpClient

    def start,
      do: Agent.start_link(fn -> %{objects: %{}, requests: [], fail: false} end, name: __MODULE__)

    def requests, do: Agent.get(__MODULE__, &Enum.reverse(&1.requests))
    def fail!, do: Agent.update(__MODULE__, &Map.put(&1, :fail, true))

    @impl true
    def request(method, url, body, headers, _opts) do
      uri = URI.parse(url)

      Agent.update(
        __MODULE__,
        &Map.update!(&1, :requests, fn r -> [{method, uri, headers} | r] end)
      )

      if Agent.get(__MODULE__, & &1.fail) do
        {:ok, %{status_code: 500, headers: [], body: "<Error><Code>InternalError</Code></Error>"}}
      else
        answer(method, uri, body)
      end
    end

    defp key(uri),
      do: uri.path |> String.trim_leading("/") |> String.split("/", parts: 2) |> Enum.at(1, "")

    defp answer(:put, uri, body) do
      Agent.update(__MODULE__, &put_in(&1, [:objects, key(uri)], body))
      {:ok, %{status_code: 200, headers: [], body: ""}}
    end

    defp answer(:get, %URI{query: query} = uri, _body) when is_binary(query) do
      prefix = URI.decode_query(query)["prefix"] || ""

      if Map.has_key?(URI.decode_query(query), "list-type") or
           Map.has_key?(URI.decode_query(query), "prefix") do
        listing(prefix)
      else
        object(uri)
      end
    end

    defp answer(:get, uri, _body), do: object(uri)

    defp answer(:head, uri, _body) do
      case Agent.get(__MODULE__, &get_in(&1, [:objects, key(uri)])) do
        nil ->
          {:ok, %{status_code: 404, headers: [], body: ""}}

        data ->
          {:ok,
           %{
             status_code: 200,
             headers: [
               {"Content-Length", Integer.to_string(byte_size(data))},
               {"Content-Type", "image/png"}
             ],
             body: ""
           }}
      end
    end

    defp answer(:delete, uri, _body) do
      Agent.update(__MODULE__, &Map.update!(&1, :objects, fn o -> Map.delete(o, key(uri)) end))
      {:ok, %{status_code: 204, headers: [], body: ""}}
    end

    # Multi-object delete.
    defp answer(:post, _uri, body) do
      keys = Regex.scan(~r{<Key>([^<]+)</Key>}, body, capture: :all_but_first) |> List.flatten()
      Agent.update(__MODULE__, &Map.update!(&1, :objects, fn o -> Map.drop(o, keys) end))
      {:ok, %{status_code: 200, headers: [], body: "<DeleteResult></DeleteResult>"}}
    end

    defp object(uri) do
      case Agent.get(__MODULE__, &get_in(&1, [:objects, key(uri)])) do
        nil ->
          {:ok, %{status_code: 404, headers: [], body: "<Error><Code>NoSuchKey</Code></Error>"}}

        data ->
          {:ok, %{status_code: 200, headers: [], body: data}}
      end
    end

    defp listing(prefix) do
      contents =
        __MODULE__
        |> Agent.get(& &1.objects)
        |> Enum.filter(fn {key, _} -> String.starts_with?(key, prefix) end)
        |> Enum.sort()
        |> Enum.map_join(fn {key, data} ->
          "<Contents><Key>#{key}</Key><LastModified>2026-10-01T10:00:00.000Z</LastModified>" <>
            "<ETag>\"e\"</ETag><Size>#{byte_size(data)}</Size><StorageClass>STANDARD</StorageClass></Contents>"
        end)

      body =
        ~s(<?xml version="1.0" encoding="UTF-8"?><ListBucketResult><Name>bucket</Name>) <>
          "<Prefix>#{prefix}</Prefix><MaxKeys>1000</MaxKeys><IsTruncated>false</IsTruncated>#{contents}</ListBucketResult>"

      {:ok, %{status_code: 200, headers: [], body: body}}
    end
  end

  setup do
    previous = %{
      s3: Application.get_env(:gamend_core, S3),
      storage: Application.get_env(:gamend_core, Gamend.Storage),
      http: Application.get_env(:ex_aws, :http_client),
      retries: Application.get_env(:ex_aws, :retries)
    }

    {:ok, _} = FakeBucket.start()
    Application.put_env(:ex_aws, :http_client, FakeBucket)
    Application.put_env(:ex_aws, :retries, max_attempts: 1)

    Application.put_env(:gamend_core, S3,
      bucket: "bucket",
      access_key_id: "key",
      secret_access_key: "secret",
      region: "auto",
      endpoint: "http://minio.test:9000"
    )

    on_exit(fn ->
      restore(:gamend_core, S3, previous.s3)
      restore(:gamend_core, Gamend.Storage, previous.storage)
      restore(:ex_aws, :http_client, previous.http)
      restore(:ex_aws, :retries, previous.retries)
    end)

    :ok
  end

  defp restore(app, key, nil), do: Application.delete_env(app, key)
  defp restore(app, key, value), do: Application.put_env(app, key, value)

  defp public_url(value) do
    config = Application.get_env(:gamend_core, Gamend.Storage, [])
    Application.put_env(:gamend_core, Gamend.Storage, Keyword.put(config, :public_url, value))
  end

  test "an object is put, read, stat'd and deleted, on the custom endpoint" do
    assert S3.put("avatars/u1/a.png", ["PN", "G"], content_type: "image/png") ==
             {:ok, "avatars/u1/a.png"}

    assert S3.exists?("avatars/u1/a.png")
    assert S3.get("avatars/u1/a.png") == {:ok, "PNG"}
    assert S3.stat("avatars/u1/a.png") == {:ok, %{size: 3, content_type: "image/png"}}

    [{:put, uri, headers} | _] = FakeBucket.requests()
    assert uri.host == "minio.test"
    assert uri.port == 9000

    assert {"content-type", "image/png"} in Enum.map(headers, fn {k, v} ->
             {String.downcase(k), v}
           end)

    assert S3.delete("avatars/u1/a.png") == :ok
    refute S3.exists?("avatars/u1/a.png")
    assert {:error, _} = S3.get("avatars/u1/a.png")
    assert {:error, _} = S3.stat("avatars/u1/a.png")
  end

  test "a prefix is listed, paged, measured and deleted whole" do
    for {key, data} <- [{"pdf/a.pdf", "aa"}, {"pdf/b.pdf", "bbb"}, {"avatars/c.png", "c"}] do
      {:ok, _} = S3.put(key, data, [])
    end

    assert [%{key: "pdf/a.pdf", size: 2, last_modified: %DateTime{}}, %{key: "pdf/b.pdf"}] =
             S3.list(prefix: "pdf/")

    assert [%{key: "pdf/b.pdf"}] = S3.list(prefix: "pdf/", offset: 1, limit: 5)
    assert S3.usage(prefix: "pdf/") == %{count: 2, bytes: 5}
    assert S3.usage() == %{count: 3, bytes: 6}

    assert S3.delete_prefix("pdf/") == {:ok, 2}
    assert S3.list(prefix: "pdf/") == []
    assert [%{key: "avatars/c.png"}] = S3.list([])
  end

  test "a private bucket's URL is our redirect, or a signed link; a public one is plain" do
    public_url(nil)
    assert S3.url("avatars/u1/a.png", []) == "/storage/avatars/u1/a.png"

    signed = S3.url("avatars/u1/a.png", signed: true)
    assert signed =~ "minio.test:9000/bucket/avatars/u1/a.png"
    assert signed =~ "X-Amz-Signature="

    public_url("https://cdn.example.com/")
    assert S3.url("avatars/u1/a.png", []) == "https://cdn.example.com/avatars/u1/a.png"
  end

  test "an upload is presigned for a PUT, with its content type" do
    assert {:ok, upload} =
             S3.presigned_upload("avatars/u1/new.png", content_type: "image/webp", expires_in: 60)

    assert upload.method == "PUT"
    assert upload.headers == %{"content-type" => "image/webp"}
    assert upload.expires_in == 60
    assert upload.url =~ "X-Amz-Expires=60"

    assert {:ok, %{headers: headers}} = S3.presigned_upload("avatars/u1/new.png", [])
    assert headers == %{}
  end

  test "a bucket that answers errors is answered as errors" do
    FakeBucket.fail!()
    assert {:error, _} = S3.put("k", "v", [])
    assert {:error, _} = S3.get("k")
    assert {:error, _} = S3.delete("k")
    refute S3.exists?("k")
  end

  test "an unconfigured bucket says so" do
    Application.put_env(:gamend_core, S3, [])
    assert_raise RuntimeError, ~r/:bucket is not configured/, fn -> S3.get("k") end
  end
end
