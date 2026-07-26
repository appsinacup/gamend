defmodule GameServerWeb.HostPublicDocsTest do
  @moduledoc """
  Guides are files on disk, so nothing about them fails at compile time: a
  malformed, untitled or unreadable one only shows up as a blank section in
  production. These walk every real file the way the page does.

  The page itself lives in the host app, which has no test suite, so this
  covers the part that can break silently — the content, not the route.
  """
  use GameServer.DataCase, async: false

  alias GameServer.Content

  @docs_dir Path.expand(Path.join(__DIR__, "../../../../../priv/docs"))

  setup do
    Content.register_path(:docs, kind: :dir, candidates: [@docs_dir])
    Content.reload()
    on_exit(&Content.reload/0)
    :ok
  end

  test "the guides directory is wired up and non-empty" do
    assert File.dir?(@docs_dir), "expected guides at #{@docs_dir}"

    categories = Content.list_doc_categories()

    assert categories != [], "no guides found - is the :docs content source registered?"
    assert length(Content.list_docs()) > 1
  end

  test "every guide renders to markup" do
    for guide <- Content.list_docs() do
      html = Content.doc_html(guide.slug)

      assert is_binary(html) and html != "", "#{guide.path} rendered nothing"

      # The page prints the title in the summary you click, so the body must
      # not repeat it.
      refute html =~ "<h1>"
    end
  end

  test "each guide carries a title and a one-line summary" do
    for guide <- Content.list_docs() do
      assert guide.title != "", "#{guide.path} has no `# ` heading"

      assert is_binary(guide.summary) and guide.summary != "",
             "#{guide.path} has no opening paragraph to summarise it on the index"
    end
  end

  test "slugs are unique - they are DOM ids and deep-link targets" do
    slugs = Enum.map(Content.list_docs(), & &1.slug)

    assert Enum.uniq(slugs) == slugs
  end

  test "categories come from the folder, in filename order" do
    categories = Content.list_doc_categories()
    names = Enum.map(categories, & &1.category)

    assert "Setup" in names
    refute Enum.any?(names, &String.match?(&1, ~r/^\d/)), "order prefix leaked into a label"

    for %{guides: guides} <- categories do
      refute Enum.any?(guides, &String.match?(&1.slug, ~r/^\d/)),
             "order prefix leaked into a slug"
    end
  end
end
