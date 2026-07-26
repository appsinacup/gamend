defmodule GameServerHost.SitemapController do
  @moduledoc """
  Host-owned `sitemap.xml` controller.

  Edit `@static_pages` here to advertise host-specific public pages such as
  custom docs, landing pages, or host-only routes.
  """

  use GameServerWeb, :controller

  alias GameServer.Content

  @static_pages [
    %{loc: "/", changefreq: "weekly", priority: "1.0"},
    %{loc: "/blog", changefreq: "weekly", priority: "0.8"},
    %{loc: "/changelog", changefreq: "weekly", priority: "0.6"},
    %{loc: "/roadmap", changefreq: "monthly", priority: "0.5"},
    %{loc: "/docs/setup", changefreq: "monthly", priority: "0.7"},
    %{loc: "/privacy", changefreq: "yearly", priority: "0.3"},
    %{loc: "/terms", changefreq: "yearly", priority: "0.3"},
    %{loc: "/data_deletion", changefreq: "yearly", priority: "0.3"},
    %{loc: "/users/register", changefreq: "yearly", priority: "0.5"},
    %{loc: "/users/log_in", changefreq: "yearly", priority: "0.5"}
  ]

  def index(conn, _params) do
    base_url = GameServerWeb.endpoint().url()
    blog_posts = Content.list_blog_posts()

    urls =
      Enum.map(@static_pages, fn page ->
        url_entry(base_url, page.loc, nil, page.changefreq, page.priority)
      end) ++
        Enum.map(blog_posts, fn post ->
          lastmod = Date.to_iso8601(post.date)
          url_entry(base_url, "/blog/#{post.slug}", lastmod, "monthly", "0.7")
        end)

    xml = """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    #{Enum.join(urls, "\n")}
    </urlset>
    """

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, xml)
  end

  defp url_entry(base_url, loc, lastmod, changefreq, priority) do
    lastmod_tag = if lastmod, do: "    <lastmod>#{lastmod}</lastmod>\n", else: ""

    """
      <url>
        <loc>#{base_url}#{loc}</loc>
    #{lastmod_tag}    <changefreq>#{changefreq}</changefreq>
        <priority>#{priority}</priority>
      </url>
    """
  end
end
