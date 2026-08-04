defmodule GamendWeb.Plugs.PageMeta do
  @moduledoc """
  Assigns per-page SEO metadata so the root layout can render a `<meta
  name="description">` that is unique to the page.

  Without this every page inherits the theme's site-wide description, which
  search engines treat as duplicate boilerplate and which suppresses
  click-through on every page but the landing page.

  The copy itself is host content, not core's business, so it comes from a
  host-supplied provider configured as

      config :gamend_web, page_meta_provider: MyHost.PageMeta

  The provider implements:

    * `describe(path) :: String.t() | nil` — the meta description
    * `title(path) :: String.t() | nil` — an optional SEO `<title>`, used when
      the in-page `:page_title` is a short UI label ("Learn") rather than
      something anyone searches for ("Vocabulary Lists for 50 Languages")
    * `json_ld(path) :: [map()]` — schema.org objects for the page, rendered
      as `application/ld+json`
    * `breadcrumbs(path) :: [{String.t(), String.t() | nil}]` — the trail, as
      `{label, path}` pairs ending with the current page (whose path may be
      `nil`). The layout renders it and the provider should build its
      `BreadcrumbList` markup from the same list, so the two cannot drift.

  Returning `nil` (or `[]`) leaves the assign unset and the layout falls back
  to the page title and theme description.

  Runs in the `:browser` pipeline, so the assign is present for the initial
  render of both controller pages and LiveViews — which is the render crawlers
  see.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    # `:seo_path` is the locale-free path (LocalePath assigns it). Looking up
    # `request_path` instead would miss every localized URL, since `/es/about`
    # is not a key any provider would write.
    path = conn.assigns[:seo_path] || conn.request_path

    # Stashed for the layout shell. `Layouts.app` is a function component, so
    # it only sees the attrs a template hands it — several core templates pass
    # neither `current_path` nor `conn`, and the shell would otherwise think
    # every one of them is the home page. Set on every browser request before
    # anything renders, so a keep-alive connection cannot serve a stale value.
    Process.put(:gamend_page_path, path)

    conn
    |> maybe_assign(:meta_description, provider_call(:describe, path))
    |> maybe_assign(:seo_title, provider_call(:title, path))
    |> maybe_assign(:json_ld, provider_call(:json_ld, path))
    |> maybe_assign(:breadcrumbs, provider_call(:breadcrumbs, path))
  end

  defp maybe_assign(conn, key, value) when is_binary(value) and value != "",
    do: assign(conn, key, value)

  defp maybe_assign(conn, key, [_ | _] = value), do: assign(conn, key, value)

  defp maybe_assign(conn, _key, _value), do: conn

  defp provider_call(fun, path) do
    case Application.get_env(:gamend_web, :page_meta_provider) do
      nil ->
        nil

      module ->
        # Releases load modules lazily, so `function_exported?` alone can
        # report false for a module that simply has not been loaded yet.
        if Code.ensure_loaded?(module) and function_exported?(module, fun, 1) do
          apply(module, fun, [path])
        end
    end
  end
end
