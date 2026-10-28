defmodule GamendWeb.Api.V1.TournamentControllerTest do
  use GamendWeb.ConnCase, async: false

  alias Gamend.AccountsFixtures
  alias Gamend.Tournaments
  alias GamendWeb.Auth.Guardian

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    {:ok, access, _} = Guardian.encode_and_sign(user)

    {:ok, tournament} =
      Tournaments.create_tournament(%{
        slug: "api-cup-#{System.unique_integer([:positive])}",
        title: "API Cup",
        starts_at: DateTime.add(DateTime.utc_now(:second), 3600),
        round_window_sec: 600
      })

    %{
      conn: conn,
      user: user,
      tournament: tournament,
      auth_conn: put_req_header(conn, "authorization", "Bearer " <> access)
    }
  end

  test "GET /api/v1/tournaments lists and filters", %{conn: conn, tournament: tournament} do
    resp = conn |> get("/api/v1/tournaments") |> json_response(200)
    assert Enum.any?(resp["data"], &(&1["id"] == tournament.id))

    # index lists raw state (no lazy advance): a fresh tournament is scheduled
    resp = conn |> get("/api/v1/tournaments?state=scheduled") |> json_response(200)
    assert Enum.any?(resp["data"], &(&1["id"] == tournament.id))

    resp = conn |> get("/api/v1/tournaments?state=finished") |> json_response(200)
    refute Enum.any?(resp["data"], &(&1["id"] == tournament.id))
  end

  test "GET /api/v1/tournaments/:id works by id and by slug", %{
    conn: conn,
    tournament: tournament
  } do
    resp = conn |> get("/api/v1/tournaments/#{tournament.id}") |> json_response(200)
    assert resp["data"]["slug"] == tournament.slug
    assert resp["data"]["state"] == "registration"
    assert resp["data"]["my_entry"] == nil

    resp = conn |> get("/api/v1/tournaments/#{tournament.slug}") |> json_response(200)
    assert resp["data"]["id"] == tournament.id

    assert conn |> get("/api/v1/tournaments/#{Ecto.UUID.generate()}") |> json_response(404)
  end

  test "GET /api/v1/tournaments/:id finds a 16-character slug", %{conn: conn} do
    {:ok, tournament} =
      Tournaments.create_tournament(%{
        slug: "weekend-gauntlet",
        title: "Weekend Gauntlet",
        round_window_sec: 600
      })

    resp = conn |> get("/api/v1/tournaments/weekend-gauntlet") |> json_response(200)
    assert resp["data"]["id"] == tournament.id
  end

  test "join/leave lifecycle over the API", %{auth_conn: auth_conn, tournament: tournament} do
    resp = auth_conn |> post("/api/v1/tournaments/#{tournament.id}/join") |> json_response(200)
    assert resp["data"]["state"] == "registered"
    assert resp["data"]["seed"] == nil

    resp = auth_conn |> get("/api/v1/tournaments/#{tournament.id}") |> json_response(200)
    assert resp["data"]["my_entry"]["state"] == "registered"
    assert resp["data"]["entry_count"] == 1

    resp =
      auth_conn |> post("/api/v1/tournaments/#{tournament.id}/join") |> json_response(409)

    assert resp["error"] == "already_registered"

    resp = auth_conn |> delete("/api/v1/tournaments/#{tournament.id}/join") |> json_response(200)
    assert resp == %{"ok" => true}

    resp = auth_conn |> delete("/api/v1/tournaments/#{tournament.id}/join") |> json_response(404)
    assert resp["error"] == "not_registered"
  end

  test "join is refused when full or closed, leave once drawn", %{
    auth_conn: auth_conn,
    user: user,
    tournament: tournament
  } do
    {:ok, full} = Tournaments.update_tournament(tournament, %{max_entries: 2})

    for _ <- 1..2 do
      {:ok, _} =
        Tournaments.join_tournament(
          AccountsFixtures.user_fixture(),
          Tournaments.advance_lifecycle(full)
        )
    end

    resp = auth_conn |> post("/api/v1/tournaments/#{full.id}/join") |> json_response(403)
    assert resp["error"] == "tournament_full"

    {:ok, open} = Tournaments.update_tournament(full, %{max_entries: 4})
    {:ok, _} = Tournaments.join_tournament(user, Tournaments.advance_lifecycle(open))

    {:ok, running} =
      Tournaments.update_tournament(open, %{starts_at: DateTime.utc_now(:second)})

    assert Tournaments.advance_lifecycle(running).state == "running"

    resp = auth_conn |> delete("/api/v1/tournaments/#{running.id}/join") |> json_response(409)
    assert resp["error"] == "already_drawn"

    late = AccountsFixtures.user_fixture()
    {:ok, access, _} = Guardian.encode_and_sign(late)

    resp =
      build_conn()
      |> put_req_header("authorization", "Bearer " <> access)
      |> post("/api/v1/tournaments/#{running.id}/join")
      |> json_response(403)

    assert resp["error"] == "registration_closed"
  end

  test "unknown tournaments answer not_found", %{conn: conn, auth_conn: auth_conn} do
    id = Ecto.UUID.generate()

    for path <- ["", "/entries", "/bracket", "/standings"] do
      resp = conn |> get("/api/v1/tournaments/#{id}#{path}") |> json_response(404)
      assert resp["error"] == "not_found", path
    end

    for {verb, path} <- [{:get, "/my_match"}, {:post, "/join"}, {:delete, "/join"}] do
      resp =
        auth_conn
        |> dispatch(@endpoint, verb, "/api/v1/tournaments/#{id}#{path}")
        |> json_response(404)

      assert resp["error"] == "not_found", path
    end
  end

  test "join requires authentication", %{conn: conn, tournament: tournament} do
    assert conn |> post("/api/v1/tournaments/#{tournament.id}/join") |> response(401)
  end

  test "GET /tournaments/:id/entries paginates and filters by state", %{
    conn: conn,
    user: user,
    tournament: tournament
  } do
    {:ok, _} = Tournaments.join_tournament(user, tournament)

    for _ <- 1..2 do
      {:ok, _} =
        Tournaments.join_tournament(Gamend.AccountsFixtures.user_fixture(), tournament)
    end

    resp = conn |> get("/api/v1/tournaments/#{tournament.id}/entries") |> json_response(200)
    assert length(resp["data"]) == 3
    assert resp["meta"]["total_count"] == 3
    assert resp["meta"]["total_pages"] == 1

    resp =
      conn
      |> get("/api/v1/tournaments/#{tournament.id}/entries?page=2&page_size=2")
      |> json_response(200)

    assert length(resp["data"]) == 1
    assert resp["meta"]["page"] == 2
    assert resp["meta"]["total_pages"] == 2

    resp =
      conn
      |> get("/api/v1/tournaments/#{tournament.id}/entries?state=eliminated")
      |> json_response(200)

    assert resp["data"] == []
    assert resp["meta"]["total_count"] == 0
  end

  test "GET /tournaments/:id/bracket paginates by bracket and filters by index", %{
    conn: conn,
    tournament: tournament
  } do
    # bracket_size 2 with 4 entries = two brackets
    {:ok, tournament} = Tournaments.update_tournament(tournament, %{bracket_size: 2})

    for _ <- 1..4 do
      {:ok, _} =
        Tournaments.join_tournament(
          Gamend.AccountsFixtures.user_fixture(),
          Tournaments.advance_lifecycle(tournament)
        )
    end

    {:ok, tournament} =
      Tournaments.update_tournament(tournament, %{starts_at: DateTime.utc_now(:second)})

    tournament = Tournaments.advance_lifecycle(tournament)
    assert tournament.state == "running"

    resp = conn |> get("/api/v1/tournaments/#{tournament.id}/bracket") |> json_response(200)
    assert [%{"index" => 0}, %{"index" => 1}] = resp["data"]
    assert resp["meta"]["total_count"] == 2

    # each bracket carries its own matches and the entries they name
    for bracket <- resp["data"] do
      assert Enum.all?(bracket["matches"], &(&1["bracket_index"] == bracket["index"]))
      named = Enum.flat_map(bracket["matches"], &[&1["a_entry_id"], &1["b_entry_id"]])
      assert Enum.sort(Enum.map(bracket["entries"], & &1["id"])) == Enum.sort(named)
    end

    resp =
      conn
      |> get("/api/v1/tournaments/#{tournament.id}/bracket?page=1&page_size=1")
      |> json_response(200)

    assert [%{"entries" => entries}] = resp["data"]
    assert resp["meta"]["total_pages"] == 2
    # only the entries of the returned bracket are included
    assert length(entries) == 2

    resp =
      conn
      |> get("/api/v1/tournaments/#{tournament.id}/bracket?index=1")
      |> json_response(200)

    assert [%{"index" => 1}] = resp["data"]
    assert resp["meta"]["total_count"] == 1
    assert resp["meta"]["has_more"] == false

    assert conn
           |> get("/api/v1/tournaments/#{tournament.id}/bracket?index=9")
           |> json_response(404)

    resp =
      conn
      |> get("/api/v1/tournaments/#{tournament.id}/bracket?index=one")
      |> json_response(400)

    assert resp["error"] == "invalid_index"

    # an unset index, as the Godot SDK sends it, is no filter
    resp =
      conn
      |> get("/api/v1/tournaments/#{tournament.id}/bracket?index&page=1")
      |> json_response(200)

    assert length(resp["data"]) == 2
  end

  test "bracket, standings and my_match after a draw", %{
    auth_conn: auth_conn,
    conn: conn,
    user: user,
    tournament: tournament
  } do
    resp = auth_conn |> get("/api/v1/tournaments/#{tournament.id}/my_match") |> json_response(404)
    assert resp["error"] == "no_current_match"

    opponent = AccountsFixtures.user_fixture()
    {:ok, _} = Tournaments.join_tournament(user, tournament)
    {:ok, _} = Tournaments.join_tournament(opponent, tournament)

    {:ok, tournament} =
      Tournaments.update_tournament(tournament, %{starts_at: DateTime.utc_now(:second)})

    tournament = Tournaments.advance_lifecycle(tournament)
    assert tournament.state == "running"

    resp = conn |> get("/api/v1/tournaments/#{tournament.id}/bracket") |> json_response(200)
    assert [%{"index" => 0, "size" => 2, "matches" => [match]}] = resp["data"]

    assert Enum.sort([match["a_leader_id"], match["b_leader_id"]]) ==
             Enum.sort([user.id, opponent.id])

    resp = auth_conn |> get("/api/v1/tournaments/#{tournament.id}/my_match") |> json_response(200)
    assert resp["data"]["id"] == match["id"]
    assert user.id in [resp["data"]["a_leader_id"], resp["data"]["b_leader_id"]]

    {:ok, _} = Tournaments.resolve_match(match["id"], match["a_entry_id"])

    resp = auth_conn |> get("/api/v1/tournaments/#{tournament.id}/my_match") |> json_response(404)
    assert resp["error"] == "no_current_match"

    resp = conn |> get("/api/v1/tournaments/#{tournament.id}/standings") |> json_response(200)
    assert [champion] = resp["data"]["champions"]
    assert champion["state"] == "winner"
    assert champion["id"] == match["a_entry_id"]

    assert [%{"placement" => 1, "entry_id" => winner}, %{"placement" => 2}] =
             resp["data"]["placements"]

    assert winner == champion["id"]
  end
end
