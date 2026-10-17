defmodule GamendWeb.QuestsLiveCardTest do
  @moduledoc """
  The quest list is a grid of clickable cards, so it has to read like the
  leaderboard and tournament grids rather than as its own dialect.
  """

  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gamend.Quests

  # A host's own selector: it covers the "countries" group and not "seas",
  # and its control only has to send "group" with a `group` param. It prints
  # keys, never titles, so a test can tell a card from the picker.
  defmodule HostPicker do
    @behaviour GamendWeb.QuestGroupSelector

    use Phoenix.Component

    @impl true
    def selectable?(%{key: key}), do: key == "countries"

    @impl true
    def selector(assigns) do
      ~H"""
      <form id="host-picker" phx-change="group">
        <label :for={g <- @groups}>
          <input type="radio" name="group" value={g.key} checked={g.key == @selected} />
          {g.key}
        </label>
      </form>
      """
    end

    # Answers "countries" only for the user the test expects, so the rendered
    # page proves what the hook was handed — or whatever a test planted.
    @impl true
    def default_group(user_id) do
      case :persistent_term.get({__MODULE__, :default}, nil) do
        nil ->
          if user_id == :persistent_term.get({__MODULE__, :expected_user}, :nobody),
            do: "countries",
            else: nil

        planted ->
          planted
      end
    end
  end

  setup do
    for attrs <- [
          %{
            key: "card_daily",
            title: "Daily check-in",
            description: "Log in today.",
            category: "Daily",
            reset: "daily",
            icon_url: "/icons/calendar-days.svg",
            objectives: [%{event: "login", target: 1}]
          },
          %{
            key: "card_weekly",
            title: "Weekly regular",
            description: "Log in on five days.",
            category: "Achievements",
            reset: "weekly",
            icon_url: "/icons/calendar.svg",
            objectives: [%{event: "login", target: 5}]
          },
          %{
            key: "card_locked",
            title: "Loyal veteran",
            description: "Log in fifty times.",
            category: "Chained",
            reset: "never",
            prerequisite_quest_key: "card_daily",
            icon_url: "/icons/shield-check.svg",
            objectives: [%{event: "login", target: 50}]
          }
        ] do
      {:ok, _} = Quests.create_quest(attrs)
    end

    :ok
  end

  defp page(conn) do
    {:ok, _view, html} = live(conn, ~p"/quests")
    html
  end

  describe "grouped quests" do
    setup do
      for id <- ["ro", "es", "pl"] do
        {:ok, _} =
          Quests.create_quest(%{
            key: "visit_#{id}",
            title: "Visit #{String.upcase(id)}",
            description: "Visit every city.",
            category: "exploration",
            group_key: "countries",
            group_title: "Visit countries",
            objectives: [%{event: "city_visited", target: 5, params: %{"country" => id}}]
          })
      end

      :ok
    end

    test "the group is one card, named for the group", %{conn: conn} do
      html = page(conn)

      assert html =~ "Visit countries", "the card is titled by the group"

      refute html =~ "Visit RO",
             "a member's own title must not head a card that stands for three"
    end

    test "opening the group renders every member", %{conn: conn} do
      conn = log_in_user(conn, Gamend.AccountsFixtures.user_fixture())
      {:ok, view, _html} = live(conn, ~p"/quests")

      # Rendering the modal used to raise KeyError :locked — the members come
      # from Quests.group/2, which has no tiers and so no `locked` key, and the
      # modal was reusing the chain's status label.
      html = render_click(view, "show_group", %{"group" => "countries"})

      for id <- ["RO", "ES", "PL"], do: assert(html =~ "Visit #{id}")
      assert html =~ "Not started"
    end

    test "opening a group a signed-out visitor can see does not raise", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/quests")

      assert render_click(view, "show_group", %{"group" => "countries"}) =~ "Visit countries"
    end

    test "a hidden member stays a teaser once the group is open", %{conn: conn} do
      {:ok, _} =
        Quests.create_quest(%{
          key: "visit_atlantis",
          title: "Visit Atlantis",
          description: "Find the lost city.",
          hidden: true,
          group_key: "countries",
          group_title: "Visit countries",
          objectives: [%{event: "city_visited", target: 5, params: %{"country" => "atl"}}]
        })

      conn = log_in_user(conn, Gamend.AccountsFixtures.user_fixture())
      {:ok, view, _html} = live(conn, ~p"/quests")

      html = render_click(view, "show_group", %{"group" => "countries"})

      assert html =~ "???"
      refute html =~ "Visit Atlantis", "opening a group must not spoil a hidden member"
    end
  end

  describe "the group selector" do
    # Two groups of two, so picking one has something to drop, and the other
    # is a real collapsed card (a group of one lists as the one).
    setup do
      for {id, group, title} <- [
            {"ro", "countries", "Visit countries"},
            {"es", "countries", "Visit countries"},
            {"fr", "seas", "Sail the seas"},
            {"it", "seas", "Sail the seas"}
          ] do
        {:ok, _} =
          Quests.create_quest(%{
            key: "visit_#{id}",
            title: "Visit #{String.upcase(id)}",
            description: "Visit every city.",
            category: "exploration",
            group_key: group,
            group_title: title,
            objectives: [%{event: "city_visited", target: 5, params: %{"country" => id}}]
          })
      end

      orig_selector = Application.get_env(:gamend_web, :quest_group_selector)

      on_exit(fn ->
        restore(:quest_group_selector, orig_selector)
        :persistent_term.erase({HostPicker, :default})
        :persistent_term.erase({HostPicker, :expected_user})
      end)

      :ok
    end

    defp restore(key, nil), do: Application.delete_env(:gamend_web, key)
    defp restore(key, value), do: Application.put_env(:gamend_web, key, value)

    # The plain select prints every group's title as an option, so a title's
    # presence says nothing about its card: count it. One is the option alone.
    defp occurrences(html, text), do: length(String.split(html, text)) - 1

    test "the plain select offers every group behind an All that keeps the cards collapsed",
         %{conn: conn} do
      html = page(conn)

      assert html =~ ~s(<select name="group")
      assert occurrences(html, "Visit countries") == 2, "the option, and the collapsed card"
      assert occurrences(html, "Sail the seas") == 2
      refute html =~ "Visit RO", "All is the collapsed cards, as before"
    end

    test "picking a group lists its members and drops the other groups", %{conn: conn} do
      for conn <- [conn, log_in_user(conn, Gamend.AccountsFixtures.user_fixture())] do
        {:ok, view, _html} = live(conn, ~p"/quests")

        html = view |> element("#quest-groups") |> render_change(%{"group" => "countries"})

        assert html =~ "Visit RO"
        assert html =~ "Visit ES"

        assert occurrences(html, "Sail the seas") == 1,
               "the unpicked group is off the page, not collapsed: its option alone remains"

        refute html =~ "Visit FR"
        # The ungrouped quests stay.
        assert html =~ "Daily check-in"

        html = view |> element("#quest-groups") |> render_change(%{"group" => ""})
        refute html =~ "Visit RO"
        assert occurrences(html, "Sail the seas") == 2, "All: the card is back"
      end
    end

    test "no selector renders when the view has no groups", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/quests")
      html = render_click(view, "category", %{"category" => "Daily"})

      refute html =~ ~s(<select name="group")
    end

    test "a host selector covers its groups; the rest keep their card", %{conn: conn} do
      Application.put_env(:gamend_web, :quest_group_selector, HostPicker)

      for conn <- [conn, log_in_user(conn, Gamend.AccountsFixtures.user_fixture())] do
        {:ok, view, html} = live(conn, ~p"/quests")

        assert html =~ "host-picker"
        assert html =~ ~s(value="countries")
        refute html =~ ~s(value="seas"), "not the selector's, so not in it"
        refute html =~ ~s(<select name="group"), "the host's control replaces the plain one"
        refute html =~ "Visit countries", "nothing picked: the selector's group is off the page"
        assert html =~ "Sail the seas", "a group the selector does not cover is still its card"
        refute html =~ "Visit FR", "…collapsed, not opened"
        assert html =~ "Daily check-in"

        # Picking through the host's control lists the members; the other card stays.
        html = view |> element("#host-picker") |> render_change(%{"group" => "countries"})
        assert html =~ "Visit RO"
        assert html =~ "Visit ES"
        assert html =~ "Sail the seas"
        refute html =~ "Visit FR"
      end
    end

    test "the host's default group opens on mount, for the signed-in user", %{conn: conn} do
      Application.put_env(:gamend_web, :quest_group_selector, HostPicker)

      user = Gamend.AccountsFixtures.user_fixture()
      :persistent_term.put({HostPicker, :expected_user}, user.id)

      # A visitor is not that user: nothing picked, the selector's group off the page.
      refute page(conn) =~ "Visit RO"

      {:ok, _view, html} = live(log_in_user(conn, user), ~p"/quests")
      assert html =~ "Visit RO"
      assert html =~ "Sail the seas"
    end

    test "a default the viewer's groups do not hold is ignored", %{conn: conn} do
      Application.put_env(:gamend_web, :quest_group_selector, HostPicker)
      :persistent_term.put({HostPicker, :default}, "atlantis")

      html = page(conn)

      # Nothing picked, then: the selector's group off the page, the other's card up.
      refute html =~ "Visit countries"
      refute html =~ "Visit RO"
      assert html =~ "Sail the seas"
    end
  end

  test "the icon sits in the title, with no boxed-off tile around it", %{conn: conn} do
    html = page(conn)

    assert html =~ ~s(class="card-title text-lg")

    refute html =~ "w-12 h-12 rounded-lg",
           "the icon tile is gone; the icon reads like the other grids"
  end

  test "title and description use the same sizes as the other grids", %{conn: conn} do
    html = page(conn)

    assert html =~ "card-title text-lg"
    assert html =~ "text-sm text-muted line-clamp-2"
  end

  test "a signed-out visitor gets no per-viewer status badge", %{conn: conn} do
    html = page(conn)

    refute html =~ "Not started",
           "progress belongs to a viewer; seven cards reading Not started is noise"

    refute html =~ "In progress"
  end

  test "a signed-in player gets one, coloured like Active/Ended elsewhere", %{conn: conn} do
    conn = log_in_user(conn, Gamend.AccountsFixtures.user_fixture())
    html = page(conn)

    assert html =~ "Daily check-in", "the signed-in user should still see the quests"

    # Logging in fires the `login` event these quests track, so the daily is
    # already claimable and the weekly in progress — any of the labels will do,
    # the point is that a status badge is present and colour-coded.
    assert html =~ "badge-success" or html =~ "badge-neutral"

    assert Enum.any?(
             ["Not started", "In progress", "Ready to claim", "Completed", "Claimed"],
             &String.contains?(html, &1)
           )
  end

  test "the cadence badge is dropped when it just repeats the category", %{conn: conn} do
    html = page(conn)

    # "Daily check-in" is category Daily *and* reset daily — one badge, not two.
    daily_card =
      html
      |> String.split("Daily check-in")
      |> Enum.at(1, "")
      |> String.slice(0, 900)

    assert String.contains?(daily_card, "Daily"), "the category badge should still be there"

    refute Regex.scan(~r/>\s*Daily\s*</, daily_card) |> length() > 1,
           "Daily is shown twice on the same card"
  end

  test "the cadence badge stays when it differs from the category", %{conn: conn} do
    html = page(conn)
    weekly = html |> String.split("Weekly regular") |> Enum.at(1, "") |> String.slice(0, 900)

    assert String.contains?(weekly, "Achievements")
    assert String.contains?(weekly, "Weekly")
  end

  test "repeat quests do not render an empty cadence badge", %{conn: conn} do
    for {key, title} <- [{"repeat_cups", "Tournaments"}, {"repeat_treasures", "Treasures"}] do
      {:ok, _} =
        Quests.create_quest(%{
          key: key,
          title: title,
          description: "Repeatable reward.",
          category: "weekly",
          reset: "repeat",
          objectives: [%{event: key, target: 1}]
        })
    end

    html = page(conn)

    refute html =~ ~r/<span class="badge badge-ghost badge-sm text-nowrap">\s*<\/span>/,
           "repeat quests have no cadence label, so they should not render an empty badge"
  end

  test "a long chain reports its real length, not the walk limit", %{conn: conn} do
    # The depth walk used to stop at 20 hops to survive malformed cycles, which
    # cannot tell a cycle from a genuinely long chain: the 52-unit course showed
    # every unit as "1/21". Silent — the number was plausible.
    for tier <- 1..30 do
      {:ok, _} =
        Quests.create_quest(%{
          key: "long_#{tier}",
          title: "Long tier #{tier}",
          description: "Tier #{tier}.",
          category: "Long",
          objectives: [%{event: "long_evt", target: 1}],
          prerequisite_quest_key: if(tier > 1, do: "long_#{tier - 1}")
        })
    end

    html = page(conn)

    assert html =~ "1/30", "a 30-long chain must report 30, not the old 21 cap"
    refute html =~ "1/21"
  end

  test "a category with nothing visible behind it gets no tab", %{conn: conn} do
    html = page(conn)

    assert html =~ "Daily"
    assert html =~ "Achievements"

    refute html =~ ~r/>\s*Chained\s*</,
           "the chained tier is locked, so its tab would open onto nothing"
  end
end
