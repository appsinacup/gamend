defmodule GamendHost.SearchTest do
  @moduledoc """
  What the search palette offers, and whether those places exist.

  Every row is a promise that a URL leads somewhere, and the catalogue is
  built from three enumerations that this code does not own — the theme's
  navigation and two `Gamend.Content` collections. Any of them can gain a
  shape spelled differently from what is assumed here, and the symptom would
  be a 404 from a search result, which nobody reports as a search bug.

  So the route check is the point: every href is resolved through the real
  router, and a match against the catch-all page fallback counts as a miss,
  because that fallback matches every path ever written.
  """

  use ExUnit.Case, async: true

  alias GamendHost.Search
  alias GamendWeb.SearchIndex

  @context %{scope: nil, locale: "en"}

  defp entries, do: Search.entries(@context)

  defp hrefs, do: Enum.map(entries(), & &1.href)

  defp group(entries, name), do: Enum.filter(entries, &(&1[:group] == name))

  # `route_info/4` answers for the catch-all too, and that fallback matches
  # every path ever written — so a hit on it only counts when the theme really
  # declares that page.
  defp resolves?("/" <> _ = href) do
    path = href |> String.split(["?", "#"]) |> hd()

    case Phoenix.Router.route_info(GamendHost.Router, "GET", path, "") do
      %{plug: GamendWeb.PageController, plug_opts: :configured_page} -> configured_page?(path)
      %{} -> true
      :error -> false
    end
  end

  # An off-site nav link is the theme's business, not the router's.
  defp resolves?(_href), do: true

  defp configured_page?("/" <> slug) do
    GamendWeb.HostLayouts.resolve_theme("en")
    |> Map.get("pages", %{})
    |> Map.has_key?(slug)
  end

  defp configured_page?(_path), do: false

  describe "the catalogue" do
    test "every destination leads to a page that exists" do
      broken =
        entries()
        |> Enum.reject(&resolves?(&1.href))
        |> Enum.map(& &1.href)

      assert broken == []
    end

    test "nothing is offered twice" do
      assert hrefs() == Enum.uniq(hrefs())
    end

    test "every row says something" do
      assert Enum.all?(entries(), &(is_binary(&1.title) and String.trim(&1.title) != ""))
    end
  end

  describe "what is in it" do
    setup do
      %{entries: entries()}
    end

    test "the navigation", %{entries: entries} do
      hrefs = Enum.map(entries, & &1.href)

      assert "/play" in hrefs
      assert "/leaderboards" in hrefs
      assert "/blog" in hrefs
    end

    test "every guide, under one heading", %{entries: entries} do
      guides = entries |> group("Documentation") |> Enum.reject(&String.contains?(&1.href, "#"))

      assert length(guides) == length(Gamend.Content.list_docs())
      assert Enum.any?(guides, &(&1.href == "/docs/theme"))
    end

    test "every section of a guide, linking to its heading", %{entries: entries} do
      usernames = Enum.find(entries, &(&1.href == "/docs/authentication#usernames"))

      assert usernames.title == "Usernames"
      assert usernames.group == "Documentation"
      assert String.starts_with?(usernames.subtitle, "Authentication · ")
    end

    # The anchor is only worth linking if the rendered guide has that id.
    test "every section anchor exists in its guide", %{entries: entries} do
      missing =
        for %{href: "/docs/" <> rest} <- entries,
            [slug, id] <- [String.split(rest, "#", parts: 2)],
            not String.contains?(Gamend.Content.doc_html(slug), ~s(id="#{id}")),
            do: rest

      assert missing == []
    end

    # A word only the body of a section holds, found through the section's
    # opening sentence.
    test "a section is found by the words it opens with", %{entries: entries} do
      assert Enum.any?(entries, &(&1[:subtitle] && &1.subtitle =~ "utf8"))
    end

    test "sections come after the pages, so a guide stays above its own sections",
         %{entries: entries} do
      hrefs = Enum.map(entries, & &1.href)
      first_section = Enum.find_index(hrefs, &String.contains?(&1, "#"))
      last_page = hrefs |> Enum.reject(&String.contains?(&1, "#")) |> List.last()

      assert first_section > Enum.find_index(hrefs, &(&1 == last_page))
    end

    test "the content rows are built once, not per palette open" do
      assert entries() == entries()

      calls = :counters.new(1, [])

      Gamend.Content.memoize({__MODULE__, :probe}, fn ->
        :counters.add(calls, 1, 1)
        [:built]
      end)

      assert Gamend.Content.memoize({__MODULE__, :probe}, fn -> [:rebuilt] end) == [:built]
      assert :counters.get(calls, 1) == 1
    end

    test "a guide carries its category as a keyword, so the category is searchable" do
      theme = Enum.find(entries(), &(&1.href == "/docs/theme"))

      assert theme.keywords == ["Setup"]
    end

    test "every blog post", %{entries: entries} do
      posts = group(entries, "Blog")

      assert length(posts) == length(Gamend.Content.list_blog_posts())
      assert Enum.all?(posts, &String.starts_with?(&1.href, "/blog/"))
    end

    # The navigation is prepended, and `SearchIndex` keeps the first row it saw
    # for an href. `/blog` the nav link must not be displaced by anything: it
    # is a top-level link, so it has no group, where a content row would.
    test "the nav's own links win a tie with content", %{entries: entries} do
      assert %{title: "Blog", group: nil} = Enum.find(entries, &(&1.href == "/blog"))
    end

    # Linked only from the footer, which the palette does not read.
    test "the changelog and the roadmap", %{entries: entries} do
      hrefs = Enum.map(entries, & &1.href)

      assert "/changelog" in hrefs
      assert "/roadmap" in hrefs
    end
  end

  describe "through core" do
    # Core prefixes only the paths this host declares translatable, which is
    # the point of handing it clean hrefs: the provider writes `/blog` and
    # `/docs/theme` and does not have to know that the blog index is
    # translated while the guides are English-only markdown.
    test "the index is localized on the way out, where the path is localized" do
      rows = SearchIndex.entries(%{scope: nil, locale: "ro"})
      hrefs = Enum.map(rows, & &1["href"])

      assert "/ro/blog" in hrefs
      assert "/docs/theme" in hrefs
      refute "/ro/docs/theme" in hrefs
    end
  end
end
