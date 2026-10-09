defmodule GamendWeb.Sitemap.Cache do
  @moduledoc """
  Stores rendered sitemap XML on `Gamend.Storage` so a request serves bytes
  instead of rebuilding them.

  A large sitemap is ~19 MB and ~5,000 URLs, 90% of it the hreflang alternates
  every URL carries. Building one walks the host's content, resolves a date per
  key and interleaves an alternate per locale per URL — and a controller does
  that on **every** request, for a public endpoint anyone can loop on. Fifty
  children is roughly a gigabyte of generation per full crawl.

  ## Keyed by a content signature, not by name alone

  The obvious version — precompute at restamp time — goes stale the moment
  something changes that `mix gamend.sitemap.lastmod` does not stamp: a new
  blog post, a new page, a language gaining content. Those move the sitemap
  without moving the manifest.

  So the key carries a signature of everything the output depends on. A change
  to any of it lands on a key that does not exist yet and regenerates once; the
  old object is simply orphaned, and swept by `prune/0`. That makes the cache
  self-healing: forgetting to warm it costs one slow request, never a wrong
  sitemap.

  The signature is deliberately cheap — a `File.stat` of the manifest rather
  than a hash of its thousands of entries, because it is computed on every
  request, and it doubles as the ETag.

  ## What the host contributes

  Core knows the inputs every host shares — the manifest's stamp, the endpoint
  URL, the locale set. It cannot know the rest, so `c:signature_inputs/0` on
  the configured `GamendWeb.Sitemap.Source` returns them: the counts and
  versions that decide how many URLs exist.

  Anything the rendered XML depends on belongs in that list. **Include a
  version number the host bumps by hand**, too — pages decided by code rather
  than data change the output and nothing derived from content would notice.

  ## Stored gzipped

  Uncompressed, fifty children would be about a gigabyte on the volume; XML of
  this shape compresses roughly ten to one. Every crawler sends
  `accept-encoding: gzip`, so the common path also skips decompression
  entirely — the stored bytes go straight out.
  """

  alias Gamend.Storage
  alias GamendWeb.Plugs.LocalePath
  alias GamendWeb.Sitemap.Source

  require Logger

  @prefix "sitemap"

  @doc """
  The cache key for `name` under the current signature.

  `name` is the sitemap's own name — `"index"`, `"pages"`, or whatever the host
  calls a child.
  """
  @spec key(String.t()) :: String.t()
  def key(name), do: "#{@prefix}/#{signature()}/#{name}.xml.gz"

  @doc """
  Gzipped bytes for `name`, generating and storing them on a miss.

  `generate` returns the iodata body, and is only called on a miss — building
  it eagerly and passing the result would leave the whole cost in place and
  cache only the write.

  A storage failure is logged and downgraded to a miss: serving an uncached
  sitemap is better than serving none.
  """
  @spec fetch(String.t(), (-> iodata())) :: {:ok, binary(), :hit | :miss}
  def fetch(name, generate) when is_binary(name) and is_function(generate, 0) do
    cache_key = key(name)

    case Storage.get(cache_key) do
      {:ok, gzipped} when byte_size(gzipped) > 0 ->
        {:ok, gzipped, :hit}

      _ ->
        gzipped = generate.() |> IO.iodata_to_binary() |> :zlib.gzip()

        case Storage.put(cache_key, gzipped, content_type: "application/gzip") do
          {:ok, _} -> :ok
          {:error, reason} -> Logger.warning("sitemap cache write failed: #{inspect(reason)}")
        end

        {:ok, gzipped, :miss}
    end
  end

  @doc """
  The signature every cache key is scoped by, and the ETag every response
  carries.

  Covers each input that changes the rendered XML: the manifest (mtime and
  size — a restamp moves both), the endpoint URL every `<loc>` is built from,
  the locale set that decides the alternates per URL, and whatever the host's
  `c:GamendWeb.Sitemap.Source.signature_inputs/0` adds.
  """
  @spec signature() :: String.t()
  def signature do
    manifest_stamp =
      case File.stat(Source.manifest_path()) do
        {:ok, %{mtime: mtime, size: size}} -> {mtime, size}
        _ -> :missing
      end

    [
      manifest_stamp,
      GamendWeb.endpoint().url(),
      length(LocalePath.hreflang_locales()) | Source.signature_inputs()
    ]
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
    |> binary_part(0, 16)
  end

  @doc """
  Renders `name` through the cache and sends it.

  The signature doubles as the ETag, so a crawler that already has the file
  gets a 304 and the body is never sent at all — which is the cheapest possible
  answer to the request a crawler makes most often.

  Bytes are stored gzipped, which is what every crawler asks for anyway; only a
  client that does not accept gzip pays for the decompression.

  Options: `:cache_control` (default one day — the sitemap changes when content
  does, and the ETag makes a repeat fetch a 304 either way).
  """
  @spec serve(Plug.Conn.t(), String.t(), (-> iodata()), keyword()) :: Plug.Conn.t()
  def serve(conn, name, generate, opts \\ []) do
    cache_control = Keyword.get(opts, :cache_control, "public, max-age=86400")
    etag = ~s("#{signature()}-#{name}")

    conn = Plug.Conn.put_resp_header(conn, "etag", etag)
    conn = Plug.Conn.put_resp_header(conn, "cache-control", cache_control)

    if etag in Plug.Conn.get_req_header(conn, "if-none-match") do
      Plug.Conn.send_resp(conn, 304, "")
    else
      {:ok, gzipped, _origin} = fetch(name, generate)

      conn
      |> Plug.Conn.put_resp_content_type("application/xml")
      |> send_body(gzipped)
    end
  end

  # No `vary: accept-encoding` here — Bandit's compression layer adds it to
  # every compressible response already, and setting it too sent the header
  # twice. Both spellings are legal and mean the same thing, which is why it
  # went unnoticed.
  defp send_body(conn, gzipped) do
    if accepts_gzip?(conn) do
      conn
      |> Plug.Conn.put_resp_header("content-encoding", "gzip")
      |> Plug.Conn.send_resp(200, gzipped)
    else
      Plug.Conn.send_resp(conn, 200, :zlib.gunzip(gzipped))
    end
  end

  defp accepts_gzip?(conn) do
    conn
    |> Plug.Conn.get_req_header("accept-encoding")
    |> Enum.any?(&String.contains?(&1, "gzip"))
  end

  @doc """
  Deletes every cached sitemap whose signature is not the current one.

  Nothing depends on this — a stale object is unreachable, not wrong — so it is
  housekeeping rather than part of the request path.
  """
  @spec prune() :: :ok
  def prune do
    current = "#{@prefix}/#{signature()}/"

    # Every page of the listing, not the first: a host with a thousand
    # children has more current objects than one page holds, and the keys
    # sort, so a single page could be all current ones and nothing old was
    # ever deleted. Each old signature then goes as one prefix.
    0
    |> signature_prefixes(MapSet.new())
    |> MapSet.delete(current)
    |> Enum.each(&Storage.delete_prefix/1)

    :ok
  end

  @prune_page 1000

  # No `is_list` guard: `Gamend.Storage.Adapter`'s `list/1` callback is typed
  # `[object()]`, so the fallback branch this used to carry was unreachable —
  # dialyzer flagged it as pattern_match_cov.
  defp signature_prefixes(offset, acc) do
    page = Storage.list_objects(prefix: "#{@prefix}/", offset: offset, limit: @prune_page)

    acc =
      Enum.reduce(page, acc, fn object, acc ->
        case object |> object_key() |> String.split("/", parts: 3) do
          [@prefix, signature, _name] -> MapSet.put(acc, "#{@prefix}/#{signature}/")
          _ -> acc
        end
      end)

    if length(page) < @prune_page,
      do: acc,
      else: signature_prefixes(offset + @prune_page, acc)
  end

  defp object_key(%{key: key}), do: key
  defp object_key(%{"key" => key}), do: key
  defp object_key(key) when is_binary(key), do: key
  defp object_key(_), do: ""
end
