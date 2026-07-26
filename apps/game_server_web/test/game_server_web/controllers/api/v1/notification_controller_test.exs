defmodule GameServerWeb.Api.V1.NotificationControllerTest do
  use GameServerWeb.ConnCase

  alias GameServer.AccountsFixtures
  alias GameServer.Friends
  alias GameServer.Notifications
  alias GameServerWeb.Auth.Guardian

  # Helper to create two users who are accepted friends
  defp make_friends do
    a = AccountsFixtures.user_fixture()
    b = AccountsFixtures.user_fixture()
    {:ok, f} = Friends.create_request(a.id, b.id)
    {:ok, _} = Friends.accept_friend_request(f.id, b)
    purge_notifications()
    {a, b}
  end

  # Friendship setup itself creates friend_request/friend_accepted
  # notifications; clear them so tests assert only on what they create.
  defp purge_notifications do
    GameServer.Repo.delete_all(GameServer.Notifications.Notification)
  end

  defp auth_conn(conn, user) do
    {:ok, token, _} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer " <> token)
  end

  # ── Send notification ──────────────────────────────────────────────────────

  test "POST /api/v1/notifications creates a notification to a friend", %{conn: conn} do
    {a, b} = make_friends()

    resp =
      conn
      |> auth_conn(a)
      |> post("/api/v1/notifications", %{user_id: b.id, title: "Hello!"})
      |> json_response(201)

    assert resp["title"] == "Hello!"
    assert resp["sender_id"] == a.id
    assert Map.has_key?(resp, "sender_name")
    assert resp["recipient_id"] == b.id
    assert is_binary(resp["id"])
  end

  test "POST /api/v1/notifications with content and metadata", %{conn: conn} do
    {a, b} = make_friends()

    resp =
      conn
      |> auth_conn(a)
      |> post("/api/v1/notifications", %{
        user_id: b.id,
        title: "Game invite",
        content: "Join my lobby!",
        metadata: %{"lobby_id" => 42}
      })
      |> json_response(201)

    assert resp["title"] == "Game invite"
    assert resp["content"] == "Join my lobby!"
    assert resp["metadata"]["lobby_id"] == 42
  end

  test "POST /api/v1/notifications fails when not friends", %{conn: conn} do
    a = AccountsFixtures.user_fixture()
    b = AccountsFixtures.user_fixture()

    resp =
      conn
      |> auth_conn(a)
      |> post("/api/v1/notifications", %{user_id: b.id, title: "Hi"})
      |> json_response(400)

    assert resp["error"] == "not_friends"
  end

  test "POST /api/v1/notifications fails without title", %{conn: conn} do
    {a, b} = make_friends()

    resp =
      conn
      |> auth_conn(a)
      |> post("/api/v1/notifications", %{user_id: b.id})
      |> json_response(422)

    assert resp["error"] == "validation_failed"
  end

  test "POST /api/v1/notifications fails without auth", %{conn: conn} do
    resp =
      conn
      |> post("/api/v1/notifications", %{user_id: 1, title: "Hi"})

    assert resp.status in [401, 403]
  end

  test "POST /api/v1/notifications upserts duplicate title from same sender to same recipient",
       %{conn: conn} do
    {a, b} = make_friends()

    first =
      conn
      |> auth_conn(a)
      |> post("/api/v1/notifications", %{user_id: b.id, title: "Invited to play", content: "v1"})
      |> json_response(201)

    second =
      conn
      |> auth_conn(a)
      |> post("/api/v1/notifications", %{user_id: b.id, title: "Invited to play", content: "v2"})
      |> json_response(201)

    # Upsert: same notification is updated in place
    assert second["title"] == "Invited to play"
    assert second["id"] == first["id"]
    assert second["content"] == "v2"
  end

  test "POST /api/v1/notifications fails when sending to self", %{conn: conn} do
    a = AccountsFixtures.user_fixture()

    resp =
      conn
      |> auth_conn(a)
      |> post("/api/v1/notifications", %{user_id: a.id, title: "Hi me"})
      |> json_response(400)

    assert resp["error"] == "cannot_notify_self"
  end

  # ── List notifications ─────────────────────────────────────────────────────

  test "GET /api/v1/notifications lists own notifications", %{conn: conn} do
    {a, b} = make_friends()

    # Send 3 notifications from a to b
    for i <- 1..3 do
      {:ok, _} =
        Notifications.send_notification(a.id, %{"user_id" => b.id, "title" => "Notif #{i}"})
    end

    resp =
      conn
      |> auth_conn(b)
      |> get("/api/v1/notifications")
      |> json_response(200)

    assert length(resp["data"]) == 3
    assert resp["meta"]["total_count"] == 3
    assert resp["meta"]["page"] == 1
    # Verify chronological order (oldest first)
    titles = Enum.map(resp["data"], & &1["title"])
    assert titles == ["Notif 1", "Notif 2", "Notif 3"]
  end

  test "GET /api/v1/notifications returns empty for new user", %{conn: conn} do
    user = AccountsFixtures.user_fixture()

    resp =
      conn
      |> auth_conn(user)
      |> get("/api/v1/notifications")
      |> json_response(200)

    assert resp["data"] == []
    assert resp["meta"]["total_count"] == 0
  end

  test "GET /api/v1/notifications supports pagination", %{conn: conn} do
    {a, b} = make_friends()

    for i <- 1..5 do
      {:ok, _} = Notifications.send_notification(a.id, %{"user_id" => b.id, "title" => "N#{i}"})
    end

    resp =
      conn
      |> auth_conn(b)
      |> get("/api/v1/notifications", %{page: 1, page_size: 2})
      |> json_response(200)

    assert length(resp["data"]) == 2
    assert resp["meta"]["total_count"] == 5
    assert resp["meta"]["total_pages"] == 3
    assert resp["meta"]["has_more"] == true

    # Page 3 should have 1 item
    resp2 =
      conn
      |> auth_conn(b)
      |> get("/api/v1/notifications", %{page: 3, page_size: 2})
      |> json_response(200)

    assert length(resp2["data"]) == 1
    assert resp2["meta"]["has_more"] == false
  end

  # ── Delete notifications ───────────────────────────────────────────────────

  test "DELETE /api/v1/notifications deletes by IDs", %{conn: conn} do
    {a, b} = make_friends()

    {:ok, n1} = Notifications.send_notification(a.id, %{"user_id" => b.id, "title" => "Del 1"})
    {:ok, n2} = Notifications.send_notification(a.id, %{"user_id" => b.id, "title" => "Del 2"})
    {:ok, n3} = Notifications.send_notification(a.id, %{"user_id" => b.id, "title" => "Keep"})

    resp =
      conn
      |> auth_conn(b)
      |> delete("/api/v1/notifications", %{ids: [n1.id, n2.id]})
      |> json_response(200)

    assert resp["data"]["deleted"] == 2

    # Only n3 should remain
    list =
      conn
      |> auth_conn(b)
      |> get("/api/v1/notifications")
      |> json_response(200)

    assert length(list["data"]) == 1
    assert hd(list["data"])["id"] == n3.id
  end

  test "DELETE /api/v1/notifications cannot delete other user's notifications", %{conn: conn} do
    {a, b} = make_friends()

    {:ok, n} = Notifications.send_notification(a.id, %{"user_id" => b.id, "title" => "Mine"})

    # a tries to delete b's notification
    resp =
      conn
      |> auth_conn(a)
      |> delete("/api/v1/notifications", %{ids: [n.id]})
      |> json_response(200)

    # Should delete 0 since a is not the recipient
    assert resp["data"]["deleted"] == 0

    # Notification should still exist for b
    assert Notifications.count_notifications(b.id) == 1
  end

  test "DELETE /api/v1/notifications with single id in array", %{conn: conn} do
    {a, b} = make_friends()

    {:ok, n} = Notifications.send_notification(a.id, %{"user_id" => b.id, "title" => "Single"})

    resp =
      conn
      |> auth_conn(b)
      |> delete("/api/v1/notifications", %{ids: [n.id]})
      |> json_response(200)

    assert resp["data"]["deleted"] == 1
  end

  test "DELETE /api/v1/notifications without ids returns error", %{conn: conn} do
    user = AccountsFixtures.user_fixture()

    resp =
      conn
      |> auth_conn(user)
      |> delete("/api/v1/notifications", %{})
      |> json_response(400)

    assert resp["error"] =~ "ids"
  end
end
