defmodule GamendWeb.Api.V1.Admin.TournamentsAdminControllerTest do
  use GamendWeb.ConnCase, async: false

  alias Gamend.Accounts
  alias Gamend.Tournaments
  alias GamendWeb.Auth.Guardian

  defp bearer_conn(conn, user) do
    {:ok, token, _} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer " <> token)
  end

  setup %{conn: conn} do
    user = Gamend.AccountsFixtures.user_fixture()
    {:ok, admin} = Accounts.update_user(user, %{is_admin: true})

    %{admin_conn: bearer_conn(conn, admin), admin: admin}
  end

  defp create_attrs do
    %{
      "slug" => "admin-cup-#{System.unique_integer([:positive])}",
      "title" => "Admin Cup",
      "starts_at" => DateTime.utc_now(:second) |> DateTime.add(3600) |> DateTime.to_iso8601(),
      "round_window_sec" => 600
    }
  end

  test "full admin lifecycle over HTTP: create, update, draw, resolve, finish", %{
    admin_conn: admin_conn
  } do
    resp = admin_conn |> post("/api/v1/admin/tournaments", create_attrs()) |> json_response(201)
    assert %{"id" => id, "state" => "scheduled"} = resp["data"]

    resp =
      admin_conn
      |> patch("/api/v1/admin/tournaments/#{id}", %{"title" => "Renamed"})
      |> json_response(200)

    assert resp["data"]["title"] == "Renamed"

    # Two entries so the draw produces a match.
    tournament = Tournaments.get_tournament(id)

    for _ <- 1..2 do
      {:ok, _} =
        Tournaments.join_tournament(
          Gamend.AccountsFixtures.user_fixture(),
          Tournaments.advance_lifecycle(tournament)
        )
    end

    resp = admin_conn |> post("/api/v1/admin/tournaments/#{id}/draw") |> json_response(200)
    assert resp["data"]["state"] == "running"

    [match] = Tournaments.list_matches(id)

    resp =
      admin_conn
      |> post("/api/v1/admin/tournaments/#{id}/matches/#{match.id}/resolve", %{
        "winner_entry_id" => match.a_entry_id
      })
      |> json_response(200)

    assert resp["data"]["winner_entry_id"] == match.a_entry_id
    assert resp["data"]["resolved_at"]

    # Champion decided -> the tournament already finished; finish is refused.
    resp = admin_conn |> post("/api/v1/admin/tournaments/#{id}/finish") |> json_response(403)
    assert resp["error"] == "not_running"

    assert Tournaments.get_tournament(id).state == "finished"
  end

  defmodule VetoingHook do
    def before_tournament_result(_match, _winner), do: {:error, :invalid_report}
  end

  # Was 403 with the hook's atom as the code (`invalid_report`): a veto is
  # `rejected`, its reason the message, as on every other endpoint.
  test "a before_tournament_result veto is 403 rejected", %{admin_conn: admin_conn} do
    resp = admin_conn |> post("/api/v1/admin/tournaments", create_attrs()) |> json_response(201)
    id = resp["data"]["id"]
    tournament = Tournaments.get_tournament(id)

    for _ <- 1..2 do
      {:ok, _} =
        Tournaments.join_tournament(
          Gamend.AccountsFixtures.user_fixture(),
          Tournaments.advance_lifecycle(tournament)
        )
    end

    _ = admin_conn |> post("/api/v1/admin/tournaments/#{id}/draw") |> json_response(200)
    [match] = Tournaments.list_matches(id)

    original = Application.get_env(:gamend_core, :hooks_module)
    Application.put_env(:gamend_core, :hooks_module, VetoingHook)

    on_exit(fn ->
      if original,
        do: Application.put_env(:gamend_core, :hooks_module, original),
        else: Application.delete_env(:gamend_core, :hooks_module)
    end)

    assert admin_conn
           |> post("/api/v1/admin/tournaments/#{id}/matches/#{match.id}/resolve", %{
             "winner_entry_id" => match.a_entry_id
           })
           |> json_response(403) == %{"error" => "rejected", "message" => ":invalid_report"}

    assert Tournaments.get_match(match.id).resolved_at == nil
  end

  test "resolve without a winner records a double forfeit", %{admin_conn: admin_conn} do
    resp = admin_conn |> post("/api/v1/admin/tournaments", create_attrs()) |> json_response(201)
    id = resp["data"]["id"]

    tournament = Tournaments.get_tournament(id)

    for _ <- 1..2 do
      {:ok, _} =
        Tournaments.join_tournament(
          Gamend.AccountsFixtures.user_fixture(),
          Tournaments.advance_lifecycle(tournament)
        )
    end

    _ = admin_conn |> post("/api/v1/admin/tournaments/#{id}/draw") |> json_response(200)
    [match] = Tournaments.list_matches(id)

    resp =
      admin_conn
      |> post("/api/v1/admin/tournaments/#{id}/matches/#{match.id}/resolve", %{})
      |> json_response(200)

    assert resp["data"]["winner_entry_id"] == ""

    resp =
      admin_conn
      |> post("/api/v1/admin/tournaments/#{id}/matches/#{match.id}/resolve", %{
        "winner_entry_id" => match.a_entry_id
      })
      |> json_response(409)

    assert resp["error"] == "already_resolved"
  end

  test "finish ends a running tournament early", %{admin_conn: admin_conn} do
    resp = admin_conn |> post("/api/v1/admin/tournaments", create_attrs()) |> json_response(201)
    id = resp["data"]["id"]
    tournament = Tournaments.get_tournament(id)

    for _ <- 1..2 do
      {:ok, _} =
        Tournaments.join_tournament(
          Gamend.AccountsFixtures.user_fixture(),
          Tournaments.advance_lifecycle(tournament)
        )
    end

    _ = admin_conn |> post("/api/v1/admin/tournaments/#{id}/draw") |> json_response(200)

    resp = admin_conn |> post("/api/v1/admin/tournaments/#{id}/finish") |> json_response(200)
    assert resp["data"]["state"] == "finished"
  end

  test "cancel and delete", %{admin_conn: admin_conn} do
    resp = admin_conn |> post("/api/v1/admin/tournaments", create_attrs()) |> json_response(201)
    id = resp["data"]["id"]

    resp = admin_conn |> post("/api/v1/admin/tournaments/#{id}/cancel") |> json_response(200)
    assert resp["data"]["state"] == "cancelled"

    resp = admin_conn |> delete("/api/v1/admin/tournaments/#{id}") |> json_response(200)
    assert resp == %{"ok" => true}
    assert Tournaments.get_tournament(id) == nil
  end

  test "cancel then reopen over HTTP", %{admin_conn: admin_conn} do
    resp = admin_conn |> post("/api/v1/admin/tournaments", create_attrs()) |> json_response(201)
    id = resp["data"]["id"]

    resp = admin_conn |> post("/api/v1/admin/tournaments/#{id}/cancel") |> json_response(200)
    assert resp["data"]["state"] == "cancelled"

    resp = admin_conn |> post("/api/v1/admin/tournaments/#{id}/reopen") |> json_response(200)
    assert resp["data"]["state"] == "registration"

    # reopening something that is not cancelled is rejected
    resp = admin_conn |> post("/api/v1/admin/tournaments/#{id}/reopen") |> json_response(403)
    assert resp["error"] == "not_cancelled"
  end

  test "validation errors surface as 422", %{admin_conn: admin_conn} do
    resp =
      admin_conn
      |> post("/api/v1/admin/tournaments", %{"slug" => "bad"})
      |> json_response(422)

    assert resp["error"] == "validation_failed"
    assert resp["errors"]["title"]
  end

  test "non-admins are rejected", %{conn: conn} do
    user = Gamend.AccountsFixtures.user_fixture()

    assert conn
           |> bearer_conn(user)
           |> post("/api/v1/admin/tournaments", create_attrs())
           |> response(403)
  end
end
