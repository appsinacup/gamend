defmodule Gamend.Content.MarkdownTest do
  use ExUnit.Case, async: true

  alias Gamend.Content.Markdown

  defp render!(md, opts \\ []) do
    {:ok, html} = Markdown.render(md, opts)
    html
  end

  describe "headings" do
    test "carry ids and the frontmatter is not rendered" do
      html = render!("---\ntitle: x\n---\n## Getting started\n\n### First run\n")

      assert html =~ ~s(<h2 id="getting-started">)
      assert html =~ ~s(<h3 id="first-run">)
      refute html =~ "title: x"
    end

    test "make a table of contents of h2 and h3 only" do
      html = render!("# Title\n\n## One `code`\n\n### Two\n\n#### Four\n\n## Three\n")

      assert Markdown.toc(html) == [
               %{id: "one-code", text: "One code", level: 2},
               %{id: "two", text: "Two", level: 3},
               %{id: "three", text: "Three", level: 2}
             ]
    end

    test "strip_first_h1 tolerates the id the heading now carries" do
      assert Markdown.strip_first_h1(
               ~s(<h1 id="t">T<a href="#t" class="anchor"></a></h1>\n<p>x</p>)
             ) ==
               "<p>x</p>"

      assert Markdown.strip_first_h1("<p>no heading</p>") == "<p>no heading</p>"
    end
  end

  describe "admonitions" do
    test "a titled directive keeps its title" do
      html = render!(":::tip[For animators]\nInside **bold**.\n:::\n")

      assert html =~
               ~r{<div class="admonition admonition-tip">\s*<p class="admonition-title">For animators</p>}

      assert html =~ "<strong>bold</strong>"
      refute html =~ "tip[For"
    end

    test "an untitled directive is titled by its kind" do
      html = render!(":::warning\nCareful.\n:::\n")

      assert html =~
               ~r{<div class="admonition admonition-warning">\s*<p class="admonition-title">Warning</p>}
    end

    test "a GitHub alert renders as the same markup" do
      html = render!("> [!NOTE]\n> Body.\n")

      assert html =~
               ~r{<div class="admonition admonition-note">\s*<p class="admonition-title">Note</p>}

      refute html =~ "markdown-alert"
    end

    test "a raw div named like an admonition is HTML and stays as written" do
      html = render!(~s{<div class="note">plain</div>\n})

      assert html =~ ~s(<div class="note">plain</div>)
      refute html =~ "admonition"
    end

    test "a directive of another kind is not an admonition" do
      assert render!(":::columns\nx\n:::\n") =~ ~s(<div class="columns">)
    end

    test "a link inside an admonition is rewritten like any other" do
      html = render!(":::tip\n[a](./b.md)\n:::\n", base_path: "/docs", slug: "m/x")

      assert html =~ ~s(href="/docs/m/b")
    end
  end

  describe "mermaid" do
    test "a fence becomes the hook's element with the source intact" do
      html = render!("Before\n\n```mermaid\ngraph TD; A-->B\n```\n\nAfter\n", id: "doc-x")

      assert html =~
               ~s(<div id="doc-x-mermaid-0" class="mermaid-diagram" phx-hook="MermaidDiagram" phx-update="ignore" data-diagram="graph TD; A--&gt;B"></div>)

      refute html =~ "language-mermaid"
      assert html =~ "<p>Before</p>"
      assert html =~ "<p>After</p>"
    end

    test "several fences keep document order" do
      html = render!("```mermaid\nfirst\n```\n\ntext\n\n```mermaid\nsecond\n```\n", id: "d")

      assert [[_, "d-mermaid-0", "first"], [_, "d-mermaid-1", "second"]] =
               Regex.scan(~r/id="([^"]+)"[^>]*data-diagram="([^"]+)"/, html)
    end

    test "a fence inside a list item is still a diagram" do
      html = render!("- item\n\n  ```mermaid\n  graph TD\n  ```\n", id: "d")

      assert html =~ ~r{<li>.*<div id="d-mermaid-0" class="mermaid-diagram".*</li>}s
      refute html =~ "language-mermaid"
    end

    test "other fences are still highlighted" do
      html = render!("```toml\n[package]\nname = \"x\"\n```\n")

      assert html =~ ~s(class="language-toml")
      assert html =~ "l-line"
    end
  end

  describe "raw HTML" do
    test "a figure with a video and an inline svg icon survive the sanitiser" do
      html =
        render!("""
        <figure class="clip"><video controls muted loop playsinline preload="none" poster="/img/poster/a.webp"><source src="/video/a.webm" type="video/webm"></video><figcaption>Cap</figcaption></figure>

        <span class="ref-icon" aria-hidden="true"><svg viewBox="0 0 8 8"><path d="M0 0h8" fill="currentColor"/></svg></span> `body2d`
        """)

      assert html =~ ~s(<figure class="clip">)
      assert html =~ ~s(poster="/img/poster/a.webp")
      assert html =~ ~s(<source src="/video/a.webm" type="video/webm">)
      assert html =~ ~s(<svg viewBox="0 0 8 8"><path d="M0 0h8" fill="currentColor"></path></svg>)
    end

    test "scripts and handlers do not" do
      html = render!(~s{<script>alert(1)</script>\n\n<div onclick="x()" class="a">ok</div>\n})

      refute html =~ "<script"
      refute html =~ "onclick"
      assert html =~ ~s(<div class="a">ok</div>)
    end
  end

  describe "links" do
    test "a relative .md link resolves against the document's slug" do
      opts = [base_path: "/docs", slug: "manual/scenes"]

      html =
        render!(
          "[a](./scripting.md#debugging) [b](../principles.mdx) [c](../reference/index.md) [d](sub/20-thing.md)",
          opts
        )

      assert html =~ ~s(href="/docs/manual/scripting#debugging")
      assert html =~ ~s(href="/docs/principles")
      assert html =~ ~s(href="/docs/reference")
      assert html =~ ~s(href="/docs/manual/sub/thing")
    end

    test "an index page's links resolve against its own folder, not its parent" do
      html =
        render!(
          "[a](builds.md) [b](signing/10-macos.md#notary) [c](../principles.md)",
          base_path: "/docs",
          slug: "forge",
          index: true
        )

      assert html =~ ~s(href="/docs/forge/builds")
      assert html =~ ~s(href="/docs/forge/signing/macos#notary")
      assert html =~ ~s(href="/docs/principles")
    end

    test "render_file/2 knows an index.md from its name" do
      dir = Path.join(System.tmp_dir!(), "gs-md-index-#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)

      index = Path.join(dir, "index.md")
      page = Path.join(dir, "20-page.md")
      File.write!(index, "[a](builds.md)")
      File.write!(page, "[a](builds.md)")

      assert Markdown.render_file(index, base_path: "/docs", slug: "forge") =~
               ~s(href="/docs/forge/builds")

      assert Markdown.render_file(page, base_path: "/docs", slug: "forge/page") =~
               ~s(href="/docs/forge/builds")
    end

    test "absolute and external links are left alone, as is everything without a base path" do
      html = render!("[a](/docs/x) [b](https://e.com/a.md) [c](./y.md)", base_path: "/docs")

      assert html =~ ~s(href="/docs/x")
      assert html =~ ~s(href="https://e.com/a.md")
      assert html =~ ~s(href="/docs/y")

      assert render!("[c](./y.md)") =~ ~s(href="./y.md")
    end
  end

  describe "images" do
    test "content mode routes every image through the collection's asset path" do
      html = render!("![a](gamend/auth.png) ![b](/blog/gamend/x.png)", collection: "blog")

      assert html =~ ~s(src="/content/blog/gamend/auth.png")
      assert html =~ ~s(src="/content/blog/gamend/x.png")
      assert html =~ ~s(loading="lazy")
    end

    test "static mode leaves a root-absolute path alone and resolves a relative one against the file" do
      html =
        render!("![a](/img/manual/x.webp) ![b](../shots/y.png)",
          collection: "docs",
          assets: :static,
          dir: "10-manual"
        )

      assert html =~ ~s(src="/img/manual/x.webp")
      assert html =~ ~s(src="/content/docs/shots/y.png")
    end
  end

  test "gdscript fences borrow the javascript grammar" do
    assert render!("```gdscript\nvar x = 1\n```\n") =~ ~s(class="language-javascript")
  end

  test "footnotes render" do
    html = render!("Text[^1].\n\n[^1]: The note.\n")

    assert html =~ "footnote"
  end
end
