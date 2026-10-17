defmodule GamendWeb.SearchIndexTest do
  @moduledoc """
  The edge around a host's search provider.

  Two things are being pinned here. One is that a provider cannot break the
  palette: a crash, a bad entry, a wrong type — each costs that entry and
  nothing more. The other is the auth default, which is the only place this
  code can leak something: the nav's four sections do not share a default for
  an entry that omits `auth`, and flattening them with the public "any"
  default would offer a stranger the admin links.
  """
  use ExUnit.Case, async: false

  alias GamendWeb.SearchIndex

  defmodule RaisingProvider do
    @moduledoc false
    def entries(_context), do: raise("boom")
  end

  defmodule ThrowingProvider do
    @moduledoc false
    def entries(_context), do: throw(:nope)
  end

  defmodule NonsenseProvider do
    @moduledoc false
    def entries(_context), do: :not_a_list
  end

  defmodule StubProvider do
    @moduledoc false
    def entries(_context), do: Process.get(:stub_entries, [])
    def scopes(_context), do: Process.get(:stub_scopes, [])
  end

  setup context do
    previous = Application.get_env(:gamend_web, :search_provider)

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(:gamend_web, :search_provider)
      else
        Application.put_env(:gamend_web, :search_provider, previous)
      end
    end)

    # `Map.has_key?` and not a truthiness check: `false` is the value being
    # tested, and it is also the one a truthy guard would skip.
    if Map.has_key?(context, :provider) do
      Application.put_env(:gamend_web, :search_provider, context.provider)
    end

    :ok
  end

  defp entries(list) do
    Process.put(:stub_entries, list)
    SearchIndex.entries(%{scope: nil, locale: "en"})
  end

  describe "provider resolution" do
    test "defaults to the navigation provider when nothing is configured" do
      Application.delete_env(:gamend_web, :search_provider)

      assert SearchIndex.provider() == GamendWeb.SearchIndex.Default
      assert SearchIndex.enabled?()
    end

    @tag provider: false
    test "false is the off switch" do
      refute SearchIndex.enabled?()
      assert SearchIndex.entries(%{scope: nil, locale: "en"}) == []
      assert SearchIndex.scopes(%{scope: nil, locale: "en"}) == []
    end
  end

  describe "a provider that misbehaves" do
    @tag provider: RaisingProvider
    test "raising yields an empty index, not a failed page" do
      assert SearchIndex.entries(%{scope: nil, locale: "en"}) == []
    end

    @tag provider: ThrowingProvider
    test "throwing yields an empty index" do
      assert SearchIndex.entries(%{scope: nil, locale: "en"}) == []
    end

    @tag provider: NonsenseProvider
    test "returning something that is not a list yields an empty index" do
      assert SearchIndex.entries(%{scope: nil, locale: "en"}) == []
    end

    @tag provider: GamendWeb.SearchIndex.Default
    test "a provider without scopes/1 has no scopes" do
      assert SearchIndex.scopes(%{scope: nil, locale: "en"}) == []
    end
  end

  describe "normalization" do
    @tag provider: StubProvider
    test "an entry without a title or an href is dropped" do
      assert entries([
               %{title: "", href: "/a"},
               %{title: "B", href: ""},
               %{title: "C", href: "/c"},
               %{href: "/d"},
               "not a map"
             ]) == [
               %{
                 "title" => "C",
                 "href" => "/c",
                 "group" => nil,
                 "subtitle" => nil,
                 "keywords" => [],
                 "scope" => nil
               }
             ]
    end

    @tag provider: StubProvider
    test "string keys are accepted, since an entry may come from JSON" do
      assert [%{"title" => "Guide", "href" => "/guide", "group" => "News"}] =
               entries([%{"title" => "Guide", "href" => "/guide", "group" => "News"}])
    end

    @tag provider: StubProvider
    test "keywords are trimmed, de-duplicated and non-strings dropped" do
      assert [%{"keywords" => ["es", "Español"]}] =
               entries([
                 %{title: "Spanish", href: "/s", keywords: ["es", " es ", "Español", nil, %{}]}
               ])
    end

    @tag provider: StubProvider
    test "the first entry wins a duplicate href" do
      assert [%{"title" => "First"}] =
               entries([%{title: "First", href: "/x"}, %{title: "Second", href: "/x"}])
    end

    @tag provider: StubProvider
    test "an external href is left alone" do
      assert [%{"href" => "https://example.com/x"}] =
               entries([%{title: "Out", href: "https://example.com/x"}])
    end
  end

  describe "localization" do
    @tag provider: StubProvider
    test "a clean href picks up the locale prefix, query string and all" do
      Process.put(:stub_entries, [
        %{title: "Spanish", href: "/vocabulary/spanish?q={q}"},
        %{title: "Out", href: "https://example.com"}
      ])

      assert [%{"href" => localized}, %{"href" => "https://example.com"}] =
               SearchIndex.entries(%{scope: nil, locale: "ro"})

      # Whether a host localizes `/vocabulary` is its own configuration; what
      # this pins is that the query token survives whichever answer it gives.
      assert String.ends_with?(localized, "/vocabulary/spanish?q={q}")
    end

    @tag provider: StubProvider
    test "the default locale adds no prefix" do
      assert [%{"href" => "/guide"}] =
               (fn ->
                  Process.put(:stub_entries, [%{title: "Guide", href: "/guide"}])
                  SearchIndex.entries(%{scope: nil, locale: "en"})
                end).()
    end
  end

  describe "scopes" do
    @tag provider: StubProvider
    test "blank and repeated scopes are dropped" do
      Process.put(:stub_scopes, ["es_es", "", "es_es", "fr", nil])

      assert SearchIndex.scopes(%{scope: nil, locale: "en"}) == ["es_es", "fr"]
    end
  end

  describe "the default provider" do
    @navigation %{
      "primary_links" => [
        %{"label" => "Play", "href" => "/play"},
        %{
          "label" => "Learn",
          "items" => [
            %{"label" => "Vocabulary", "href" => "/vocabulary"},
            %{"label" => "Courses", "href" => "/courses"}
          ]
        },
        %{"label" => "Coins", "readonly" => true},
        %{"label" => "Soon", "href" => "/soon", "disabled" => true},
        %{"label" => "{Nope.gone}", "href" => "/nowhere"}
      ],
      "account_links" => [%{"label" => "Admin", "href" => "/admin"}]
    }

    test "groups flatten into rows that carry the dropdown's label" do
      links = GamendWeb.HostLayoutNavigation.flat_links(@navigation, nil)

      assert %{title: "Play", href: "/play", group: nil} in links
      assert %{title: "Vocabulary", href: "/vocabulary", group: "Learn"} in links
      assert %{title: "Courses", href: "/courses", group: "Learn"} in links
    end

    test "a readonly badge is not a destination" do
      links = GamendWeb.HostLayoutNavigation.flat_links(@navigation, nil)

      refute Enum.any?(links, &(&1.title == "Coins"))
    end

    test "a disabled (coming soon) link is not a destination" do
      links = GamendWeb.HostLayoutNavigation.flat_links(@navigation, nil)

      refute Enum.any?(links, &(&1.href == "/soon"))
    end

    test "a dynamic label that resolves to nothing is dropped" do
      links = GamendWeb.HostLayoutNavigation.flat_links(@navigation, nil)

      refute Enum.any?(links, &(&1.href == "/nowhere"))
    end

    test "an account link with no auth of its own is hidden from a stranger" do
      # The section defaults are why this is `section_entries/5` and not
      # `entry_visible?/2`: the public helper defaults to "any", which would
      # hand the admin console to anyone who opened the palette. The
      # signed-in half needs a real user and lives in the controller test.
      refute Enum.any?(
               GamendWeb.HostLayoutNavigation.flat_links(@navigation, nil),
               &(&1.href == "/admin")
             )
    end

    test "a navigation that is not a map yields nothing" do
      assert GamendWeb.HostLayoutNavigation.flat_links(nil, nil) == []
    end
  end
end
