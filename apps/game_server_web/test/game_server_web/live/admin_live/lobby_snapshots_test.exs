defmodule GameServerWeb.AdminLive.LobbySnapshotsTest do
  # async: false — the writer is a named process shared across tests.
  use GameServerWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias GameServer.Accounts.User
  alias GameServer.AccountsFixtures
  alias GameServer.Lobbies
  alias GameServer.LobbySnapshots
  alias GameServer.LobbySnapshots.Writer
  alias GameServer.Repo

  setup %{conn: conn} do
    previous = Application.get_env(:game_server_core, LobbySnapshots, [])
    Application.put_env(:game_server_core, LobbySnapshots, enabled: true, user_kv_keys: [])
    on_exit(fn -> Application.put_env(:game_server_core, LobbySnapshots, previous) end)

    {:ok, _writer} = Writer.start_link([])

    admin = AccountsFixtures.user_fixture()
    {:ok, admin} = admin |> User.admin_changeset(%{"is_admin" => true}) |> Repo.update()

    {:ok, lobby} = Lobbies.create_lobby(%{title: "snapshot-room", host_id: admin.id})

    capture = fn trigger ->
      :ok = LobbySnapshots.capture_lobby(lobby.id, trigger, sync: true)
      :ok = Writer.flush()
    end

    capture.("test:first")

    # Changes two sections, so per-section filtering has something to narrow.
    # Note `lobbies` timestamps are second-precision, so `updated_at` does not
    # differ between captures milliseconds apart — the lobby section has exactly
    # one changed row.
    {:ok, _} =
      Lobbies.update_lobby(Repo.get!(Lobbies.Lobby, lobby.id), %{
        title: "renamed-mid-run",
        metadata: %{"boat_adventure" => %{"distance" => 250.5}}
      })

    capture.("test:second")

    %{conn: log_in_user(conn, admin), lobby: lobby}
  end

  test "lists recorded runs", %{conn: conn, lobby: lobby} do
    {:ok, _live, html} = live(conn, ~p"/admin/lobby_snapshots")

    assert html =~ "Lobby snapshots"
    assert html =~ lobby.id
  end

  test "shows a run's timeline with its triggers and events", %{conn: conn, lobby: lobby} do
    :ok = LobbySnapshots.record_event(lobby.id, "boat.speed", %{from: 100, to: 50})
    :ok = Writer.flush()

    {:ok, _live, html} = live(conn, ~p"/admin/lobby_snapshots?lobby_id=#{lobby.id}")

    assert html =~ "test:first"
    assert html =~ "test:second"
    assert html =~ "boat.speed"
  end

  test "expanding a snapshot shows the field that changed", %{conn: conn, lobby: lobby} do
    {:ok, live, _html} = live(conn, ~p"/admin/lobby_snapshots?lobby_id=#{lobby.id}")

    [_first, second] = LobbySnapshots.list_snapshots(lobby.id)

    html =
      live
      |> element("button[phx-value-id='#{second.id}']")
      |> render_click()

    # The diff is the point of the page: the changed field, both values, and
    # the section it lives in.
    assert html =~ "title"
    assert html =~ "snapshot-room"
    assert html =~ "renamed-mid-run"
  end

  test "the first snapshot says there is nothing to compare against", %{
    conn: conn,
    lobby: lobby
  } do
    {:ok, live, _html} = live(conn, ~p"/admin/lobby_snapshots?lobby_id=#{lobby.id}")

    [first, _second] = LobbySnapshots.list_snapshots(lobby.id)

    html =
      live
      |> element("button[phx-value-id='#{first.id}']")
      |> render_click()

    assert html =~ "nothing to compare against"
  end

  describe "filtering" do
    defp expand_second(live, lobby) do
      [_first, second] = LobbySnapshots.list_snapshots(lobby.id)
      html = live |> element("button[phx-value-id='#{second.id}']") |> render_click()
      {second, html}
    end

    test "the run filter narrows rows across every section", %{conn: conn, lobby: lobby} do
      {:ok, live, _html} = live(conn, ~p"/admin/lobby_snapshots?lobby_id=#{lobby.id}")
      {_second, html} = expand_second(live, lobby)

      # Both sections changed, so both render rows.
      assert html =~ "renamed-mid-run"
      assert html =~ "250.5"
      refute html =~ "No rows match."

      filtered = live |> form("#run-filter", %{q: "title"}) |> render_change()

      # lobby keeps its row; lobby_metadata has nothing matching and says so.
      assert filtered =~ "renamed-mid-run"
      assert filtered =~ "No rows match."
    end

    test "the filter matches values, not just field names", %{conn: conn, lobby: lobby} do
      {:ok, live, _html} = live(conn, ~p"/admin/lobby_snapshots?lobby_id=#{lobby.id}")
      expand_second(live, lobby)

      # "250.5" is a value, not a path — searching by what a field changed *to*
      # is the common case when chasing a bad value.
      html = live |> form("#run-filter", %{q: "250.5"}) |> render_change()

      assert html =~ "250.5"
      # The lobby section has no row containing 250.5.
      assert html =~ "No rows match."
    end

    test "a filter matching nothing says so rather than rendering an empty table", %{
      conn: conn,
      lobby: lobby
    } do
      {:ok, live, _html} = live(conn, ~p"/admin/lobby_snapshots?lobby_id=#{lobby.id}")
      expand_second(live, lobby)

      html = live |> form("#run-filter", %{q: "zzz-no-such-field"}) |> render_change()

      assert html =~ "No rows match."
      assert html =~ "(0 of 1)"
    end

    test "a per-section filter narrows only its own section", %{conn: conn, lobby: lobby} do
      {:ok, live, _html} = live(conn, ~p"/admin/lobby_snapshots?lobby_id=#{lobby.id}")
      {second, _html} = expand_second(live, lobby)

      html =
        live
        |> form("#section-filter-#{second.id}-lobby", %{section: "lobby", q: "zzz"})
        |> render_change()

      # lobby is emptied by its own filter; lobby_metadata is untouched by it.
      assert html =~ "No rows match."
      assert html =~ "250.5"
    end

    test "each section's filter box is labelled with its section", %{conn: conn, lobby: lobby} do
      {:ok, live, _html} = live(conn, ~p"/admin/lobby_snapshots?lobby_id=#{lobby.id}")
      {_second, html} = expand_second(live, lobby)

      # HEEx does not interpolate inside quoted attributes, so this catches the
      # placeholder rendering as a literal "filter #{section}".
      assert html =~ ~s(placeholder="filter lobby_metadata")
      refute html =~ "\#{section}"
    end

    test "filtering events keeps the ones that match", %{conn: conn, lobby: lobby} do
      :ok = LobbySnapshots.record_event(lobby.id, "boat.speed", %{from: 100, to: 50})
      :ok = LobbySnapshots.record_event(lobby.id, "boat.collision", %{actor: "starfish"})
      :ok = Writer.flush()

      {:ok, live, html} = live(conn, ~p"/admin/lobby_snapshots?lobby_id=#{lobby.id}")
      assert html =~ "boat.speed"
      assert html =~ "boat.collision"

      filtered = live |> form("form[phx-change='filter']", %{q: "collision"}) |> render_change()

      assert filtered =~ "boat.collision"
      refute filtered =~ "boat.speed"
    end
  end

  test "long event lists collapse and expand on demand", %{conn: conn, lobby: lobby} do
    # A real run puts dozens of events in one interval; showing them all inline
    # recreates the wall of logs this view replaces.
    for i <- 1..15 do
      :ok = LobbySnapshots.record_event(lobby.id, "boat.tick.#{i}", %{step: i})
    end

    :ok = Writer.flush()

    {:ok, live, html} = live(conn, ~p"/admin/lobby_snapshots?lobby_id=#{lobby.id}")

    assert html =~ "boat.tick.1"
    refute html =~ "boat.tick.15"
    assert html =~ "Show 7 more events"

    expanded = live |> element("button[phx-click='toggle_events']") |> render_click()
    assert expanded =~ "boat.tick.15"
  end

  test "event payloads render as discrete fields, not a truncated blob", %{
    conn: conn,
    lobby: lobby
  } do
    :ok =
      LobbySnapshots.record_event(lobby.id, "boat.speed", %{
        from: "full",
        to: "boost",
        current_dist: 8423.199939727783
      })

    :ok = Writer.flush()

    {:ok, _live, html} = live(conn, ~p"/admin/lobby_snapshots?lobby_id=#{lobby.id}")

    assert html =~ "current_dist="
    assert html =~ "to="
    # Full float precision survives — 8423.2 vs 8423.199939727783 is exactly the
    # drift worth seeing.
    assert html =~ "8423.199939727783"
  end

  test "coverage gaps are surfaced as a warning with a link to the run", %{
    conn: conn,
    lobby: lobby
  } do
    :ok =
      LobbySnapshots.record_coverage_gap(lobby.id, "unserialized_write", %{
        "section" => "boat_adventure"
      })

    :ok = Writer.flush()

    {:ok, _live, html} = live(conn, ~p"/admin/lobby_snapshots")

    assert html =~ "coverage gap"
    assert html =~ "coverage:unserialized_write"
    assert html =~ lobby.id
  end

  test "flagged filter narrows the list to anomalous runs", %{conn: conn, lobby: lobby} do
    other = AccountsFixtures.user_fixture()
    {:ok, flagged_lobby} = Lobbies.create_lobby(%{title: "bad-run", host_id: other.id})
    :ok = LobbySnapshots.capture_lobby(flagged_lobby.id, "hook:boom", sync: true, flagged: true)
    :ok = Writer.flush()

    {:ok, live, _html} = live(conn, ~p"/admin/lobby_snapshots")

    html = live |> element("button[phx-click='toggle_flagged']") |> render_click()

    assert html =~ flagged_lobby.id
    refute html =~ lobby.id
  end
end
