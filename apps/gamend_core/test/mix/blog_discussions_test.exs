defmodule Mix.Tasks.Gamend.Blog.DiscussionsTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Gamend.Blog.Discussions

  @config %{
    repo: "owner/name",
    site: "https://example.org",
    category: "Announcements",
    tagline: nil
  }

  defp post(slug, date), do: %{slug: slug, title: slug, date: date, path: "/nowhere/#{slug}.md"}

  test "a post a discussion links to is posted, and the rest come oldest first" do
    posts = [
      post("newer", ~D[2026-02-01]),
      post("posted", ~D[2026-01-15]),
      post("older", ~D[2026-01-01])
    ]

    bodies = ["Read more here: https://example.org/blog/posted/"]

    assert Enum.map(Discussions.unposted(@config, posts, bodies), & &1.slug) == ["older", "newer"]
  end

  test "the body drops the frontmatter, the heading and the truncate marker, and links back" do
    markdown = """
    ---
    title: "Saves"
    ---
    # Saves

    Opening line.

    <!-- truncate -->

    More.
    """

    body = Discussions.body(@config, %{post("saves", ~D[2026-01-01]) | title: "Saves"}, markdown)

    assert body ==
             "Opening line.\n\nMore.\n\n---\n\nRead it on the site: https://example.org/blog/saves\n"
  end

  test "hard-wrapped prose joins, while lists, code and tables keep their lines" do
    markdown = """
    One sentence
    across two lines.

    - an item
      that wraps
    - another

    ```
    keep
    these
    ```

    | a |
    | - |
    """

    body = Discussions.body(@config, post("p", ~D[2026-01-01]), markdown)

    assert body =~ "One sentence across two lines.\n"
    assert body =~ "- an item that wraps\n- another\n"
    assert body =~ "```\nkeep\nthese\n```"
    assert body =~ "| a |\n| - |"
  end

  test "root links, relative pictures and clips become absolute" do
    markdown = """
    See [the docs](/docs/x) and ![shot](race/lint.png).

    <figure class="clip"><video controls poster="/img/p.webp" aria-label="A clip"><source src="/video/c.webm" type="video/webm"><source src="/video/c.mp4" type="video/mp4"></video></figure>
    """

    body = Discussions.body(@config, post("p", ~D[2026-01-01]), markdown)

    assert body =~ "[the docs](https://example.org/docs/x)"
    assert body =~ "![shot](https://example.org/content/blog/race/lint.png)"
    assert body =~ "[![A clip](https://example.org/img/p.webp)](https://example.org/video/c.mp4)"
    refute body =~ "<video"
  end

  test "a tagline closes the body when the host sets one" do
    body = Discussions.body(%{@config | tagline: "Tag."}, post("p", ~D[2026-01-01]), "Hi.\n")

    assert String.ends_with?(body, "blog/p\n\nTag.\n")
  end
end
