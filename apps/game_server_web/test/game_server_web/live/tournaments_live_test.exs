defmodule GameServerWeb.TournamentsLiveTest do
  use GameServerWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias GameServer.Accounts
  alias GameServer.AccountsFixtures
  alias GameServer.Tournaments

  # A game's hook can refuse a registration (entry fee, rank gate, ...); the page
  # has to surface that rather than pretend the join worked.
  defmodule RejectingHook do
    def before_tournament_register(_user, _tournament), do: {:error, :not_enough_coins}
  end

  defp create_tournament(attrs \\ %{}) do
    defaults = %{
      slug: "cup-#{System.unique_integer([:positive])}",
      title: "Public Cup",
      description: "A public bracket cup",
      starts_at: DateTime.add(DateTime.utc_now(:second), 3600),
      round_window_sec: 600,
      bracket_size: 4
    }

    {:ok, tournament} = Tournaments.create_tournament(Map.merge(defaults, attrs))
    tournament
  end

  defp join(tournament, n) do
    for _ <- 1..n do
      {:ok, entry} =
        Tournaments.join_tournament(
          AccountsFixtures.user_fixture(),
          Tournaments.advance_lifecycle(tournament)
        )

      entry
    end
  end

  defp named_user(display_name) do
    {:ok, user} =
      Accounts.update_user_display_name(AccountsFixtures.user_fixture(), %{
        "display_name" => display_name
      })

    user
  end

  defp join_named(tournament, display_name) do
    user = named_user(display_name)
    {:ok, entry} = Tournaments.join_tournament(user, Tournaments.advance_lifecycle(tournament))
    entry
  end

  defp draw!(tournament) do
    {:ok, tournament} =
      Tournaments.update_tournament(tournament, %{starts_at: DateTime.utc_now(:second)})

    Tournaments.advance_lifecycle(tournament)
  end

  test "index shows one card per slug, not per edition", %{conn: conn} do
    slug = "cup-#{System.unique_integer([:positive])}"
    _old = create_tournament(%{slug: slug, state: "finished"})
    current = create_tournament(%{slug: slug})
    join(current, 2)

    {:ok, _view, html} = live(conn, ~p"/tournaments")

    # one card, with the edition count badge, not two "Public Cup" cards
    assert length(String.split(html, "card-title")) - 1 == 1
    assert html =~ "Public Cup"
    assert html =~ "Players: 2"
  end

  test "detail resolves a 16-character slug (Ecto.UUID.cast accepts 16-byte binaries)", %{
    conn: conn
  } do
    # "weekend-gauntlet" is exactly 16 bytes; Ecto.UUID.cast/1 treats any 16-byte
    # binary as a raw UUID, so fetch/1 used to look it up by id and 404 the page.
    slug = "weekend-gauntlet"
    assert byte_size(slug) == 16
    tournament = create_tournament(%{slug: slug})
    join(tournament, 2)

    {:ok, _view, html} = live(conn, ~p"/tournaments/#{slug}")

    assert html =~ "Public Cup"
    assert html =~ "Registered"
    refute html =~ "Not found"
  end

  test "index paginates", %{conn: conn} do
    for _ <- 1..3, do: create_tournament()

    {:ok, view, _html} = live(conn, ~p"/tournaments")
    # 3 tournaments fit one page (page size 25): no pager rendered
    refute render(view) =~ "Page 1 of"
  end

  test "detail lists registrants before the draw", %{conn: conn} do
    tournament = create_tournament()
    join(tournament, 3)
    join_named(tournament, "Ada Lovelace")

    {:ok, _view, html} = live(conn, ~p"/tournaments/#{tournament.id}")

    assert html =~ "Ada Lovelace"
    assert html =~ "Registered"
    # stat cards render the label and value separately
    assert html =~ "Players"
    assert html =~ ~s(<div class="text-2xl font-bold">4</div>)
    # no bracket column until there is a draw
    refute html =~ "matches decided"
  end

  test "detail shows brackets after the draw and links into one", %{conn: conn} do
    tournament = create_tournament()
    join(tournament, 4)
    tournament = draw!(tournament)

    {:ok, view, html} = live(conn, ~p"/tournaments/#{tournament.id}")

    assert html =~ "Brackets"
    assert html =~ "Bracket 1"
    assert html =~ "matches decided"

    # links are slug-based, not UUID-based, for SEO
    assert view
           |> element(~s|a[href="/tournaments/#{tournament.slug}/brackets/0"]|)
           |> has_element?()
  end

  test "detail keeps listing players after the draw, with bracket and result", %{conn: conn} do
    tournament = create_tournament()
    join(tournament, 3)
    entry = join_named(tournament, "Ada Lovelace")
    tournament = draw!(tournament)

    {:ok, view, html} = live(conn, ~p"/tournaments/#{tournament.id}")

    # brackets and the player list are both on the page
    assert html =~ "matches decided"
    assert html =~ "Ada Lovelace"
    assert html =~ "Playing"

    # each player links into their own bracket, with themselves selected
    entry = GameServer.Repo.reload!(entry)

    assert view
           |> element(
             ~s|a[href="/tournaments/#{tournament.slug}/brackets/#{entry.bracket_index}?entry=#{entry.id}"]|
           )
           |> has_element?()
  end

  test "detail filters players by name", %{conn: conn} do
    tournament = create_tournament()
    join_named(tournament, "Ada Lovelace")
    join_named(tournament, "Grace Hopper")

    {:ok, view, html} = live(conn, ~p"/tournaments/#{tournament.id}")
    assert html =~ "Ada Lovelace"
    assert html =~ "Grace Hopper"

    html =
      view
      |> form("#players-search-form", %{"search" => "grace"})
      |> render_change()

    assert html =~ "Grace Hopper"
    refute html =~ "Ada Lovelace"

    # a search that matches nobody says so rather than looking empty
    html = view |> form("#players-search-form", %{"search" => "zzz"}) |> render_change()
    assert html =~ "No results."
  end

  test "bracket view renders the tree with rounds and winners", %{conn: conn} do
    tournament = create_tournament()
    join(tournament, 4)
    tournament = draw!(tournament)

    [semi | _] = Tournaments.list_matches(tournament.id) |> Enum.filter(&(&1.round == 1))
    {:ok, _} = Tournaments.resolve_match(semi.id, semi.a_entry_id)

    {:ok, _view, html} = live(conn, ~p"/tournaments/#{tournament.id}/brackets/0")

    assert html =~ "Bracket 1"
    # 4-slot bracket: round 1 is the semifinal, round 2 the final
    assert html =~ "Semifinal"
    assert html =~ "Final"
    # the resolved match marks a winner
    assert html =~ "✓"
  end

  test "bracket view highlights the player linked from the list", %{conn: conn} do
    tournament = create_tournament()
    join(tournament, 3)
    entry = join_named(tournament, "Ada Lovelace")
    tournament = draw!(tournament)
    entry = GameServer.Repo.reload!(entry)

    {:ok, _view, html} =
      live(
        conn,
        ~p"/tournaments/#{tournament.id}/brackets/#{entry.bracket_index}?entry=#{entry.id}"
      )

    # the banner names them and reports how they are doing
    assert html =~ "Showing"
    assert html =~ "Ada Lovelace"
    assert html =~ "Playing"
    # and their slot in the tree is marked
    assert html =~ "ring-primary"

    # without the parameter the tree renders unhighlighted
    {:ok, _view, plain} =
      live(conn, ~p"/tournaments/#{tournament.id}/brackets/#{entry.bracket_index}")

    refute plain =~ "Showing"
    refute plain =~ "ring-primary"
  end

  describe "your own run" do
    # 8 players in 4-slot brackets = two brackets, so "a bracket you are not in"
    # is a real page rather than a case that never happens.
    setup :register_and_log_in_user

    setup %{user: user} do
      tournament = create_tournament()
      rivals = for n <- 1..7, do: join_named(tournament, "Rival #{n}")

      {:ok, me} =
        Accounts.update_user_display_name(user, %{"display_name" => "Ada Lovelace"})

      {:ok, mine} = Tournaments.join_tournament(me, Tournaments.advance_lifecycle(tournament))
      tournament = draw!(tournament)
      mine = GameServer.Repo.reload!(mine)

      neighbour =
        Enum.find_value(rivals, fn rival ->
          reloaded = GameServer.Repo.reload!(rival) |> GameServer.Repo.preload(:leader)
          if reloaded.bracket_index == mine.bracket_index, do: reloaded
        end)

      other_bracket =
        Tournaments.list_brackets(tournament.id)
        |> Enum.find(&(&1.index != mine.bracket_index))

      %{
        tournament: tournament,
        mine: mine,
        neighbour: neighbour,
        other_bracket: other_bracket
      }
    end

    test "a bracket you are in shows you by default", %{
      conn: conn,
      tournament: tournament,
      mine: mine
    } do
      {:ok, _view, html} =
        live(conn, ~p"/tournaments/#{tournament.slug}/brackets/#{mine.bracket_index}")

      assert html =~ "Showing"
      assert html =~ "Ada Lovelace"
      # the "You" badge, which only appears when the highlight is your own entry
      assert html =~ ~s(badge badge-primary badge-sm)
      assert html =~ "ring-primary"
    end

    test "an explicit entry link wins over defaulting to you", %{
      conn: conn,
      tournament: tournament,
      mine: mine,
      neighbour: neighbour
    } do
      assert neighbour, "expected a rival sharing the bracket"

      {:ok, _view, html} =
        live(
          conn,
          ~p"/tournaments/#{tournament.slug}/brackets/#{mine.bracket_index}?entry=#{neighbour.id}"
        )

      # the banner names them, and does not claim they are you
      assert html =~ "Showing"
      assert html =~ neighbour.leader.display_name
      refute html =~ ~s(badge badge-primary badge-sm)
    end

    test "a bracket you are not in highlights nobody", %{
      conn: conn,
      tournament: tournament,
      other_bracket: other_bracket
    } do
      assert other_bracket, "expected a second bracket"

      {:ok, _view, html} =
        live(conn, ~p"/tournaments/#{tournament.slug}/brackets/#{other_bracket.index}")

      refute html =~ "Showing"
      refute html =~ "ring-primary"
    end

    test "the player list marks your row", %{conn: conn, tournament: tournament} do
      {:ok, _view, html} = live(conn, ~p"/tournaments/#{tournament.slug}")

      assert html =~ "Ada Lovelace"
      assert html =~ ~s(badge badge-primary badge-sm)
    end

    test "a signed-out visitor sees no default highlight", %{tournament: tournament, mine: mine} do
      {:ok, _view, html} =
        live(build_conn(), ~p"/tournaments/#{tournament.slug}/brackets/#{mine.bracket_index}")

      refute html =~ "Showing"
      refute html =~ "ring-primary"
    end
  end

  describe "joining and leaving" do
    setup :register_and_log_in_user

    test "a signed-in visitor can join, then leave", %{conn: conn} do
      tournament = create_tournament()
      {:ok, view, html} = live(conn, ~p"/tournaments/#{tournament.slug}")

      assert html =~ "Join"
      refute html =~ "Leave"

      html = view |> element("#join-btn") |> render_click()
      assert html =~ "Leave"
      refute html =~ ~r/id="join-btn"/
      assert Tournaments.count_entries(tournament.id) == 1

      html = view |> element("#leave-btn") |> render_click()
      assert html =~ "Join"
      assert Tournaments.count_entries(tournament.id) == 0
    end

    test "joining shows you in the player list right away", %{conn: conn, user: user} do
      {:ok, _} = Accounts.update_user_display_name(user, %{"display_name" => "Ada Lovelace"})
      tournament = create_tournament()

      {:ok, view, _html} = live(conn, ~p"/tournaments/#{tournament.slug}")
      html = view |> element("#join-btn") |> render_click()

      assert html =~ "Ada Lovelace"
      # the Players stat moves with it
      assert html =~ ~s(<div class="text-2xl font-bold">1</div>)
    end

    test "a hook veto is surfaced instead of joining", %{conn: conn} do
      tournament = create_tournament()
      {:ok, view, _html} = live(conn, ~p"/tournaments/#{tournament.slug}")

      original = Application.get_env(:game_server_core, :hooks_module)
      Application.put_env(:game_server_core, :hooks_module, RejectingHook)

      on_exit(fn ->
        if original,
          do: Application.put_env(:game_server_core, :hooks_module, original),
          else: Application.delete_env(:game_server_core, :hooks_module)
      end)

      html = view |> element("#join-btn") |> render_click()

      # the game's own reason, humanized for display, and no entry created
      assert html =~ "Not enough coins"
      assert Tournaments.count_entries(tournament.id) == 0
      assert html =~ "Join"
    end

    test "no join button once the bracket is drawn", %{conn: conn} do
      tournament = create_tournament()
      join(tournament, 4)
      tournament = draw!(tournament)

      {:ok, _view, html} = live(conn, ~p"/tournaments/#{tournament.slug}")

      refute html =~ ~s(id="join-btn")
      refute html =~ ~s(id="leave-btn")
    end

    test "a participant cannot leave after the draw", %{conn: conn, user: user} do
      tournament = create_tournament()
      join(tournament, 3)
      {:ok, _} = Tournaments.join_tournament(user, Tournaments.advance_lifecycle(tournament))
      tournament = draw!(tournament)

      {:ok, _view, html} = live(conn, ~p"/tournaments/#{tournament.slug}")

      refute html =~ ~s(id="leave-btn")
    end
  end

  test "a signed-out visitor is pointed at log in", %{conn: conn} do
    tournament = create_tournament()

    {:ok, _view, html} = live(conn, ~p"/tournaments/#{tournament.slug}")

    refute html =~ ~s(id="join-btn")
    assert html =~ "Log in"
  end

  test "bracket view shows byes for empty round-1 slots", %{conn: conn} do
    tournament = create_tournament()
    join(tournament, 3)
    tournament = draw!(tournament)

    {:ok, _view, html} = live(conn, ~p"/tournaments/#{tournament.id}/brackets/0")

    assert html =~ "bye"
  end

  test "detail navigates between editions of the same slug", %{conn: conn} do
    slug = "cup-#{System.unique_integer([:positive])}"

    past =
      create_tournament(%{
        slug: slug,
        state: "finished",
        starts_at: DateTime.add(DateTime.utc_now(:second), -86_400)
      })

    current = create_tournament(%{slug: slug})

    {:ok, view, html} = live(conn, ~p"/tournaments/#{current.id}")
    assert html =~ "Older"
    assert html =~ "#2"

    html = view |> element("button[phx-click='older_edition']") |> render_click()
    assert html =~ "#1"
    # editions are numbered oldest-first, so the older one is edition 1
    assert_patched(view, ~p"/tournaments/#{slug}/1")
    assert past.slug == slug

    # a one-shot tournament has no edition navigation
    solo = create_tournament()
    {:ok, _view, html} = live(conn, ~p"/tournaments/#{solo.id}")
    refute html =~ "Older"
  end

  test "unknown tournament or bracket redirects to the index", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/tournaments"}}} =
             live(conn, ~p"/tournaments/#{Ecto.UUID.generate()}")

    tournament = create_tournament()

    assert {:error, {:live_redirect, %{to: "/tournaments"}}} =
             live(conn, ~p"/tournaments/#{tournament.id}/brackets/9")
  end

  test "tournament is reachable by slug", %{conn: conn} do
    tournament = create_tournament()

    {:ok, _view, html} = live(conn, ~p"/tournaments/#{tournament.slug}")
    assert html =~ "Public Cup"
  end

  describe "edition URLs" do
    setup do
      slug = "cup-#{System.unique_integer([:positive])}"

      past =
        create_tournament(%{
          slug: slug,
          state: "finished",
          title: "Old Cup",
          starts_at: DateTime.add(DateTime.utc_now(:second), -86_400)
        })

      current = create_tournament(%{slug: slug, title: "New Cup"})
      %{slug: slug, past: past, current: current}
    end

    test "an older edition is addressable by its number", %{conn: conn, slug: slug} do
      {:ok, _view, html} = live(conn, ~p"/tournaments/#{slug}/1")
      assert html =~ "Old Cup"

      # the bare slug lands on the live edition
      {:ok, _view, html} = live(conn, ~p"/tournaments/#{slug}")
      assert html =~ "New Cup"
    end

    test "edition numbers stay put when a newer edition appears", %{conn: conn, slug: slug} do
      create_tournament(%{slug: slug, title: "Newest Cup"})

      # edition 1 is still the oldest, not renumbered by the new arrival
      {:ok, _view, html} = live(conn, ~p"/tournaments/#{slug}/1")
      assert html =~ "Old Cup"
    end

    test "brackets are addressable per edition", %{conn: conn, slug: slug, current: current} do
      join(current, 4)
      draw!(current)

      {:ok, _view, html} = live(conn, ~p"/tournaments/#{slug}/brackets/0")
      assert html =~ "Bracket 1"

      {:ok, _view, html} = live(conn, ~p"/tournaments/#{slug}/2/brackets/0")
      assert html =~ "Bracket 1"
    end

    test "an out-of-range or non-numeric edition is not found", %{conn: conn, slug: slug} do
      for bad <- ["0", "99", "abc"] do
        assert {:error, {:live_redirect, %{to: "/tournaments"}}} =
                 live(conn, ~p"/tournaments/#{slug}/#{bad}")
      end
    end

    test "old UUID links still resolve", %{conn: conn, past: past} do
      {:ok, _view, html} = live(conn, ~p"/tournaments/#{past.id}")
      assert html =~ "Old Cup"
    end
  end

  test "bracket page shows the tournament date and state", %{conn: conn} do
    tournament = create_tournament()
    join(tournament, 4)
    tournament = draw!(tournament)

    {:ok, _view, html} = live(conn, ~p"/tournaments/#{tournament.slug}/brackets/0")

    assert html =~ Calendar.strftime(tournament.starts_at, "%b %d, %Y")
    assert html =~ "Running"
  end
end
