defmodule GamendHost.PagesSmokeTest do
  @moduledoc """
  Every public page the host serves must at least render.

  The web app's own suite covers the reusable LiveViews, but the host-owned
  pages — blog, changelog, roadmap, the markdown-driven docs — only exist
  here, which is how a `%Date{}` crash on /blog shipped without a red test.
  This is deliberately shallow: load the page, expect a 200 (or a redirect),
  assert nothing blew up.
  """

  use ExUnit.Case, async: false

  import Phoenix.ConnTest

  @endpoint GamendWeb.Endpoint

  @pages [
    "/",
    "/blog",
    "/changelog",
    "/roadmap",
    "/privacy",
    "/terms",
    "/data_deletion",
    "/docs/setup",
    "/quests",
    "/leaderboards",
    "/tournaments",
    "/groups",
    "/users/log_in",
    "/users/register"
  ]

  for path <- @pages do
    test "GET #{path} renders" do
      conn = get(build_conn(), unquote(path))

      assert conn.status in [200, 302],
             "#{unquote(path)} returned #{conn.status}"

      if conn.status == 200 do
        body = html_response(conn, 200)
        refute body =~ "MatchError", unquote(path)
        refute body =~ "FunctionClauseError", unquote(path)
      end
    end
  end

  # A 200 is not enough for these two: `GamendWeb.ContentPages` renders an
  # empty state when the markdown is missing, so a broken content-path
  # registration or a renamed assign would still pass the smoke test above
  # while serving "Add a changelog file at CHANGELOG.md to display it here."
  test "the changelog and roadmap render their file, not the empty state" do
    for {path, file} <- [{"/changelog", "CHANGELOG.md"}, {"/roadmap", "ROADMAP.md"}] do
      body = html_response(get(build_conn(), path), 200)

      # `markdown-content` only renders when there is markdown, so this is the
      # real assertion; the refute names the failure if it ever does not hold.
      assert body =~ "markdown-content", "#{path} rendered no article"
      refute body =~ "to display it here", "#{path} fell back to the empty state"

      # And it is *this* host's file, read from disk rather than a phrase
      # copied into the test that goes stale the next time someone edits it.
      assert body =~ first_bold(file), "#{path} did not render #{file}"
    end
  end

  # The first `**bold**` run in a markdown file that survives rendering
  # verbatim — every entry in both of ours opens with one, and plain text
  # inside a <strong> reaches the HTML unchanged. Runs carrying their own
  # markup do not: a bold `code` span renders as <code> without the backticks,
  # and anything with &, < or > comes back HTML-escaped, so those are skipped
  # rather than compared against a string the page never contains.
  defp first_bold(file) do
    ~r/\*\*(.+?)\*\*/
    |> Regex.scan(File.read!(file))
    |> Enum.map(fn [_, text] -> text end)
    |> Enum.find(&(not Regex.match?(~r/[`<>&\[\]*_"']/, &1)))
  end

  test "each of the two links across to the other" do
    assert html_response(get(build_conn(), "/changelog"), 200) =~ ~s(href="/roadmap")
    assert html_response(get(build_conn(), "/roadmap"), 200) =~ ~s(href="/changelog")
  end

  test "a post does not open by repeating its own lede" do
    for post <- Gamend.Content.list_blog_posts(),
        html = Gamend.Content.blog_post_html(post.slug),
        is_binary(html) and is_binary(post.excerpt) and post.excerpt != "" do
      # The show page renders the excerpt above the body already.
      first_paragraph =
        case Regex.run(~r/\A\s*<p>(.*?)<\/p>/s, html) do
          [_, text] -> text |> String.replace(~r/<[^>]+>/, "") |> String.replace(~r/\s+/, " ")
          _ -> nil
        end

      excerpt = post.excerpt |> String.replace(~r/\s+/, " ") |> String.trim()

      refute first_paragraph == excerpt,
             "#{post.slug} body starts with its excerpt — the page shows it twice"
    end
  end

  test "every guide has its own page, reachable from the index" do
    index = html_response(get(build_conn(), "/docs/setup"), 200)

    for guide <- Gamend.Content.list_docs() do
      assert index =~ ~s(href="/docs/#{guide.slug}"),
             "/docs/setup does not link to #{guide.slug}"

      page = get(build_conn(), "/docs/#{guide.slug}")
      assert page.status == 200, "/docs/#{guide.slug} returned #{page.status}"
    end
  end

  # The whole point of a page per guide: its own <title> and description, not
  # the site-wide boilerplate every guide shared when they were one page.
  test "a guide page carries its own title and description" do
    guide = hd(Gamend.Content.list_docs())
    body = html_response(get(build_conn(), "/docs/#{guide.slug}"), 200)

    assert body =~ guide.title
    assert body =~ ~s(<meta name="description")
    assert body =~ ~s("@type":"TechArticle") or body =~ ~s("@type": "TechArticle")

    refute GamendHost.PageMeta.describe("/docs/#{guide.slug}") == nil,
           "#{guide.slug} has no meta description"
  end

  # The real guides, through the real router: `/docs/:slug` would answer this
  # path if the route were listed after it, and two guides sharing a heading
  # would leave a `#section` link landing in the wrong one.
  test "the guides download as one page, every guide in it" do
    conn = get(build_conn(), "/docs/download")
    body = response(conn, 200)

    assert [disposition] = Plug.Conn.get_resp_header(conn, "content-disposition")
    assert disposition =~ "attachment"

    for guide <- Gamend.Content.list_docs() do
      assert body =~ ~s(<article id="doc-#{guide.slug}">), "#{guide.slug} is not in the file"
    end

    ids =
      ~r/<[a-zA-Z][^<>]*\sid="([^"]*)"/
      |> Regex.scan(body, capture: :all_but_first)
      |> List.flatten()

    assert ids == Enum.uniq(ids)
  end

  # Any other class renders and is simply absent from a stylesheet that never
  # scanned these files, which is how gamend.org lost every category's colour.
  test "every guide category names a color from the shared palette" do
    for path <- Path.wildcard("priv/docs/*/_category.md") do
      color = path |> File.read!() |> Gamend.Content.frontmatter() |> Map.get("color")

      assert color in GamendWeb.DocsLive.category_colors(), "#{path} names #{inspect(color)}"
    end
  end

  test "the guides' index offers the download" do
    assert html_response(get(build_conn(), "/docs/setup"), 200) =~ ~s(href="/docs/download")
  end

  test "an unknown guide is a 404, not a blank page" do
    assert_error_sent 404, fn -> get(build_conn(), "/docs/no-such-guide") end
  end

  # `?guide=` was how the single-page version deep-linked a section; those
  # links are still in the wild.
  test "a legacy ?guide= link moves to the guide's own URL" do
    guide = hd(Gamend.Content.list_docs())
    conn = get(build_conn(), "/docs/setup?guide=#{guide.slug}")

    assert conn.status == 302
    assert redirected_to(conn) == "/docs/#{guide.slug}"
  end

  test "every blog post page renders, not just the index" do
    conn = get(build_conn(), "/blog")

    for [_, slug] <- Regex.scan(~r{href="/blog/([a-z0-9-]+)"}, html_response(conn, 200)),
        slug != "" do
      post = get(build_conn(), "/blog/#{slug}")
      assert post.status == 200, "/blog/#{slug} returned #{post.status}"
    end
  end
end
