defmodule GamendWeb.BlogLayoutTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias GamendWeb.ContentPages

  @posts [
    {2026,
     [
       {9,
        [
          %{
            slug: "one",
            title: "One",
            date: ~D[2026-09-02],
            excerpt: "The first.",
            image: "/img/one.png",
            card_image: "/img/one.card.webp",
            reading_minutes: 3
          },
          %{
            slug: "two",
            title: "Two",
            date: ~D[2026-09-01],
            excerpt: "The second.",
            image: "/img/two.png",
            authors: [%{name: "Dragos", url: "https://github.com/Ughuuu"}]
          },
          %{slug: "three", title: "Three", date: ~D[2026-09-01], excerpt: "No picture."}
        ]}
     ]}
  ]

  describe "the index" do
    test "is a grid: cards in columns, each picture above its text" do
      html = render_index()

      assert html =~ "grid gap-5 sm:grid-cols-2 lg:grid-cols-3"

      # The picture is the card link's first child, the text after it.
      assert html =~ ~r/<a[^>]*class="flex h-full flex-col"[^>]*>\s*<img/
    end

    test "a card shows the post's card picture, else its picture, else none" do
      html = render_index()

      assert html =~ ~s(src="/img/one.card.webp")
      refute html =~ ~s(src="/img/one.png")
      assert html =~ ~s(src="/img/two.png")
      # The layout has pictures of its own; these are the cards'.
      assert length(Regex.scan(~r/<img[^>]*aspect-video/, html)) == 2
    end

    test "the newest post's picture is fetched first, the rest lazily" do
      html = render_index()

      assert [first] = Regex.run(~r/<img[^>]*one\.card\.webp[^>]*>/, html)
      assert first =~ ~s(loading="eager")
      assert first =~ ~s(fetchpriority="high")

      assert [second] = Regex.run(~r/<img[^>]*two\.png[^>]*>/, html)
      assert second =~ ~s(loading="lazy")
      refute second =~ "fetchpriority"
    end

    test "dates are localized in the browser, with the reading time beside them" do
      html = render_index()

      assert html =~ ~s(<time datetime="2026-09-02" data-local-time="calendar-date")
      assert html =~ ~s(<time datetime="2026-09" data-local-time="calendar-month")
      assert html =~ "3 min read"
    end

    # The card is a link; an author's link inside it would split it in two.
    test "a card holds no link but its own" do
      html = render_index()

      assert html =~ "Dragos"
      refute html =~ ~s(href="https://github.com/Ughuuu")
    end
  end

  describe "the post" do
    test "opens with the whole first paragraph when the body dropped it" do
      lede = String.duplicate("A long opening paragraph. ", 12)

      html =
        render_post(%{excerpt: String.slice(lede, 0, 200), lede: lede, lede_in_body?: true})

      assert html =~ String.trim(lede)
    end

    test "opens with the description when there is one" do
      html = render_post(%{excerpt: "The description.", lede: "Body text.", lede_in_body?: false})

      assert html =~ "The description."
      refute html =~ "Body text."
    end

    test "fetches the picture the body opens with first, and no later one" do
      body =
        ~s(<p><img loading="lazy" decoding="async" src="/a.png"></p><p>Text.</p>) <>
          ~s(<p><img loading="lazy" src="/b.png"></p>)

      html = render_post(%{}, body)

      assert html =~ ~s(<img loading="eager" fetchpriority="high" decoding="async" src="/a.png">)
      assert html =~ ~s(<img loading="lazy" src="/b.png">)
    end

    test "a cover is fetched first, and the body's pictures stay lazy" do
      html = render_post(%{image: "/img/cover.png"}, ~s(<p><img loading="lazy" src="/b.png"></p>))

      assert html =~ ~r/<img[^>]*src="\/img\/cover.png"[^>]*fetchpriority="high"/
      assert html =~ ~s(<img loading="lazy" src="/b.png">)
    end

    # The post's way back is the Back button every page has (2026-10-09),
    # not the old "Blog /" text crumb before the date.
    test "goes back to the blog with the Back button, not a text crumb" do
      html =
        render_component(&ContentPages.blog_post/1,
          flash: %{},
          post: %{slug: "two", title: "Two", date: ~D[2026-09-01], excerpt: "x", lede: ""},
          html: "<p>Body.</p>",
          prev: %{slug: "one", title: "One"},
          next: %{slug: "three", title: "Three"}
        )

      assert html =~ ~r{<a[^>]*href="/blog"[^>]*title="Back"}
      refute html =~ ~r{<a[^>]*href="/blog"[^>]*>\s*Blog\s*</a>}
      assert html =~ ~s(href="/blog/one")
      assert html =~ ~s(href="/blog/three")
    end
  end

  describe "eager_opening_image/1" do
    test "only the picture nothing but markup comes before" do
      assert ContentPages.eager_opening_image(~s(<figure><img src="/a.png"></figure>)) ==
               ~s(<figure><img loading="eager" fetchpriority="high" src="/a.png"></figure>)

      later = ~s(<p>First words.</p><p><img loading="lazy" src="/a.png"></p>)
      assert ContentPages.eager_opening_image(later) == later
      assert ContentPages.eager_opening_image("<p>No pictures.</p>") == "<p>No pictures.</p>"
      assert ContentPages.eager_opening_image(nil) == nil
    end
  end

  describe "cover/2" do
    test "a cover the body already shows is not shown again" do
      post = %{image: "/img/blog/cloth.png"}

      assert ContentPages.cover(post, ~s(<p>x</p><img src="/img/blog/cloth.webp?v=1" alt="">)) ==
               nil
    end

    test "a picture taken from the body is the body's, not a cover" do
      post = %{image: "/content/blog/2026/ship.png"}

      assert ContentPages.cover(post, ~s(<p><img src="/content/blog/2026/ship.png"></p>)) == nil
    end

    test "a cover the body does not show stays" do
      post = %{image: "/img/blog/cloth.png"}

      assert ContentPages.cover(post, ~s(<img src="/img/blog/jelly.webp">)) ==
               "/img/blog/cloth.png"

      assert ContentPages.cover(post, nil) == "/img/blog/cloth.png"
      assert ContentPages.cover(%{}, "<p>x</p>") == nil
    end
  end

  defp render_index do
    render_component(&ContentPages.blog_index/1,
      flash: %{},
      blog_available?: true,
      grouped_posts: @posts
    )
  end

  defp render_post(fields, html \\ "<p>Body.</p>") do
    post =
      Map.merge(
        %{slug: "one", title: "One", date: ~D[2026-09-02], excerpt: "The first.", lede: ""},
        fields
      )

    render_component(&ContentPages.blog_post/1, flash: %{}, post: post, html: html)
  end
end
