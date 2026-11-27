defmodule GamendWeb.Api.V1.NotificationControllerTest do
  use GamendWeb.ConnCase
  use Oban.Testing, repo: Gamend.Repo

  alias Gamend.AccountsFixtures
  alias Gamend.Friends
  alias Gamend.Notifications
  alias GamendWeb.Auth.Guardian

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
    Gamend.Repo.delete_all(Gamend.Notifications.Notification)
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
      |> Map.fetch!("data")

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
      |> Map.fetch!("data")

    assert resp["title"] == "Game invite"
    assert resp["content"] == "Join my lobby!"
    assert resp["metadata"]["lobby_id"] == 42
  end

  test "POST /api/v1/notifications cannot name the notice's group or send its email now", %{
    conn: conn
  } do
    {a, b} = make_friends()

    resp =
      conn
      |> auth_conn(a)
      |> post("/api/v1/notifications", %{
        user_id: b.id,
        title: "Your account",
        metadata: %{"group" => "account", "email_now" => true, "lobby_id" => "x"}
      })
      |> json_response(201)
      |> Map.fetch!("data")

    assert resp["metadata"] == %{"lobby_id" => "x"}

    [stored] = Notifications.list_recent_notifications(b.id, 10)
    assert stored.metadata == %{"lobby_id" => "x"}
    assert Notifications.group_of(stored) == nil
    assert [] == all_enqueued(worker: "GamendWeb.Workers.NotificationEmail")
  end

  test "POST /api/v1/notifications fails when not friends", %{conn: conn} do
    a = AccountsFixtures.user_fixture()
    b = AccountsFixtures.user_fixture()

    resp =
      conn
      |> auth_conn(a)
      |> post("/api/v1/notifications", %{user_id: b.id, title: "Hi"})
      |> json_response(403)

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

  test "POST /api/v1/notifications upserts duplicate title from same sender to same recipient",
       %{conn: conn} do
    {a, b} = make_friends()

    first =
      conn
      |> auth_conn(a)
      |> post("/api/v1/notifications", %{user_id: b.id, title: "Invited to play", content: "v1"})
      |> json_response(201)
      |> Map.fetch!("data")

    second =
      conn
      |> auth_conn(a)
      |> post("/api/v1/notifications", %{user_id: b.id, title: "Invited to play", content: "v2"})
      |> json_response(201)
      |> Map.fetch!("data")

    # Upsert: same notification is updated in place
    assert second["title"] == "Invited to play"
    assert second["id"] == first["id"]
    assert second["content"] == "v2"
  end

  test "POST /api/v1/notifications to a full inbox answers 403 too_many_notifications", %{
    conn: conn
  } do
    {a, b} = make_friends()
    previous = Application.get_env(:gamend_core, Gamend.Limits, [])
    on_exit(fn -> Application.put_env(:gamend_core, Gamend.Limits, previous) end)

    Application.put_env(
      :gamend_core,
      Gamend.Limits,
      Keyword.put(previous, :max_notifications_per_user, 0)
    )

    resp =
      conn
      |> auth_conn(a)
      |> post("/api/v1/notifications", %{user_id: b.id, title: "One more"})
      |> json_response(403)

    assert resp["error"] == "too_many_notifications"
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

  test "GET /api/v1/notifications says each notification's group", %{conn: conn} do
    {a, b} = make_friends()
    admin_send = &Notifications.admin_create_notification(a.id, b.id, &1)

    {:ok, _} = admin_send.(%{"title" => "Invite", "metadata" => %{"type" => "group_invite"}})
    {:ok, _} = admin_send.(%{"title" => "Plain"})

    groups =
      conn
      |> auth_conn(b)
      |> get("/api/v1/notifications")
      |> json_response(200)
      |> Map.fetch!("data")
      |> Map.new(&{&1["title"], &1["group"]})

    assert groups == %{"Invite" => "social", "Plain" => ""}
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

  test "GET /api/v1/notifications?sort_by=inserted_at lists the newest first", %{conn: conn} do
    {a, b} = make_friends()

    for i <- 1..3 do
      {:ok, _} = Notifications.send_notification(a.id, %{"user_id" => b.id, "title" => "N#{i}"})
    end

    titles = fn params ->
      conn
      |> auth_conn(b)
      |> get("/api/v1/notifications", params)
      |> json_response(200)
      |> Map.fetch!("data")
      |> Enum.map(& &1["title"])
    end

    assert titles.(%{}) == ["N1", "N2", "N3"]
    assert titles.(%{sort_by: "inserted_at_asc"}) == ["N1", "N2", "N3"]
    assert titles.(%{sort_by: "inserted_at"}) == ["N3", "N2", "N1"]
    assert titles.(%{sort_by: "inserted_at", page: 1, page_size: 2}) == ["N3", "N2"]

    assert conn
           |> auth_conn(b)
           |> get("/api/v1/notifications", %{sort_by: "title"})
           |> json_response(422)
  end

  # ── Delete notifications ───────────────────────────────────────────────────

  test "DELETE /api/v1/notifications/all deletes every one of the caller's and says the count",
       %{conn: conn} do
    {a, b} = make_friends()
    {:ok, _} = Notifications.send_notification(a.id, %{"user_id" => b.id, "title" => "One"})
    {:ok, _} = Notifications.send_notification(a.id, %{"user_id" => b.id, "title" => "Two"})
    {:ok, kept} = Notifications.send_notification(b.id, %{"user_id" => a.id, "title" => "Hers"})
    :ok = Notifications.subscribe(b.id)

    assert %{"data" => %{"deleted" => 2}} =
             conn
             |> auth_conn(b)
             |> delete("/api/v1/notifications/all")
             |> json_response(200)

    assert_receive {:notifications_read, %{ids: [], unread_count: 0}}
    assert Notifications.count_notifications(b.id) == 0
    assert [%{id: id}] = Notifications.list_notifications(a.id)
    assert id == kept.id

    assert %{"data" => %{"deleted" => 0}} =
             conn
             |> auth_conn(b)
             |> delete("/api/v1/notifications/all")
             |> json_response(200)

    assert conn |> delete("/api/v1/notifications/all") |> json_response(401)
  end

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

  test "DELETE /api/v1/notifications without ids returns error", %{conn: conn} do
    user = AccountsFixtures.user_fixture()

    resp =
      conn
      |> auth_conn(user)
      |> delete("/api/v1/notifications", %{})
      |> json_response(422)

    assert %{"error" => "validation_failed", "errors" => %{"ids" => [_]}} = resp
  end

  # ── Read state ─────────────────────────────────────────────────────────────

  test "POST /api/v1/notifications/read marks those ids read and tells the user's connections",
       %{conn: conn} do
    {a, b} = make_friends()
    {:ok, n1} = Notifications.send_notification(a.id, %{"user_id" => b.id, "title" => "One"})
    {:ok, n2} = Notifications.send_notification(a.id, %{"user_id" => b.id, "title" => "Two"})
    {:ok, other} = Notifications.send_notification(b.id, %{"user_id" => a.id, "title" => "Hi"})
    :ok = Notifications.subscribe(b.id)

    assert %{"data" => %{"marked" => 1, "unread_count" => 1}} =
             conn
             |> auth_conn(b)
             |> post("/api/v1/notifications/read", %{ids: [n1.id, other.id]})
             |> json_response(200)

    assert_receive {:notifications_read, %{ids: [id], unread_count: 1}}
    assert id == n1.id

    listed =
      conn
      |> auth_conn(b)
      |> get("/api/v1/notifications")
      |> json_response(200)
      |> Map.fetch!("data")
      |> Map.new(&{&1["id"], &1["read"]})

    assert listed == %{n1.id => true, n2.id => false}
    refute Gamend.Repo.get!(Gamend.Notifications.Notification, other.id).read

    # Read already: nothing marked, nothing said.
    assert %{"data" => %{"marked" => 0, "unread_count" => 1}} =
             conn
             |> auth_conn(b)
             |> post("/api/v1/notifications/read", %{ids: [n1.id]})
             |> json_response(200)

    refute_receive {:notifications_read, _}
  end

  test "POST /api/v1/notifications/read_all and GET /unread_count", %{conn: conn} do
    {a, b} = make_friends()
    {:ok, _} = Notifications.send_notification(a.id, %{"user_id" => b.id, "title" => "One"})
    {:ok, _} = Notifications.send_notification(a.id, %{"user_id" => b.id, "title" => "Two"})

    assert %{"data" => %{"unread_count" => 2}} =
             conn
             |> auth_conn(b)
             |> get("/api/v1/notifications/unread_count")
             |> json_response(200)

    :ok = Notifications.subscribe(b.id)

    assert %{"data" => %{"marked" => 2, "unread_count" => 0}} =
             conn
             |> auth_conn(b)
             |> post("/api/v1/notifications/read_all")
             |> json_response(200)

    assert_receive {:notifications_read, %{ids: ids, unread_count: 0}}
    assert length(ids) == 2

    assert %{"data" => %{"unread_count" => 0}} =
             conn
             |> auth_conn(b)
             |> get("/api/v1/notifications/unread_count")
             |> json_response(200)
  end

  test "the read routes need a signed-in user", %{conn: conn} do
    assert conn |> post("/api/v1/notifications/read_all") |> response(401)
    assert conn |> get("/api/v1/notifications/unread_count") |> response(401)
  end

  test "POST /api/v1/notifications/read refuses more ids than an inbox holds", %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    ids = for _ <- 0..Gamend.Limits.get(:max_notifications_per_user), do: Ecto.UUID.generate()

    assert %{"error" => "too_many_ids"} =
             conn
             |> auth_conn(user)
             |> post("/api/v1/notifications/read", %{ids: ids})
             |> json_response(400)
  end

  test "DELETE /api/v1/notifications of an unread one tells the user's connections the count",
       %{conn: conn} do
    {a, b} = make_friends()
    {:ok, unread} = Notifications.send_notification(a.id, %{"user_id" => b.id, "title" => "One"})
    {:ok, read} = Notifications.send_notification(a.id, %{"user_id" => b.id, "title" => "Two"})
    {1, 1} = Notifications.mark_notifications_read(b.id, [read.id])
    :ok = Notifications.subscribe(b.id)

    conn
    |> auth_conn(b)
    |> delete("/api/v1/notifications", %{ids: [read.id]})
    |> json_response(200)

    refute_receive {:notifications_read, _}, 50

    conn
    |> auth_conn(b)
    |> delete("/api/v1/notifications", %{ids: [unread.id]})
    |> json_response(200)

    assert_receive {:notifications_read, %{ids: [], unread_count: 0}}
  end
end
