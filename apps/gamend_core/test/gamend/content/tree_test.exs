defmodule Gamend.Content.TreeTest do
  @moduledoc """
  A nested guide collection, read through `Gamend.Content` the way a docs
  page would. Fixtures are written to a temporary directory per test and
  registered under a name only that test uses.
  """
  use ExUnit.Case, async: false

  alias Gamend.Content
  alias Gamend.Content.Tree

  @collection :tree_test_docs

  setup do
    root = Path.join(System.tmp_dir!(), "gamend_tree_#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)

    write(
      root,
      "10-intro.md",
      "---\ntitle: Introduction\ndescription: What it is.\nimage: /img/social/intro.png\nkeywords: [engine, intro]\n---\n\nFirst paragraph.\n"
    )

    write(root, "principles.md", "---\nposition: 2\n---\n# Principles\n\nWhy.\n")

    write(
      root,
      "30-manual/_category.md",
      "---\ntitle: Manual\nicon: hero-book-open\ncolor: text-accent\ncollapsed: false\nposition: 5\n---\n"
    )

    write(
      root,
      "30-manual/20-scenes.md",
      "# Scenes and nodes\n\nA scene is a tree. See [scripting](./10-scripting.md#hot-reload) and [intro](../10-intro.md).\n\n## Nodes\n\n### Kinds\n"
    )

    write(
      root,
      "30-manual/10-scripting.md",
      "---\nsidebar_label: Scripting\n---\n# Scripting in Rune\n\nScripts.\n\n## Hot reload\n"
    )

    write(
      root,
      "40-reference/index.md",
      "---\ntitle: Reference\nslug: /reference\ndescription: Every component.\n---\n\nThe API.\n"
    )

    write(root, "40-reference/_category.md", "---\ntitle: Reference\nposition: 9\n---\n")

    write(
      root,
      "40-reference/components/_category.md",
      "---\ntitle: Components\ndescription: One per node kind.\n---\n"
    )

    write(root, "40-reference/components/body2d.md", "# `body2d`\n\nA body.\n")
    write(root, "40-reference/components/anchor.md", "# `anchor`\n\nAn anchor.\n")
    write(root, "_partial.md", "# Not a page\n")
    write(root, "30-manual/_features.md", "# Not a page either\n")

    Content.register_path(@collection,
      kind: :dir,
      path: root,
      nesting: :tree,
      base_path: "/docs",
      assets: :static
    )

    on_exit(fn ->
      Content.unregister_path(@collection)
      File.rm_rf(root)
    end)

    {:ok, root: root}
  end

  defp write(root, relative, content) do
    path = Path.join(root, relative)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
  end

  test "the tree is ordered by position, then prefix, then name, and skips underscored files" do
    tree = Content.doc_tree(@collection)

    assert Enum.map(tree, &{&1.type, &1.slug}) == [
             {:doc, "principles"},
             {:category, "manual"},
             {:category, "reference"},
             {:doc, "intro"}
           ]

    manual = Enum.at(tree, 1)
    assert Enum.map(manual.children, & &1.slug) == ["manual/scripting", "manual/scenes"]
    assert manual.title == "Manual"
    assert manual.icon == "hero-book-open"
    assert manual.color == "text-accent"
    refute manual.collapsed
  end

  test "reading order flattens a category's own page before its children" do
    assert Enum.map(Content.list_docs(@collection), & &1.slug) == [
             "principles",
             "manual/scripting",
             "manual/scenes",
             "reference",
             "reference/components/anchor",
             "reference/components/body2d",
             "intro"
           ]
  end

  test "a guide carries its frontmatter, and falls back to its heading" do
    intro = Content.get_doc(@collection, "intro")
    assert intro.title == "Introduction"
    assert intro.summary == "What it is."
    assert intro.image == "/img/social/intro.png"
    assert intro.keywords == ["engine", "intro"]

    scripting = Content.get_doc(@collection, "manual/scripting")
    assert scripting.title == "Scripting in Rune"
    assert scripting.label == "Scripting"
    assert scripting.summary == "Scripts."
  end

  test "a folder's index.md is the category's page, at the slug the frontmatter names" do
    reference = Content.get_doc(@collection, "reference")
    assert reference.index?
    assert reference.title == "Reference"

    category = Content.get_doc_category(@collection, "reference")
    assert category.index.slug == "reference"
    assert category.description == "Every component."
    assert [%{type: :category, slug: "reference/components"}] = category.children
  end

  test "a category without an index still has a page's worth of metadata" do
    components = Content.get_doc_category(@collection, "reference/components")

    assert components.index == nil
    assert components.title == "Components"
    assert components.description == "One per node kind."

    assert Enum.map(components.children, & &1.slug) == [
             "reference/components/anchor",
             "reference/components/body2d"
           ]
  end

  test "breadcrumbs walk the categories down to the guide" do
    crumbs = Content.doc_breadcrumbs(@collection, "reference/components/body2d")

    assert Enum.map(crumbs, &{&1.type, &1.slug}) == [
             {:category, "reference"},
             {:category, "reference/components"},
             {:doc, "reference/components/body2d"}
           ]

    assert Content.doc_breadcrumbs(@collection, "nope") == []
  end

  test "the nearest category and the neighbours across categories" do
    assert %{category: "Manual", slug: "manual"} =
             Content.doc_category(@collection, "manual/scenes")

    assert Content.doc_category(@collection, "principles") == nil

    {prev, next} = Content.doc_neighbours(@collection, "manual/scenes")
    assert prev.slug == "manual/scripting"
    assert next.slug == "reference"
  end

  test "the flat categories view groups a tree by its top level" do
    categories = Content.list_doc_categories(@collection)

    assert Enum.map(categories, & &1.category) == [nil, "Manual", "Reference"]
    assert Enum.map(hd(categories).guides, & &1.slug) == ["principles", "intro"]
  end

  test "rendering rewrites neighbour links, drops the heading and offers a table of contents" do
    html = Content.doc_html(@collection, "manual/scenes")

    refute html =~ "<h1"
    assert html =~ ~s(href="/docs/manual/scripting#hot-reload")
    assert html =~ ~s(href="/docs/intro")

    assert Content.doc_toc(@collection, "manual/scenes") == [
             %{id: "nodes", text: "Nodes", level: 2},
             %{id: "kinds", text: "Kinds", level: 3}
           ]
  end

  test "a colour reaches the guides under it, and a subcategory with none keeps its parent's" do
    root = Path.join(System.tmp_dir!(), "gamend_tree_color_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(root) end)

    write(root, "10-outer/_category.md", "---\ncolor: text-sky-400\n---\n")
    write(root, "10-outer/index.md", "# Outer\n")
    write(root, "10-outer/page.md", "# Page\n")
    write(root, "10-outer/20-plain/deep.md", "# Deep\n")
    write(root, "10-outer/30-own/_category.md", "---\ncolor: text-rose-400\n---\n")
    write(root, "10-outer/30-own/leaf.md", "# Leaf\n")

    tree = Tree.scan(root)

    assert Tree.find_doc(tree, "outer").color == "text-sky-400"
    assert Tree.find_doc(tree, "outer/page").color == "text-sky-400"
    assert Tree.find_category(tree, "outer/plain").color == "text-sky-400"
    assert Tree.find_doc(tree, "outer/plain/deep").color == "text-sky-400"
    assert Tree.find_category(tree, "outer/own").color == "text-rose-400"
    assert Tree.find_doc(tree, "outer/own/leaf").color == "text-rose-400"
  end

  test "Tree.find_doc answers a category's index by the category slug" do
    tree = Content.doc_tree(@collection)

    assert Tree.find_doc(tree, "reference").index?
    assert Tree.find_doc(tree, "reference/components") == nil
    assert Tree.find_category(tree, "reference/components").title == "Components"
  end
end
