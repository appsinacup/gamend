defmodule GameServerHost.PagesSmokeTest do
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

  @endpoint GameServerWeb.Endpoint

  @pages [
    "/",
    "/blog",
    "/changelog",
    "/roadmap",
    "/privacy",
    "/terms",
    "/data_deletion",
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

  test "a post does not open by repeating its own lede" do
    for post <- GameServer.Content.list_blog_posts(),
        html = GameServer.Content.blog_post_html(post.slug),
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

  test "every blog post page renders, not just the index" do
    conn = get(build_conn(), "/blog")

    for [_, slug] <- Regex.scan(~r{href="/blog/([a-z0-9-]+)"}, html_response(conn, 200)),
        slug != "" do
      post = get(build_conn(), "/blog/#{slug}")
      assert post.status == 200, "/blog/#{slug} returned #{post.status}"
    end
  end
end
