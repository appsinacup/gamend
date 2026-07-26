defmodule GameServerWeb.Api.V1.PushTokenControllerTest do
  use GameServerWeb.ConnCase, async: true

  alias GameServer.Push
  alias GameServerWeb.Auth.Guardian

  setup %{conn: conn} do
    user = GameServer.AccountsFixtures.user_fixture()
    {:ok, token, _} = Guardian.encode_and_sign(user)
    %{conn: put_req_header(conn, "authorization", "Bearer " <> token), user: user}
  end

  test "requires auth" do
    assert json_response(get(build_conn(), "/api/v1/me/push_tokens"), 401)
  end

  test "POST /me/push_tokens registers a device", %{conn: conn, user: user} do
    body =
      conn
      |> post("/api/v1/me/push_tokens", %{
        token: "fcm-token-1",
        platform: "android",
        device_id: "pixel-9"
      })
      |> json_response(201)

    assert body["token"] == "fcm-token-1"
    assert body["platform"] == "android"
    assert body["provider"] == "fcm"
    assert body["device_id"] == "pixel-9"
    assert [_] = Push.list_tokens(user.id)
  end

  test "POST /me/push_tokens upserts by device_id", %{conn: conn, user: user} do
    first =
      conn
      |> post("/api/v1/me/push_tokens", %{token: "t1", platform: "ios", device_id: "iphone"})
      |> json_response(201)

    second =
      conn
      |> post("/api/v1/me/push_tokens", %{token: "t2", platform: "ios", device_id: "iphone"})
      |> json_response(201)

    assert first["id"] == second["id"]
    assert second["token"] == "t2"
    assert second["provider"] == "apns"
    assert Push.count_tokens(user.id) == 1
  end

  test "POST /me/push_tokens rejects a bad platform", %{conn: conn} do
    body =
      conn
      |> post("/api/v1/me/push_tokens", %{token: "t", platform: "gameboy"})
      |> json_response(422)

    assert body["error"] == "validation_failed"
    assert body["errors"]["platform"]
  end

  test "POST /me/push_tokens enforces the device cap", %{conn: conn} do
    max = GameServer.Limits.get(:max_push_tokens_per_user)

    for i <- 1..max do
      assert conn
             |> post("/api/v1/me/push_tokens", %{token: "cap-#{i}", platform: "android"})
             |> json_response(201)
    end

    assert %{"error" => "too_many_tokens"} =
             conn
             |> post("/api/v1/me/push_tokens", %{token: "cap-over", platform: "android"})
             |> json_response(400)
  end

  test "GET /me/push_tokens lists only my devices, paginated", %{conn: conn, user: user} do
    other = GameServer.AccountsFixtures.user_fixture()
    {:ok, _} = Push.register_token(other.id, %{"token" => "other-t", "platform" => "web"})

    for i <- 1..3 do
      {:ok, _} =
        Push.register_token(user.id, %{
          "token" => "mine-#{i}",
          "platform" => "android",
          "device_id" => "d#{i}"
        })
    end

    body = json_response(get(conn, "/api/v1/me/push_tokens?page_size=2"), 200)
    assert length(body["data"]) == 2
    assert body["meta"]["total_count"] == 3
    refute Enum.any?(body["data"], &(&1["token"] == "other-t"))
  end

  test "DELETE /me/push_tokens/:id removes my device only", %{conn: conn, user: user} do
    other = GameServer.AccountsFixtures.user_fixture()
    {:ok, other_token} = Push.register_token(other.id, %{"token" => "ot", "platform" => "web"})
    {:ok, mine} = Push.register_token(user.id, %{"token" => "mine", "platform" => "android"})

    assert %{"error" => "not_found"} =
             json_response(delete(conn, "/api/v1/me/push_tokens/#{other_token.id}"), 404)

    assert %{"id" => _} = json_response(delete(conn, "/api/v1/me/push_tokens/#{mine.id}"), 200)
    assert Push.count_tokens(user.id) == 0

    assert %{"error" => "not_found"} =
             json_response(delete(conn, "/api/v1/me/push_tokens/not-a-uuid"), 404)
  end
end
