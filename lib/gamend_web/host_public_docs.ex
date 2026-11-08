defmodule GamendWeb.HostPublicDocs do
  @moduledoc """
  Renders the guides in `priv/docs`: `/docs/setup` indexes them, `/docs/:slug`
  is one guide.

  Everything but the copy is `GamendWeb.DocsLive` — the loader, both layouts
  and the two navigations. This module exists to name the collection and hold
  the wording of its index.

  ## Why a page per guide

  The guides all used to render on `/docs/setup` as `<details>` sections, with
  the open one in the query string. That gave the whole of the documentation a
  single `<title>`, a single description and a single `<h1>`, so nothing could
  match a query about any one topic — and body text collapsed behind a
  disclosure is weighted down besides. A query parameter does not fix that:
  `?guide=payments` is the same URL to a search engine, which is why those
  links canonicalised back to the index.

  Each guide now owns a URL, with `GamendHost.PageMeta` giving it its own
  title, description and breadcrumbs.
  """

  use GamendWeb.DocsLive,
    collection: :docs,
    index_path: "/docs/setup",
    item_path: "/docs",
    download_path: "/docs/download"

  @impl GamendWeb.DocsLive
  def index_title, do: gettext("Setup & Guides")

  @impl GamendWeb.DocsLive
  def index_subtitle,
    do: gettext("Platform setup, OAuth providers, payments, email, and server hooks")
end
