defmodule GamendWeb.Api.V1.Admin.ChatAdminControllerTest do
  # Admin chat: messages, the report queue, mutes and the word filter. Every
  # answer here also passes `GamendWeb.ResponseContract`.
  use GamendWeb.ConnCase, async: false

  alias Gamend.Accounts
  alias Gamend.AccountsFixtures
  alias Gamend.Chat
  alias Gamend.Chat.FilterWord
  alias Gamend.Chat.Moderation
  alias Gamend.Chat.Reports
  alias Gamend.Groups
  alias Gamend.Repo
  alias GamendWeb.Auth.Guardian

  setup %{conn: conn} do
    {:ok, admin} = Accounts.update_user(AccountsFixtures.user_fixture(), %{is_admin: true})
    {:ok, token, _} = Guardian.encode_and_sign(admin)

    owner = AccountsFixtures.user_fixture()
    member = AccountsFixtures.user_fixture()

    {:ok, group} =
      Groups.create_group(owner.id, %{
        "title" => "admin-chat-#{System.unique_integer([:positive])}",
        "type" => "public"
      })

    {:ok, _} = Groups.join_group(member.id, group.id)

    {:ok, message} =
      Chat.send_message(%{user: owner}, %{
        "chat_type" => "group",
        "chat_ref_id" => group.id,
        "content" => "hello admins"
      })

    %{
      admin_conn: put_req_header(conn, "authorization", "Bearer " <> token),
      owner: owner,
      member: member,
      group: group,
      message: message
    }
  end

  describe "messages" do
    test "lists, deletes one, and clears a conversation", ctx do
      body =
        ctx.admin_conn
        |> get("/api/v1/admin/chat", %{chat_type: "group", chat_ref_id: ctx.group.id})
        |> json_response(200)

      assert [%{"id" => id, "sender_email" => _}] = body["data"]
      assert id == ctx.message.id
      assert body["meta"]["total_count"] == 1

      assert ctx.admin_conn |> delete("/api/v1/admin/chat/#{id}") |> json_response(200) ==
               %{"ok" => true}

      Chat.send_message(%{user: ctx.owner}, %{
        "chat_type" => "group",
        "chat_ref_id" => ctx.group.id,
        "content" => "again"
      })

      body =
        ctx.admin_conn
        |> delete("/api/v1/admin/chat/conversation", %{
          chat_type: "group",
          chat_ref_id: ctx.group.id
        })
        |> json_response(200)

      assert body == %{"data" => %{"deleted" => 1}}

      resp =
        ctx.admin_conn |> delete("/api/v1/admin/chat/conversation") |> json_response(400)

      assert resp["error"] == "missing_param"
    end
  end

  describe "reports" do
    test "list, resolve and delete", ctx do
      {:ok, report} = Reports.report_message(ctx.member.id, ctx.message.id, "rude")

      body = ctx.admin_conn |> get("/api/v1/admin/chat/reports") |> json_response(200)
      assert Enum.any?(body["data"], &(&1["id"] == report.id))

      body =
        ctx.admin_conn
        |> post("/api/v1/admin/chat/reports/#{report.id}/resolve", %{status: "dismissed"})
        |> json_response(200)

      assert body["data"]["status"] == "dismissed"
      assert body["data"]["resolved_by"] != ""

      resp =
        ctx.admin_conn
        |> post("/api/v1/admin/chat/reports/#{report.id}/resolve", %{status: "bogus"})
        |> json_response(400)

      assert resp["error"] == "invalid_status"

      assert ctx.admin_conn
             |> delete("/api/v1/admin/chat/reports/#{report.id}")
             |> json_response(200) == %{"ok" => true}

      resp =
        ctx.admin_conn |> delete("/api/v1/admin/chat/reports/#{report.id}") |> json_response(404)

      assert resp["error"] == "not_found"
    end
  end

  # A mute is a chat ban, on the bans API.
  describe "mutes" do
    test "create, list and lift", ctx do
      body =
        ctx.admin_conn
        |> post("/api/v1/admin/bans", %{kind: "chat", user_id: ctx.member.id, reason: "spam"})
        |> json_response(200)

      assert %{"scope" => "global", "user_id" => user_id, "id" => mute_id} = body["data"]
      assert user_id == ctx.member.id

      body =
        ctx.admin_conn
        |> get("/api/v1/admin/bans", %{kind: "chat", user_id: ctx.member.id})
        |> json_response(200)

      assert [%{"id" => ^mute_id, "user_name" => _}] = body["data"]

      assert %{"data" => %{"active" => false, "id" => ^mute_id}} =
               ctx.admin_conn
               |> delete("/api/v1/admin/bans/#{mute_id}")
               |> json_response(200)
    end
  end

  describe "word filter" do
    test "create, update, list, test and delete a word", ctx do
      word = "zorbl#{System.unique_integer([:positive])}"

      body =
        ctx.admin_conn
        |> post("/api/v1/admin/chat/filter_words", %{word: word, severity: "mask"})
        |> json_response(201)

      assert %{"id" => id, "severity" => "mask"} = body["data"]

      body =
        ctx.admin_conn
        |> patch("/api/v1/admin/chat/filter_words/#{id}", %{severity: "block"})
        |> json_response(200)

      assert body["data"]["severity"] == "block"

      body =
        ctx.admin_conn
        |> get("/api/v1/admin/chat/filter_words", %{severity: "block"})
        |> json_response(200)

      assert Enum.any?(body["data"], &(&1["id"] == id))
      refute Map.has_key?(body, "languages")

      body =
        ctx.admin_conn
        |> post("/api/v1/admin/chat/filter_words/test", %{phrase: "say #{word} now"})
        |> json_response(200)

      assert body["data"]["action"] == "block"
      assert [%{"severity" => "block"}] = body["data"]["hits"]

      assert ctx.admin_conn
             |> delete("/api/v1/admin/chat/filter_words/#{id}")
             |> json_response(200) == %{"ok" => true}
    end

    test "languages, import and removal by language", ctx do
      body =
        ctx.admin_conn |> get("/api/v1/admin/chat/filter_words/languages") |> json_response(200)

      assert "en" in body["data"]["languages"]

      body =
        ctx.admin_conn
        |> post("/api/v1/admin/chat/filter_words/import", %{lang: "en"})
        |> json_response(200)

      assert %{"imported" => imported} = body["data"]
      assert imported > 0

      resp =
        ctx.admin_conn
        |> post("/api/v1/admin/chat/filter_words/import", %{lang: "xx"})
        |> json_response(404)

      assert resp["error"] == "unknown_language"

      body =
        ctx.admin_conn
        |> delete("/api/v1/admin/chat/filter_words", %{lang: "en"})
        |> json_response(200)

      assert body == %{"data" => %{"deleted" => imported}}
      assert Moderation.count_filter_words(%{"lang" => "en"}) == 0

      resp = ctx.admin_conn |> delete("/api/v1/admin/chat/filter_words") |> json_response(400)
      assert resp["error"] == "missing_param"
    end

    test "the word cap answers 403 too_many_filter_words", ctx do
      previous = Application.get_env(:gamend_core, Gamend.Limits, [])
      on_exit(fn -> Application.put_env(:gamend_core, Gamend.Limits, previous) end)

      Application.put_env(
        :gamend_core,
        Gamend.Limits,
        Keyword.put(previous, :max_chat_filter_words, 1)
      )

      # Straight to the table, so no word reaches the node's matcher.
      %FilterWord{}
      |> FilterWord.changeset(%{"word" => "zorbl#{System.unique_integer([:positive])}"})
      |> Repo.insert!()

      resp =
        ctx.admin_conn
        |> post("/api/v1/admin/chat/filter_words", %{word: "one-too-many"})
        |> json_response(403)

      assert resp["error"] == "too_many_filter_words"

      resp =
        ctx.admin_conn
        |> post("/api/v1/admin/chat/filter_words/import", %{lang: "en"})
        |> json_response(403)

      assert resp["error"] == "too_many_filter_words"
    end
  end
end
