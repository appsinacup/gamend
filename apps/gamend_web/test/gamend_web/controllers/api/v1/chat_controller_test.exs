defmodule GamendWeb.Api.V1.ChatControllerTest.VetoMessage do
  use Gamend.TestSupport.NoopHooks

  @impl true
  def before_chat_message(_user, _attrs), do: {:error, "No chat during the match"}
end

defmodule GamendWeb.Api.V1.ChatControllerTest do
  use GamendWeb.ConnCase

  alias Gamend.AccountsFixtures
  alias Gamend.Chat.Message
  alias Gamend.Groups
  alias Gamend.Repo
  alias Gamend.UUIDv7
  alias GamendWeb.Auth.Guardian

  defp auth_conn(conn, user) do
    {:ok, token, _} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer " <> token)
  end

  defp create_user, do: AccountsFixtures.user_fixture()

  defp insert_message(sender, chat_type, chat_ref_id, content) do
    %Message{sender_id: sender.id}
    |> Message.changeset(%{chat_type: chat_type, chat_ref_id: chat_ref_id, content: content})
    |> Repo.insert!()
  end

  describe "GET /api/v1/chat/messages" do
    test "lists messages for group members", %{conn: conn} do
      owner = create_user()
      member = create_user()

      {:ok, group} =
        Groups.create_group(owner.id, %{"title" => "member-chat", "type" => "public"})

      {:ok, _} = Groups.join_group(member.id, group.id)

      message = insert_message(owner, "group", group.id, "group secret")

      conn =
        conn
        |> auth_conn(member)
        |> get("/api/v1/chat/messages", %{chat_type: "group", chat_ref_id: group.id})

      assert %{"data" => [%{"id" => id}]} = json_response(conn, 200)
      assert id == message.id
    end

    test "rejects non-members", %{conn: conn} do
      owner = create_user()
      outsider = create_user()

      {:ok, group} =
        Groups.create_group(owner.id, %{"title" => "private-chat", "type" => "public"})

      _message = insert_message(owner, "group", group.id, "group secret")

      conn =
        conn
        |> auth_conn(outsider)
        |> get("/api/v1/chat/messages", %{chat_type: "group", chat_ref_id: group.id})

      assert %{"error" => "not_in_group"} = json_response(conn, 403)
    end
  end

  describe "a group conversation" do
    test "send, read one, edit, mark read, count unread and delete", %{conn: conn} do
      owner = create_user()
      member = create_user()
      {:ok, group} = Groups.create_group(owner.id, %{"title" => "flow-chat", "type" => "public"})
      {:ok, _} = Groups.join_group(member.id, group.id)
      where = %{chat_type: "group", chat_ref_id: group.id}

      sent =
        conn
        |> auth_conn(owner)
        |> post("/api/v1/chat/messages", Map.put(where, :content, "first"))
        |> json_response(201)
        |> Map.fetch!("data")

      assert conn |> auth_conn(member) |> get("/api/v1/chat/unread", where) |> json_response(200) ==
               %{"data" => %{"unread_count" => 1}}

      got =
        conn
        |> auth_conn(member)
        |> get("/api/v1/chat/messages/#{sent["id"]}")
        |> json_response(200)
        |> Map.fetch!("data")

      assert got["content"] == "first"

      edited =
        conn
        |> auth_conn(owner)
        |> patch("/api/v1/chat/messages/#{sent["id"]}", %{content: "edited"})
        |> json_response(200)
        |> Map.fetch!("data")

      assert edited["content"] == "edited"

      assert conn
             |> auth_conn(member)
             |> post("/api/v1/chat/read", Map.put(where, :message_id, sent["id"]))
             |> json_response(200)

      assert conn |> auth_conn(member) |> get("/api/v1/chat/unread", where) |> json_response(200) ==
               %{"data" => %{"unread_count" => 0}}

      assert conn
             |> auth_conn(owner)
             |> delete("/api/v1/chat/messages/#{sent["id"]}")
             |> json_response(200)

      assert conn
             |> auth_conn(member)
             |> get("/api/v1/chat/messages/#{sent["id"]}")
             |> json_response(404)
    end
  end

  describe "POST /api/v1/chat/read" do
    test "rejects message ids from another conversation", %{conn: conn} do
      owner = create_user()
      member = create_user()
      {:ok, group_a} = Groups.create_group(owner.id, %{"title" => "group-a", "type" => "public"})
      {:ok, group_b} = Groups.create_group(owner.id, %{"title" => "group-b", "type" => "public"})
      {:ok, _} = Groups.join_group(member.id, group_a.id)

      message_b = insert_message(owner, "group", group_b.id, "wrong group")

      conn =
        conn
        |> auth_conn(member)
        |> post("/api/v1/chat/read", %{
          chat_type: "group",
          chat_ref_id: group_a.id,
          message_id: message_b.id
        })

      assert %{"error" => "message_not_in_chat"} = json_response(conn, 422)
    end
  end

  describe "GET /api/v1/chat/unread" do
    test "rejects non-members", %{conn: conn} do
      owner = create_user()
      outsider = create_user()

      {:ok, group} =
        Groups.create_group(owner.id, %{"title" => "unread-chat", "type" => "public"})

      conn =
        conn
        |> auth_conn(outsider)
        |> get("/api/v1/chat/unread", %{chat_type: "group", chat_ref_id: group.id})

      assert %{"error" => "not_in_group"} = json_response(conn, 403)
    end
  end

  describe "the status follows the reason" do
    setup %{conn: conn} do
      owner = create_user()

      {:ok, group} =
        Groups.create_group(owner.id, %{"title" => "status-chat", "type" => "public"})

      %{owner: owner, group: group, owner_conn: auth_conn(conn, owner)}
    end

    test "a lobby or party the caller is not in answers 404", %{owner_conn: owner_conn} do
      elsewhere = UUIDv7.generate()

      assert %{"error" => "not_in_lobby"} =
               owner_conn
               |> post("/api/v1/chat/messages", %{
                 chat_type: "lobby",
                 chat_ref_id: elsewhere,
                 content: "hi"
               })
               |> json_response(404)

      assert %{"error" => "not_in_party"} =
               owner_conn
               |> post("/api/v1/chat/messages", %{
                 chat_type: "party",
                 chat_ref_id: elsewhere,
                 content: "hi"
               })
               |> json_response(404)

      assert %{"error" => "not_in_lobby"} =
               owner_conn
               |> get("/api/v1/chat/messages", %{chat_type: "lobby", chat_ref_id: elsewhere})
               |> json_response(404)

      assert %{"error" => "not_in_party"} =
               owner_conn
               |> get("/api/v1/chat/unread", %{chat_type: "party", chat_ref_id: elsewhere})
               |> json_response(404)
    end

    test "a game hook's veto answers 403 rejected with its words", ctx do
      previous = Application.get_env(:gamend_core, :hooks_module)

      Application.put_env(
        :gamend_core,
        :hooks_module,
        GamendWeb.Api.V1.ChatControllerTest.VetoMessage
      )

      on_exit(fn -> Application.put_env(:gamend_core, :hooks_module, previous) end)

      assert %{"error" => "rejected", "message" => "No chat during the match"} =
               ctx.owner_conn
               |> post("/api/v1/chat/messages", %{
                 chat_type: "group",
                 chat_ref_id: ctx.group.id,
                 content: "gg"
               })
               |> json_response(403)
    end

    test "a malformed chat id answers 400, not a crash", ctx do
      assert %{"error" => "invalid_chat_ref"} =
               ctx.owner_conn
               |> post("/api/v1/chat/messages", %{
                 chat_type: "group",
                 chat_ref_id: "not-an-id",
                 content: "hi"
               })
               |> json_response(400)

      assert %{"error" => "invalid_message"} =
               ctx.owner_conn
               |> post("/api/v1/chat/read", %{
                 chat_type: "group",
                 chat_ref_id: ctx.group.id,
                 message_id: "not-an-id"
               })
               |> json_response(400)
    end

    test "editing or deleting another player's message answers 403 forbidden", ctx do
      other = create_user()
      {:ok, _} = Groups.join_group(other.id, ctx.group.id)
      message = insert_message(other, "group", ctx.group.id, "theirs")

      assert %{"error" => "forbidden"} =
               ctx.owner_conn
               |> patch("/api/v1/chat/messages/#{message.id}", %{content: "mine now"})
               |> json_response(403)

      assert %{"error" => "forbidden"} =
               ctx.owner_conn
               |> delete("/api/v1/chat/messages/#{message.id}")
               |> json_response(403)
    end
  end
end
