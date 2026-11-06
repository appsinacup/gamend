defmodule GamendWeb.Api.V1.Admin.NotificationControllerTest do
  use GamendWeb.ConnCase, async: false

  alias Gamend.Accounts
  alias Gamend.AccountsFixtures
  alias Gamend.Notifications
  alias GamendWeb.Auth.Guardian

  defp bearer_conn(conn, user) do
    {:ok, token, _} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer " <> token)
  end

  defp admin_setup do
    user = AccountsFixtures.user_fixture()
    {:ok, admin} = Accounts.update_user(user, %{is_admin: true})
    admin
  end

  setup do
    admin = admin_setup()
    {:ok, admin: admin}
  end

  # ── List (index) ───────────────────────────────────────────────────────────

  test "GET /api/v1/admin/notifications lists all notifications", %{conn: conn, admin: admin} do
    sender = AccountsFixtures.user_fixture()
    recipient = AccountsFixtures.user_fixture()

    {:ok, _} =
      Notifications.admin_create_notification(sender.id, recipient.id, %{
        "title" => "Admin test 1"
      })

    {:ok, _} =
      Notifications.admin_create_notification(sender.id, recipient.id, %{
        "title" => "Admin test 2"
      })

    resp =
      conn
      |> bearer_conn(admin)
      |> get("/api/v1/admin/notifications")
      |> json_response(200)

    assert length(resp["data"]) >= 2
    assert resp["meta"]["total_count"] >= 2
    assert resp["meta"]["page"] == 1
  end

  test "GET /api/v1/admin/notifications filters by user_id (recipient)", %{
    conn: conn,
    admin: admin
  } do
    sender = AccountsFixtures.user_fixture()
    r1 = AccountsFixtures.user_fixture()
    r2 = AccountsFixtures.user_fixture()

    {:ok, _} =
      Notifications.admin_create_notification(sender.id, r1.id, %{"title" => "For r1"})

    {:ok, _} =
      Notifications.admin_create_notification(sender.id, r2.id, %{"title" => "For r2"})

    resp =
      conn
      |> bearer_conn(admin)
      |> get("/api/v1/admin/notifications", %{user_id: r1.id})
      |> json_response(200)

    assert Enum.all?(resp["data"], fn n -> n["recipient_id"] == r1.id end)
    assert resp["meta"]["total_count"] >= 1
  end

  test "GET /api/v1/admin/notifications filters by sender_id", %{conn: conn, admin: admin} do
    s1 = AccountsFixtures.user_fixture()
    s2 = AccountsFixtures.user_fixture()
    recipient = AccountsFixtures.user_fixture()

    {:ok, _} =
      Notifications.admin_create_notification(s1.id, recipient.id, %{"title" => "From s1"})

    {:ok, _} =
      Notifications.admin_create_notification(s2.id, recipient.id, %{"title" => "From s2"})

    resp =
      conn
      |> bearer_conn(admin)
      |> get("/api/v1/admin/notifications", %{sender_id: s1.id})
      |> json_response(200)

    assert Enum.all?(resp["data"], fn n -> n["sender_id"] == s1.id end)
  end

  test "GET /api/v1/admin/notifications filters by title", %{conn: conn, admin: admin} do
    sender = AccountsFixtures.user_fixture()
    recipient = AccountsFixtures.user_fixture()

    {:ok, _} =
      Notifications.admin_create_notification(sender.id, recipient.id, %{
        "title" => "Unique Alpha"
      })

    {:ok, _} =
      Notifications.admin_create_notification(sender.id, recipient.id, %{
        "title" => "Unique Beta"
      })

    resp =
      conn
      |> bearer_conn(admin)
      |> get("/api/v1/admin/notifications", %{title: "Alpha"})
      |> json_response(200)

    assert resp["data"] != []
    assert Enum.all?(resp["data"], fn n -> String.contains?(n["title"], "Alpha") end)
  end

  test "GET /api/v1/admin/notifications supports pagination", %{conn: conn, admin: admin} do
    sender = AccountsFixtures.user_fixture()
    recipient = AccountsFixtures.user_fixture()

    for i <- 1..5 do
      {:ok, _} =
        Notifications.admin_create_notification(sender.id, recipient.id, %{
          "title" => "Paged #{i}"
        })
    end

    resp =
      conn
      |> bearer_conn(admin)
      |> get("/api/v1/admin/notifications", %{
        user_id: recipient.id,
        page: 1,
        page_size: 2
      })
      |> json_response(200)

    assert length(resp["data"]) == 2
    assert resp["meta"]["total_count"] == 5
    assert resp["meta"]["total_pages"] == 3
    assert resp["meta"]["has_more"] == true
  end

  # ── Create ─────────────────────────────────────────────────────────────────

  test "POST /api/v1/admin/notifications creates a notification (no friendship needed)", %{
    conn: conn,
    admin: admin
  } do
    sender = AccountsFixtures.user_fixture()
    recipient = AccountsFixtures.user_fixture()

    resp =
      conn
      |> bearer_conn(admin)
      |> post("/api/v1/admin/notifications", %{
        sender_id: sender.id,
        recipient_id: recipient.id,
        title: "Admin created",
        content: "System message",
        metadata: %{"priority" => "high"}
      })
      |> json_response(201)
      |> Map.fetch!("data")

    assert resp["title"] == "Admin created"
    assert resp["content"] == "System message"
    assert resp["metadata"]["priority"] == "high"
    assert resp["sender_id"] == sender.id
    assert resp["recipient_id"] == recipient.id
  end

  test "POST /api/v1/admin/notifications fails without title", %{conn: conn, admin: admin} do
    sender = AccountsFixtures.user_fixture()
    recipient = AccountsFixtures.user_fixture()

    resp =
      conn
      |> bearer_conn(admin)
      |> post("/api/v1/admin/notifications", %{
        sender_id: sender.id,
        recipient_id: recipient.id
      })
      |> json_response(422)

    assert resp["error"] == "validation_failed"
  end

  test "POST /api/v1/admin/notifications fails without sender_id or recipient_id", %{
    conn: conn,
    admin: admin
  } do
    resp =
      conn
      |> bearer_conn(admin)
      |> post("/api/v1/admin/notifications", %{title: "No recipient"})
      |> json_response(400)

    assert resp["error"] == "missing_param"
    assert resp["message"] =~ "sender_id"
  end

  test "POST /api/v1/admin/notifications upserts duplicate title for same sender and recipient",
       %{
         conn: conn,
         admin: admin
       } do
    sender = AccountsFixtures.user_fixture()
    recipient = AccountsFixtures.user_fixture()

    first =
      conn
      |> bearer_conn(admin)
      |> post("/api/v1/admin/notifications", %{
        sender_id: sender.id,
        recipient_id: recipient.id,
        title: "Invited to play",
        content: "v1"
      })
      |> json_response(201)
      |> Map.fetch!("data")

    second =
      conn
      |> bearer_conn(admin)
      |> post("/api/v1/admin/notifications", %{
        sender_id: sender.id,
        recipient_id: recipient.id,
        title: "Invited to play",
        content: "v2"
      })
      |> json_response(201)
      |> Map.fetch!("data")

    # Upsert: same notification is updated in place
    assert second["title"] == "Invited to play"
    assert second["id"] == first["id"]
    assert second["content"] == "v2"
  end

  # ── Delete ─────────────────────────────────────────────────────────────────

  test "DELETE /api/v1/admin/notifications/:id deletes a notification", %{
    conn: conn,
    admin: admin
  } do
    sender = AccountsFixtures.user_fixture()
    recipient = AccountsFixtures.user_fixture()

    {:ok, n} =
      Notifications.admin_create_notification(sender.id, recipient.id, %{
        "title" => "To delete"
      })

    conn
    |> bearer_conn(admin)
    |> delete("/api/v1/admin/notifications/#{n.id}")
    |> json_response(200)

    # Confirm it's gone
    assert Notifications.get_notification(n.id) == nil
  end

  test "DELETE /api/v1/admin/notifications/:id returns 404 for unknown id", %{
    conn: conn,
    admin: admin
  } do
    resp =
      conn
      |> bearer_conn(admin)
      |> delete("/api/v1/admin/notifications/00000000-0000-0000-0000-000000000000")
      |> json_response(404)

    assert resp["error"] == "not_found"
  end

  test "DELETE /api/v1/admin/notifications/:id answers 400 for an id that is not one", %{
    conn: conn,
    admin: admin
  } do
    resp =
      conn
      |> bearer_conn(admin)
      |> delete("/api/v1/admin/notifications/not-an-id")
      |> json_response(400)

    assert resp["error"] == "invalid_id"
  end

  # ── Auth ───────────────────────────────────────────────────────────────────

  test "non-admin user cannot access admin notifications", %{conn: conn} do
    user = AccountsFixtures.user_fixture()

    resp =
      conn
      |> bearer_conn(user)
      |> get("/api/v1/admin/notifications")

    assert resp.status in [401, 403]
  end

  test "unauthenticated request is rejected", %{conn: conn} do
    resp = get(conn, "/api/v1/admin/notifications")
    assert resp.status in [401, 403]
  end
end
