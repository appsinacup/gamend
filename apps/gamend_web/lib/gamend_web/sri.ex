defmodule GamendWeb.SRI do
  @moduledoc """
  Computes Subresource Integrity (SRI) hashes for static assets.

  Returns a `sha384-<base64>` string suitable for the `integrity` attribute
  on `<script>` and `<link>` tags. In environments without code reloading,
  hashes are cached in `persistent_term` until the static files are reloaded
  (`GamendWeb.ProjectStatic.reload/0`, run on a theme reload).

  Returns `nil` when the file doesn't exist (e.g. in dev before digest),
  so the attribute is safely omitted from the rendered HTML.

  ## Usage in HEEx templates

      <% path = ~p"/assets/js/app.js" %>
      <script src={path} integrity={SRI.integrity(path)} crossorigin="anonymous"></script>

  The module is aliased as `SRI` in html_helpers, so it's available in all
  templates without an explicit alias.

  ## Project files

  Files are found through `GamendWeb.ProjectStatic.path_for/1`, so a file a
  project puts in its static overlay is hashed rather than the engine's file at
  the same path: `versioned_path/1` names the bytes the endpoint actually
  serves. `integrity/1` is `nil` for any path the overlay could answer: the
  endpoint checks the overlay on every request while the hash here is cached
  until a reload, so a file dropped in or edited in between would otherwise be
  refused by the browser for not matching an integrity it was never hashed for.
  Same-origin integrity guards against nothing the page itself could not
  change, so dropping it costs nothing.
  """

  alias GamendWeb.ProjectStatic

  @pt_namespace {__MODULE__, :integrity}

  @doc """
  Returns the SRI integrity hash (`"sha384-..."`) for the given static path,
  or `nil` if the file cannot be found.

  The `path` should be the URL path as returned by the `~p` sigil
  (e.g. `"/assets/js/app.js"` or `"/assets/js/app-ABC123.js"` after digest).
  """
  @spec integrity(String.t() | nil) :: String.t() | nil
  def integrity(path) when is_binary(path) and path != "" do
    if ProjectStatic.overlay_servable?(path), do: nil, else: hash(path)
  end

  def integrity(_), do: nil

  # Cached per path until `GamendWeb.ProjectStatic.generation/0` moves (a
  # theme reload, variants cut after boot): the entry is overwritten then, so
  # the key set stays bounded by the paths pages link.
  defp hash(path) do
    if cache_enabled?() do
      key = {@pt_namespace, path}
      generation = ProjectStatic.generation()

      case :persistent_term.get(key, :miss) do
        {^generation, result} -> result
        _ -> compute_and_cache(key, generation, path)
      end
    else
      compute(path)
    end
  end

  @doc """
  Returns a cache-busted version of the given static path by appending a
  content-derived `v` query parameter.

  This avoids browsers reusing a stale `/assets/...` response under a newer
  integrity hash when assets change locally without a full browser cache clear.
  """
  @spec versioned_path(String.t() | nil) :: String.t() | nil
  def versioned_path(path) when is_binary(path) and path != "" do
    case hash(path) do
      nil -> path
      sri -> append_version_query(path, sri)
    end
  end

  def versioned_path(_), do: nil

  defp compute_and_cache(key, generation, path) do
    hash = compute(path)

    :persistent_term.put(key, {generation, hash})
    hash
  end

  # `path_for/1` drops the query and fragment, and answers nil for an absolute
  # URL: a logo on a CDN is not the local file that happens to share its path.
  # A file listed but missing (a manifest entry whose file was removed) is nil
  # too, and the caller links the path as written.
  defp compute(path) do
    with file_path when is_binary(file_path) <- ProjectStatic.path_for(path),
         {:ok, content} <- File.read(file_path) do
      digest = :crypto.hash(:sha384, content) |> Base.encode64()
      "sha384-#{digest}"
    else
      _ -> nil
    end
  end

  defp cache_enabled? do
    endpoint_config = Application.get_env(:gamend_web, GamendWeb.Endpoint, [])
    not Keyword.get(endpoint_config, :code_reloader, false)
  end

  defp append_version_query(path, sri) do
    uri = URI.parse(path)
    version = String.trim_leading(sri, "sha384-")
    query = merge_query(uri.query, "v", version)

    uri
    |> Map.put(:query, query)
    |> URI.to_string()
  end

  defp merge_query(nil, key, value), do: URI.encode_query(%{key => value})

  defp merge_query(query, key, value) when is_binary(query) do
    query
    |> URI.decode_query()
    |> Map.put(key, value)
    |> URI.encode_query()
  end
end
