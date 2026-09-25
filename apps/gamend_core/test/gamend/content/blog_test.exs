defmodule Gamend.Content.BlogTest do
  @moduledoc """
  Posts with frontmatter, authors, covers and the truncate marker — and the
  old shape, a heading and a dated filename, which still works.
  """
  use ExUnit.Case, async: false

  alias Gamend.Content

  setup do
    root = Path.join(System.tmp_dir!(), "gamend_blog_#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "_authors"))

    File.write!(
      Path.join(root, "_authors/dragos.md"),
      "---\nname: Dragos\ntitle: Balaur\nurl: https://github.com/Ughuuu\n---\n"
    )

    File.write!(Path.join(root, "2026-08-02-hello-balaur.md"), """
    ---
    title: Hello, Balaur
    slug: hello
    description: The first post.
    authors: [dragos, someone]
    image: /img/blog/hello.png
    keywords: [engine, release]
    ---

    import Clip from '@site/src/components/Clip';

    Opening paragraph that is not the description.

    <!-- truncate -->

    The rest, with #{String.duplicate("word ", 450)}
    """)

    File.write!(Path.join(root, "2026-08-10-classic.md"), """
    # A classic post

    The opening paragraph is the lede.

    Second paragraph.
    """)

    File.write!(Path.join(root, "2026-09-01-truncated.md"), """
    # Truncated

    Above the marker.

    <!-- truncate -->

    Below.
    """)

    File.write!(
      Path.join(root, "_drafts/2030-01-01-draft.md") |> tap(&File.mkdir_p!(Path.dirname(&1))),
      "# Draft\n"
    )

    original = Application.get_env(:gamend_core, Gamend.Content, [])

    Application.put_env(
      :gamend_core,
      Gamend.Content,
      Keyword.put(original, :blog_candidates, [root])
    )

    Content.reload()

    on_exit(fn ->
      Application.put_env(:gamend_core, Gamend.Content, original)
      Content.reload()
      File.rm_rf(root)
    end)

    {:ok, root: root}
  end

  test "posts are newest first and underscored folders are not posts" do
    assert Enum.map(Content.list_blog_posts(), & &1.slug) == ["truncated", "classic", "hello"]
  end

  test "frontmatter names the post" do
    post = Content.get_blog_post("hello")

    assert post.title == "Hello, Balaur"
    assert post.date == ~D[2026-08-02]
    assert post.description == "The first post."
    assert post.excerpt == "The first post."
    assert post.image == "/img/blog/hello.png"
    assert post.keywords == ["engine", "release"]
    assert post.reading_minutes == 3
    refute post.lede_in_body?
  end

  test "authors resolve from _authors, and an unknown key is still a name" do
    assert [dragos, someone] = Content.get_blog_post("hello").authors

    assert dragos == %{
             key: "dragos",
             name: "Dragos",
             title: "Balaur",
             url: "https://github.com/Ughuuu",
             image: nil
           }

    assert someone.name == "someone"
  end

  test "the truncate marker decides the excerpt when there is no description" do
    post = Content.get_blog_post("truncated")

    assert post.excerpt == "Above the marker."
    refute post.lede_in_body?

    html = Content.blog_post_html("truncated")
    assert html =~ "<p>Above the marker.</p>"
    assert html =~ "<p>Below.</p>"
    refute html =~ "truncate"
  end

  test "a post with neither keeps the old shape: heading title, first paragraph as lede, body without it" do
    post = Content.get_blog_post("classic")

    assert post.title == "A classic post"
    assert post.lede == "The opening paragraph is the lede."
    assert post.lede_in_body?
    assert post.authors == []

    html = Content.blog_post_html("classic")
    refute html =~ "<h1"
    refute html =~ "The opening paragraph"
    assert html =~ "<p>Second paragraph.</p>"
  end

  test "a post that opens with an image still drops its lede from the body", %{root: root} do
    File.write!(Path.join(root, "2026-09-02-pictured.md"), """
    # Pictured

    ![A new flag](/img/blog/flag.png)

    The opening paragraph, under a picture.

    Second paragraph.
    """)

    Content.reload()

    assert Content.get_blog_post("pictured").lede == "The opening paragraph, under a picture."

    html = Content.blog_post_html("pictured")
    assert html =~ "flag.png"
    refute html =~ "The opening paragraph"
    assert html =~ "Second paragraph."
  end

  test "the lede skips an import line left over from MDX" do
    assert Content.get_blog_post("hello").lede == "Opening paragraph that is not the description."
  end
end
