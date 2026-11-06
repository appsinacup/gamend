defmodule GamendWeb.Api.V1.Admin.LeaderboardsAdminControllerTest do
  use GamendWeb.ConnCase, async: false

  alias Gamend.Accounts
  alias GamendWeb.Auth.Guardian

  defp bearer_conn(conn, user) do
    {:ok, token, _} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer " <> token)
  end

  setup do
    user = Gamend.AccountsFixtures.user_fixture()
    {:ok, admin} = Accounts.update_user(user, %{is_admin: true})

    {:ok, admin: admin}
  end

  test "POST /api/v1/admin/leaderboards creates leaderboard", %{conn: conn, admin: admin} do
    conn = conn |> bearer_conn(admin)

    conn =
      post(conn, "/api/v1/admin/leaderboards", %{
        "slug" => "admin_test_lb",
        "title" => "Admin Test"
      })

    assert %{"data" => %{"id" => id, "slug" => "admin_test_lb", "is_active" => true}} =
             json_response(conn, 201)

    assert is_binary(id)
  end

  describe "leaderboard lifecycle and records" do
    setup %{conn: conn, admin: admin} do
      admin_conn = bearer_conn(conn, admin)

      body =
        admin_conn
        |> post("/api/v1/admin/leaderboards", %{
          slug: "admin_lb_#{System.unique_integer([:positive])}",
          title: "Admin board",
          operator: "set"
        })
        |> json_response(201)

      %{admin_conn: admin_conn, lb_id: body["data"]["id"]}
    end

    test "update, end and delete the board", %{admin_conn: admin_conn, lb_id: lb_id} do
      body =
        admin_conn
        |> patch("/api/v1/admin/leaderboards/#{lb_id}", %{title: "Renamed board"})
        |> json_response(200)

      assert body["data"]["title"] == "Renamed board"

      body = admin_conn |> post("/api/v1/admin/leaderboards/#{lb_id}/end") |> json_response(200)
      assert body["data"]["is_active"] == false

      assert admin_conn |> delete("/api/v1/admin/leaderboards/#{lb_id}") |> json_response(200) ==
               %{"ok" => true}
    end

    test "submit, update and delete records", %{admin_conn: admin_conn, lb_id: lb_id} do
      player = Gamend.AccountsFixtures.user_fixture()

      body =
        admin_conn
        |> post("/api/v1/admin/leaderboards/#{lb_id}/records", %{user_id: player.id, score: 10})
        |> json_response(200)

      assert %{"id" => record_id, "score" => 10, "label" => ""} = body["data"]

      body =
        admin_conn
        |> post("/api/v1/admin/leaderboards/#{lb_id}/records", %{label: "Team A", score: 7})
        |> json_response(200)

      # A label record has no user: `user_id` is empty, never null (R6).
      assert %{"label" => "Team A", "user_id" => ""} = body["data"]

      body =
        admin_conn
        |> patch("/api/v1/admin/leaderboards/#{lb_id}/records/#{record_id}", %{score: 12})
        |> json_response(200)

      assert body["data"]["score"] == 12

      assert admin_conn
             |> delete("/api/v1/admin/leaderboards/#{lb_id}/records/#{body["data"]["id"]}")
             |> json_response(200) == %{"ok" => true}

      assert admin_conn
             |> delete("/api/v1/admin/leaderboards/#{lb_id}/records/user/#{player.id}")
             |> json_response(200) == %{"ok" => true}

      resp =
        admin_conn
        |> post("/api/v1/admin/leaderboards/#{lb_id}/records", %{user_id: player.id, score: "x"})
        |> json_response(400)

      assert resp["error"] == "invalid_score"
    end

    # Was 400: an ended board refuses scores, like a closed registration.
    test "a score on an ended board is 403 leaderboard_ended", %{
      admin_conn: admin_conn,
      lb_id: lb_id
    } do
      player = Gamend.AccountsFixtures.user_fixture()
      admin_conn |> post("/api/v1/admin/leaderboards/#{lb_id}/end") |> json_response(200)

      for body <- [%{user_id: player.id, score: 1}, %{label: "Team A", score: 1}] do
        assert admin_conn
               |> post("/api/v1/admin/leaderboards/#{lb_id}/records", body)
               |> json_response(403) == %{"error" => "leaderboard_ended"}
      end
    end

    test "a score for a board or player that is not there is 404", %{
      admin_conn: admin_conn,
      lb_id: lb_id
    } do
      assert admin_conn
             |> post("/api/v1/admin/leaderboards/#{lb_id}/records", %{
               user_id: Ecto.UUID.generate(),
               score: 1
             })
             |> json_response(404) == %{"error" => "user_not_found"}

      assert admin_conn
             |> post("/api/v1/admin/leaderboards/#{Ecto.UUID.generate()}/records", %{
               label: "Team A",
               score: 1
             })
             |> json_response(404) == %{"error" => "leaderboard_not_found"}
    end

    test "updating or deleting a record that is not there is not_found", %{
      admin_conn: admin_conn,
      lb_id: lb_id
    } do
      for id <- [Ecto.UUID.generate(), "not-a-uuid"] do
        path = "/api/v1/admin/leaderboards/#{lb_id}/records/#{id}"

        assert admin_conn |> patch(path, %{score: 1}) |> json_response(404) ==
                 %{"error" => "not_found"}

        assert admin_conn |> delete(path) |> json_response(404) == %{"error" => "not_found"}
      end
    end
  end
end
