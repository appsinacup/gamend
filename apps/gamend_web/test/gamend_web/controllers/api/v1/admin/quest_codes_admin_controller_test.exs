defmodule GamendWeb.Api.V1.Admin.QuestCodesAdminControllerTest do
  # The admin API for redemption codes: parity with `/admin/quests/:id/codes`.
  # Every answer here also passes `GamendWeb.ResponseContract`.
  use GamendWeb.ConnCase, async: false

  alias Gamend.Accounts
  alias Gamend.AccountsFixtures
  alias Gamend.Quests
  alias GamendWeb.Auth.Guardian

  setup %{conn: conn} do
    {:ok, admin} = Accounts.update_user(AccountsFixtures.user_fixture(), %{is_admin: true})
    {:ok, token, _} = Guardian.encode_and_sign(admin)
    admin_conn = put_req_header(conn, "authorization", "Bearer " <> token)

    body =
      admin_conn
      |> post("/api/v1/admin/quests", %{
        key: "codes_#{System.unique_integer([:positive])}",
        title: "Spring gift",
        code_only: true
      })
      |> json_response(201)

    assert body["data"]["code_only"] == true

    %{admin_conn: admin_conn, quest_id: body["data"]["id"], quest_key: body["data"]["key"]}
  end

  test "adds one code and lists it", ctx do
    created =
      ctx.admin_conn
      |> post("/api/v1/admin/quests/#{ctx.quest_id}/codes", %{
        token: "春节快乐",
        max_uses: 1000,
        metadata: %{source: "weibo"}
      })
      |> json_response(201)

    assert %{"token" => "春节快乐", "max_uses" => 1000, "uses" => 0, "status" => "active"} =
             created["data"]

    listed =
      ctx.admin_conn |> get("/api/v1/admin/quests/#{ctx.quest_id}/codes") |> json_response(200)

    assert [%{"token" => "春节快乐"}] = listed["data"]
    assert listed["meta"]["total_count"] == 1
  end

  test "a taken token is a conflict", ctx do
    path = "/api/v1/admin/quests/#{ctx.quest_id}/codes"

    ctx.admin_conn |> post(path, %{token: "ABC-123"}) |> json_response(201)

    assert ctx.admin_conn |> post(path, %{token: "abc 123"}) |> json_response(409)
  end

  test "null metadata and uses too big are validation failures", ctx do
    path = "/api/v1/admin/quests/#{ctx.quest_id}/codes"

    assert ctx.admin_conn |> post(path, %{token: "A", metadata: nil}) |> json_response(422)

    assert ctx.admin_conn
           |> post(path, %{token: "B", max_uses: 2_147_483_648})
           |> json_response(422)
  end

  test "a bad code is a validation failure", ctx do
    assert ctx.admin_conn
           |> post("/api/v1/admin/quests/#{ctx.quest_id}/codes", %{token: " - "})
           |> json_response(422)
  end

  test "a quest that is not code-only takes no codes", ctx do
    plain =
      ctx.admin_conn
      |> post("/api/v1/admin/quests", %{
        key: "plain_#{System.unique_integer([:positive])}",
        title: "Plain",
        objectives: [%{event: "won", target: 1}]
      })
      |> json_response(201)

    assert %{"error" => "not_code_only"} =
             ctx.admin_conn
             |> post("/api/v1/admin/quests/#{plain["data"]["id"]}/codes", %{token: "A"})
             |> json_response(422)

    assert %{"error" => "not_code_only"} =
             ctx.admin_conn
             |> post("/api/v1/admin/quests/#{plain["data"]["id"]}/codes/generate", %{count: 1})
             |> json_response(422)
  end

  test "generates, and answers how many", ctx do
    body =
      ctx.admin_conn
      |> post("/api/v1/admin/quests/#{ctx.quest_id}/codes/generate", %{count: 3, max_uses: nil})
      |> json_response(201)

    assert body["data"] == %{"created" => 3}
    assert Quests.count_codes(ctx.quest_key) == 3
    assert [%{max_uses: nil} | _] = Quests.list_codes(ctx.quest_key)
  end

  test "uses default to single-use", ctx do
    ctx.admin_conn
    |> post("/api/v1/admin/quests/#{ctx.quest_id}/codes/generate", %{count: 1})
    |> json_response(201)

    assert [%{max_uses: 1}] = Quests.list_codes(ctx.quest_key)
  end

  test "generate refuses a bad count or too many", ctx do
    path = "/api/v1/admin/quests/#{ctx.quest_id}/codes/generate"

    assert %{"error" => "invalid_count"} =
             ctx.admin_conn |> post(path, %{}) |> json_response(400)

    assert %{"error" => "too_many_codes"} =
             ctx.admin_conn |> post(path, %{count: 10_001}) |> json_response(403)
  end

  test "searches for an exact code", ctx do
    path = "/api/v1/admin/quests/#{ctx.quest_id}/codes"

    ctx.admin_conn |> post(path, %{token: "ABC-123"}) |> json_response(201)
    ctx.admin_conn |> post(path, %{token: "ABC-1234"}) |> json_response(201)

    body = ctx.admin_conn |> get(path, %{search: "abc123"}) |> json_response(200)

    assert [%{"token" => "ABC-123"}] = body["data"]
    assert body["meta"]["total_count"] == 1
  end

  test "revokes and restores", ctx do
    created =
      ctx.admin_conn
      |> post("/api/v1/admin/quests/#{ctx.quest_id}/codes", %{token: "STOP"})
      |> json_response(201)

    path = "/api/v1/admin/quest_codes/#{created["data"]["id"]}"

    assert %{"data" => %{"status" => "revoked"}} =
             ctx.admin_conn |> patch(path, %{status: "revoked"}) |> json_response(200)

    assert {:error, :code_not_found} =
             Quests.redeem_code(AccountsFixtures.user_fixture().id, "STOP")

    assert %{"data" => %{"status" => "active"}} =
             ctx.admin_conn |> patch(path, %{status: "active"}) |> json_response(200)
  end

  test "patch refuses an unknown status or code", ctx do
    created =
      ctx.admin_conn
      |> post("/api/v1/admin/quests/#{ctx.quest_id}/codes", %{token: "STAY"})
      |> json_response(201)

    assert %{"error" => "invalid_state"} =
             ctx.admin_conn
             |> patch("/api/v1/admin/quest_codes/#{created["data"]["id"]}", %{status: "nope"})
             |> json_response(422)

    for id <- [Gamend.UUIDv7.generate(), "not-a-uuid"] do
      assert %{"error" => "code_not_found"} =
               ctx.admin_conn
               |> patch("/api/v1/admin/quest_codes/#{id}", %{status: "revoked"})
               |> json_response(404)
    end
  end

  test "404 for a quest that is not there", ctx do
    path = "/api/v1/admin/quests/#{Gamend.UUIDv7.generate()}/codes"

    assert ctx.admin_conn |> get(path) |> json_response(404)
    assert ctx.admin_conn |> post(path, %{token: "A"}) |> json_response(404)
    assert ctx.admin_conn |> post(path <> "/generate", %{count: 1}) |> json_response(404)
  end

  test "a player cannot reach any of it", %{conn: conn, quest_id: quest_id} do
    {:ok, token, _} = Guardian.encode_and_sign(AccountsFixtures.user_fixture())
    player = put_req_header(conn, "authorization", "Bearer " <> token)

    assert player |> get("/api/v1/admin/quests/#{quest_id}/codes") |> json_response(403)
  end
end
