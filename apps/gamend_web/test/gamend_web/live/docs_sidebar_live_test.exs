defmodule GamendWeb.DocsSidebarLiveTest do
  @moduledoc """
  The `:sidebar` layout of `GamendWeb.DocsLive`: the tree beside every page,
  a landing page per category, breadcrumbs and a table of contents.

  Core's router carries no docs route — that is the host's — so the index
  mounts in isolation and the page components render directly, with the
  assigns `handle_params/3` would have built from `Gamend.Content`.
  """
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gamend.Content
  alias GamendWeb.DocsLive
  alias Phoenix.HTML.Safe

  @collection :sidebar_test_docs

  defmodule SidebarDocsLive do
    use GamendWeb.DocsLive,
      collection: :sidebar_test_docs,
      index_path: "/docs",
      item_path: "/docs",
      layout: :sidebar,
      edit_url: "https://example.com/edit/docs"

    @impl GamendWeb.DocsLive
    def index_title, do: "Manual"
  end

  setup do
    root = Path.join(System.tmp_dir!(), "gamend_sidebar_#{System.unique_integer([:positive])}")

    write(
      root,
      "10-intro.md",
      "---\ntitle: Introduction\ndescription: Start here.\n---\n\nHello.\n\n## Why\n\n### Because\n"
    )

    write(
      root,
      "20-manual/_category.md",
      "---\ntitle: The manual\ncollapsed: true\ncolor: text-rose-400\n---\n"
    )

    write(root, "20-manual/10-scenes.md", "# Scenes\n\nTrees.\n\n## Nodes\n")
    write(root, "20-manual/20-scripting.md", "# Scripting\n\nRune.\n")

    write(
      root,
      "30-reference/_category.md",
      "---\ntitle: Reference\ndescription: Every API.\n---\n"
    )

    write(root, "30-reference/body2d.md", "# body2d\n\nA body.\n")

    Content.register_path(@collection, kind: :dir, path: root, nesting: :tree, base_path: "/docs")

    on_exit(fn ->
      Content.unregister_path(@collection)
      File.rm_rf(root)
    end)

    :ok
  end

  defp write(root, relative, content) do
    path = Path.join(root, relative)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
  end

  # `live_isolated/3` cannot run `handle_params/3`, which every page of the
  # module goes through, so the index renders as the component the mounted
  # module would call, with the assigns `mount/3` puts in place.
  test "the index shows the tree and a card per top-level entry" do
    html =
      render_component(&DocsLive.sidebar_index/1,
        flash: %{},
        tree: Content.doc_tree(@collection),
        item_path: "/docs",
        index_path: "/docs",
        title: "Manual",
        subtitle: "Read me.",
        empty_message: "None"
      )

    doc = LazyHTML.from_fragment(html)
    # The tree is rendered twice — folded above the article on a phone, in a
    # column beside it on a desktop — so the desktop copy is the one queried.
    nav = LazyHTML.query(doc, "aside nav[aria-label='Manual']")

    assert LazyHTML.text(LazyHTML.query(nav, "a[href='/docs/intro']")) =~ "Introduction"
    assert LazyHTML.text(LazyHTML.query(nav, "a[href='/docs/manual']")) =~ "The manual"
    # A collapsed category still lists its pages; the disclosure is closed.
    assert Enum.count(LazyHTML.query(nav, "details a[href='/docs/manual/scenes']")) == 1
    assert Enum.empty?(LazyHTML.query(nav, "details[open] a[href='/docs/manual/scenes']"))

    assert LazyHTML.text(LazyHTML.query(doc, "a.card[href='/docs/reference']")) =~ "Every API."
    assert LazyHTML.text(LazyHTML.query(doc, "a.card[href='/docs/manual']")) =~ "2 pages"
    assert html =~ "Read me."
  end

  test "the module's own render dispatches on the page" do
    # The mounted module goes through `handle_params/3`; a plain render of
    # its index assigns proves the macro wired `:sidebar` in.
    assigns = %{
      __changed__: %{},
      flash: %{},
      current_scope: nil,
      current_path: nil,
      page: :index,
      categories: Content.list_doc_categories(@collection),
      tree: Content.doc_tree(@collection),
      live_action: :index
    }

    html =
      assigns
      |> SidebarDocsLive.render()
      |> Safe.to_iodata()
      |> IO.iodata_to_binary()

    assert html =~ ~s(aria-label="Manual")
  end

  test "a page renders the trail, the table of contents, the edit link and its place in the tree" do
    slug = "manual/scenes"
    {prev, next} = Content.doc_neighbours(@collection, slug)

    html =
      render_component(&DocsLive.sidebar_show/1,
        flash: %{},
        tree: Content.doc_tree(@collection),
        item_path: "/docs",
        index_path: "/docs",
        title: "Manual",
        guide: Content.get_doc(@collection, slug),
        category: Content.doc_category(@collection, slug),
        html: Content.doc_html(@collection, slug),
        toc: Content.doc_toc(@collection, slug),
        prev: prev,
        next: next,
        breadcrumbs: Content.doc_breadcrumbs(@collection, slug),
        current_slug: slug,
        edit_url:
          DocsLive.edit_url(
            "https://example.com/edit/docs",
            @collection,
            Content.get_doc(@collection, slug)
          )
      )

    # Breadcrumb: collection, category, then the page unlinked.
    assert html =~ ~s(aria-label="Breadcrumb")
    assert html =~ ~s(href="/docs/manual")
    assert html =~ ~s(<span aria-current="page">Scenes</span>)

    # The tree opens the category the reader is in and marks the page.
    assert html =~ ~s(<details open>)

    assert Regex.match?(
             ~r{href="/docs/manual/scenes"[^>]*bg-primary/10[^>]*aria-current="page"},
             html
           )

    assert html =~ ~s(href="#nodes")
    assert html =~ ~s(href="https://example.com/edit/docs/20-manual/10-scenes.md")

    # Previous and next across the tree.
    assert html =~ ~s(href="/docs/intro")
    assert html =~ ~s(href="/docs/manual/scripting")

    # The page's icon and its category in the tree wear the category's colour.
    assert html =~ "hero-document-text size-8 shrink-0 opacity-80 text-rose-400"
    assert html =~ "hero-folder size-4 shrink-0 text-rose-400"
  end

  test "a category without an index gets a landing page of its children" do
    html =
      render_component(&DocsLive.sidebar_category/1,
        flash: %{},
        tree: Content.doc_tree(@collection),
        item_path: "/docs",
        index_path: "/docs",
        title: "Manual",
        category_page: Content.get_doc_category(@collection, "reference"),
        breadcrumbs: Content.doc_breadcrumbs(@collection, "reference"),
        current_slug: "reference"
      )

    assert html =~ "Reference"
    assert html =~ "Every API."
    assert html =~ ~s(href="/docs/reference/body2d")
  end

  test "the cards layout is untouched" do
    html =
      render_component(&DocsLive.index/1,
        flash: %{},
        categories: Content.list_doc_categories(@collection),
        item_path: "/docs",
        title: "Manual",
        subtitle: nil,
        empty_message: "None"
      )

    assert html =~ "The manual"
    refute html =~ "aria-label=\"Manual\""
  end
end
