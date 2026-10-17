defmodule GamendWeb.Sitemap.CacheTest do
  # The sitemap cache (`GamendWeb.Sitemap.Cache`): a file is generated once
  # and served from storage after, under a signature that is also the ETag;
  # a client that has it gets a 304, one that cannot read gzip gets plain
  # XML, and pruning drops every signature but the current one. The host's
  # inputs come from its `GamendWeb.Sitemap.Source`.
  use GamendWeb.ConnCase, async: false

  alias Gamend.Storage
  alias GamendWeb.Sitemap.Cache
  alias GamendWeb.Sitemap.Source

  defmodule TestSource do
    @behaviour GamendWeb.Sitemap.Source
    def entries, do: []
    def urls(key), do: ["https://example.test/" <> key]
    def signature_inputs, do: [Application.get_env(:gamend_web, :sitemap_test_version, 1)]
  end

  setup do
    previous = Application.get_env(:gamend_web, GamendWeb.Sitemap)

    Application.put_env(
      :gamend_web,
      GamendWeb.Sitemap,
      Keyword.put(previous || [], :source, TestSource)
    )

    on_exit(fn ->
      if previous,
        do: Application.put_env(:gamend_web, GamendWeb.Sitemap, previous),
        else: Application.delete_env(:gamend_web, GamendWeb.Sitemap)

      Application.delete_env(:gamend_web, :sitemap_test_version)
    end)

    %{name: "test-#{System.unique_integer([:positive])}"}
  end

  defp counting do
    counter = :counters.new(1, [])

    {fn -> :counters.add(counter, 1, 1) && ["<urlset>", "</urlset>"] end,
     fn -> :counters.get(counter, 1) end}
  end

  test "a miss generates and stores, a hit serves the stored bytes", %{name: name} do
    {generate, calls} = counting()
    assert {:ok, gzipped, :miss} = Cache.fetch(name, generate)
    assert :zlib.gunzip(gzipped) == "<urlset></urlset>"
    assert {:ok, ^gzipped, :hit} = Cache.fetch(name, generate)
    assert calls.() == 1
  end

  test "the host's inputs move the signature, and with it the key", %{name: name} do
    before = Cache.signature()
    assert Cache.signature() == before
    Application.put_env(:gamend_web, :sitemap_test_version, 2)
    refute Cache.signature() == before
    assert Cache.key(name) =~ Cache.signature()
  end

  test "served gzipped to a crawler, plain to a client without gzip, 304 to one that has it",
       %{conn: conn, name: name} do
    {generate, _calls} = counting()

    gz = conn |> put_req_header("accept-encoding", "gzip") |> Cache.serve(name, generate)
    assert gz.status == 200
    assert get_resp_header(gz, "content-encoding") == ["gzip"]
    assert [etag] = get_resp_header(gz, "etag")

    plain = build_conn() |> Cache.serve(name, generate)
    assert plain.resp_body == "<urlset></urlset>"
    assert get_resp_header(plain, "cache-control") == ["public, max-age=86400"]

    again =
      build_conn()
      |> put_req_header("if-none-match", etag)
      |> Cache.serve(name, generate, cache_control: "no-cache")

    assert again.status == 304
    assert get_resp_header(again, "cache-control") == ["no-cache"]
  end

  test "prune drops the old signatures and keeps the current one", %{name: name} do
    {generate, _calls} = counting()
    {:ok, _, :miss} = Cache.fetch(name, generate)
    old_key = Cache.key(name)

    Application.put_env(:gamend_web, :sitemap_test_version, 99)
    {:ok, _, :miss} = Cache.fetch(name, generate)
    new_key = Cache.key(name)

    :ok = Cache.prune()
    assert {:error, _} = Storage.get(old_key)
    assert {:ok, _} = Storage.get(new_key)
  end

  test "the source names the URLs of changed keys; with no source, none" do
    assert Source.urls_for(["a", "b"]) == ["https://example.test/a", "https://example.test/b"]
    assert Source.signature_inputs() == [1]

    Application.put_env(:gamend_web, GamendWeb.Sitemap, [])
    assert Source.urls_for(["a"]) == []
    assert Source.signature_inputs() == []
    assert Source.source() == nil
  end
end
