defmodule GamendWeb.PageMeta.Provider do
  @moduledoc """
  Behaviour for the host module that supplies per-page SEO metadata.

      config :gamend_web, page_meta_provider: MyHost.PageMeta

  The copy on a page is the host's, not core's, so this is a seam rather than
  a setting. Every callback is optional: a host that only wants descriptions
  implements `describe/1` and nothing else.

  `GamendWeb.PageMeta` holds the mechanics a provider builds on — normalising
  the path, trimming a description to what a search engine shows, turning a
  breadcrumb trail into `BreadcrumbList` markup.

  `GamendWeb.Plugs.PageMeta` probes each function by name at request time,
  because it must: a release loads modules lazily, so a provider may not be
  loaded the first time a page is served. The behaviour gives the check
  something to be checked against, and a host that misspells a callback hears
  about it at compile time.
  """

  @doc ~S'The `<meta name="description">` for `path`, or `nil` to fall back.'
  @callback describe(path :: String.t()) :: String.t() | nil

  @doc """
  An SEO `<title>` for `path`, when the in-page `:page_title` is a short UI
  label ("Learn") rather than something anyone searches for.
  """
  @callback title(path :: String.t()) :: String.t() | nil

  @doc "schema.org objects for `path`, rendered as `application/ld+json`."
  @callback json_ld(path :: String.t()) :: [map()]

  @doc """
  The `og:image` for `path` — a root-relative path or an absolute URL — or
  `nil` for the theme's banner. A guide with a social card of its own, a
  blog post with a cover: the image a link to the page unfurls with.
  """
  @callback image(path :: String.t()) :: String.t() | nil

  @doc """
  The breadcrumb trail for `path`, as `{label, path}` pairs ending with the
  current page (whose path may be `nil`), or `[]` for none.
  """
  @callback breadcrumbs(path :: String.t()) :: [{String.t(), String.t() | nil}]

  @doc ~S'The `<meta name="robots">` value for `path` ("noindex, follow"), or `nil`.'
  @callback robots(path :: String.t()) :: String.t() | nil

  @optional_callbacks describe: 1, title: 1, json_ld: 1, image: 1, breadcrumbs: 1, robots: 1
end
