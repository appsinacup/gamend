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

  test "the truncate marker decides the excerpt, and the page still opens with the lede once" do
    post = Content.get_blog_post("truncated")

    assert post.excerpt == "Above the marker."
    assert post.lede == "Above the marker."
    # The page shows the lede above the body; keeping it in the body as
    # well printed the opening paragraph twice.
    assert post.lede_in_body?

    html = Content.blog_post_html("truncated")
    refute html =~ "Above the marker."
    assert html =~ "<p>Below.</p>"
    refute html =~ "truncate"
  end

  test "a post with neither has the classic shape: heading title, first paragraph as lede, body without it" do
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

  describe "a post's picture" do
    setup %{root: root} do
      File.write!(Path.join(root, "2026-09-03-shown.md"), """
      # Shown

      Opening paragraph.

      ![A ship](2026-sep/ship.png)

      ![A map](2026-sep/map.png)
      """)

      File.write!(Path.join(root, "2026-09-04-relative-cover.md"), """
      ---
      image: covers/hello.png
      ---
      # Relative cover

      Text.
      """)

      Content.reload()
      :ok
    end

    test "is the frontmatter image, as written" do
      post = Content.get_blog_post("hello")

      assert post.image == "/img/blog/hello.png"
      assert post.card_image == "/img/blog/hello.png"
    end

    test "is else the body's first picture, where the body serves it" do
      post = Content.get_blog_post("shown")

      assert post.image == "/content/blog/2026-sep/ship.png"
      assert Content.blog_post_html("shown") =~ ~s(src="/content/blog/2026-sep/ship.png")
    end

    test "is nil for a post with none" do
      post = Content.get_blog_post("classic")

      assert post.image == nil
      assert post.card_image == nil
    end

    test "a relative frontmatter image resolves like the body's" do
      assert Content.get_blog_post("relative-cover").image == "/content/blog/covers/hello.png"
    end

    test "goes through the blog's image_url: :card on the index, :page in the body", %{
      root: root
    } do
      Content.register_path(:blog,
        kind: :dir,
        path: root,
        image_url: {__MODULE__, :smaller},
        post_render: {__MODULE__, :stamp}
      )

      on_exit(fn -> Content.unregister_path(:blog) end)

      post = Content.get_blog_post("shown")
      assert post.image == "/content/blog/2026-sep/ship.png"
      assert post.card_image == "/content/blog/card/2026-sep/ship.webp"

      html = Content.blog_post_html("shown")
      assert html =~ ~s(src="/content/blog/page/2026-sep/ship.webp")
      assert html =~ ~s(src="/content/blog/page/2026-sep/map.webp")
      assert html =~ "<!-- stamped -->"

      assert Content.image_url(:blog, post.image, :page) ==
               "/content/blog/page/2026-sep/ship.webp"

      assert Content.image_url(:blog, "https://example.com/x.png", :card) ==
               "https://example.com/x.png"

      assert Content.image_url(:changelog, "/content/changelog/x.png", :page) ==
               "/content/changelog/x.png"
    end

    test "image_url is rejected unless it is a {module, function}", %{root: root} do
      assert_raise ArgumentError, fn ->
        Content.register_path(:bad_images, kind: :dir, path: root, image_url: :nope)
      end
    end
  end

  # A host's prebuilt copies: `/content/blog/x.png` -> `/content/blog/<use>/x.webp`,
  # and anything it has no copy of as it is.
  def smaller("/content/blog/" <> rest, use),
    do: "/content/blog/#{use}/#{Path.rootname(rest)}.webp"

  def smaller(url, _use), do: url

  def stamp(html), do: html <> "<!-- stamped -->"
end
