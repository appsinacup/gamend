defmodule Gamend.Content.OfflineTest do
  @moduledoc """
  A collection as one file: guides that were written as separate pages have
  to keep working on a single one, with no server behind it.
  """
  use ExUnit.Case, async: false

  alias Gamend.Content
  alias Gamend.Content.Offline

  @flat :offline_test_flat
  @tree :offline_test_tree
  @empty :offline_test_empty
  @show_hidden {__MODULE__, :show_hidden}

  @opts [
    title: "Setup & Guides",
    index_path: "/docs/setup",
    item_path: "/docs",
    origin: "https://game.example"
  ]

  @one """
  # One

  Intro.

  ## Overview

  [Two](/docs/two), [its setup](/docs/two#setup), [here](#overview),
  [the index](/docs/setup), [admin](/admin/config), [gone](/docs/gone),
  [out](https://example.com/x).

  ![Chart](images/chart.svg)

  ![Missing](images/missing.png)

  ```html
  <div id="sample" href="/docs/two"></div>
  ```

  ```mermaid
  flowchart LR
    A --> B
  ```
  """

  @doc false
  def visible?(%{meta: %{"feature" => "hidden"}}), do: :persistent_term.get(@show_hidden, false)
  def visible?(_doc), do: true

  setup do
    root = Path.join(System.tmp_dir!(), "gamend_offline_#{System.unique_integer([:positive])}")

    write(root, "10-start/10-one.md", @one)
    write(root, "10-start/20-two.md", "# Two\n\n## Overview\n\n## Setup\n")
    write(root, "10-start/30-three.md", "---\nfeature: hidden\n---\n# Three\n\nSecret.\n")
    write(root, "images/chart.svg", "<svg></svg>")
    File.mkdir_p!(Path.join(root, "empty"))

    for {name, nesting} <- [{@flat, :flat}, {@tree, :tree}] do
      Content.register_path(name,
        kind: :dir,
        path: root,
        nesting: nesting,
        visible: {__MODULE__, :visible?}
      )
    end

    Content.register_path(@empty, kind: :dir, path: Path.join(root, "empty"))

    on_exit(fn ->
      Enum.each([@flat, @tree, @empty], &Content.unregister_path/1)
      :persistent_term.erase(@show_hidden)
      File.rm_rf!(root)
    end)

    %{html: Offline.html(@flat, @opts)}
  end

  test "is every guide in reading order, under a contents list", %{html: html} do
    assert html =~ "<!doctype html>"
    assert html =~ "<title>Setup &amp; Guides</title>"
    assert html =~ ~s(<a href="#doc-one">One</a>)
    assert html =~ ~s(<a href="#doc-two">Two</a>)

    {one, _length} = :binary.match(html, ~s(<article id="doc-one">))
    {two, _length} = :binary.match(html, ~s(<article id="doc-two">))
    assert one < two
  end

  test "headings the guides share stay apart", %{html: html} do
    assert html =~ ~s(id="doc-one--overview")
    assert html =~ ~s(id="doc-two--overview")
  end

  test "a link to a guide stays in the file", %{html: html} do
    assert html =~ ~s(href="#doc-two")
    assert html =~ ~s(href="#doc-two--setup")
    assert html =~ ~s(href="#doc-one--overview")
    assert html =~ ~s(href="#contents")
  end

  test "any other link to the site goes to the site", %{html: html} do
    assert html =~ ~s(href="https://game.example/admin/config")
    assert html =~ ~s(href="https://game.example/docs/gone")
    assert html =~ ~s(href="https://example.com/x")
    refute html =~ ~r/\shref="\/[^\/]/
  end

  test "an image is in the file, and one that cannot be read links out", %{html: html} do
    assert html =~ "data:image/svg+xml;base64,#{Base.encode64("<svg></svg>")}"
    assert html =~ ~s(src="https://game.example/content/offline_test_flat/)
    refute html =~ ~r/\ssrc="\/[^\/]/
  end

  test "markup shown as code is left as written", %{html: html} do
    refute html =~ "doc-one--sample"
    refute html =~ ~s(#doc-two" ></div>)
  end

  test "a diagram stays readable as its source", %{html: html} do
    refute html =~ "data-diagram"
    assert html =~ ~r/<pre><code>flowchart LR\s+A --&gt; B<\/code><\/pre>/
  end

  test "a guide hidden on the site is hidden here, at once", %{html: html} do
    refute html =~ "Secret."

    :persistent_term.put(@show_hidden, true)
    assert Offline.html(@flat, @opts) =~ "Secret."

    :persistent_term.put(@show_hidden, false)
    refute Offline.html(@flat, @opts) =~ "Secret."
  end

  test "a tree collection nests its contents and keeps slugs whole" do
    html = Offline.html(@tree, @opts)

    assert html =~ ~s(<span class="category">Start</span><ul>)
    assert html =~ ~s(<article id="doc-start/one">)
    assert html =~ ~s(id="doc-start/one--overview")
  end

  test "a collection with no guides has no file" do
    assert Offline.html(@empty, @opts) == nil
  end

  defp write(root, relative, content) do
    path = Path.join(root, relative)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, content)
  end
end
