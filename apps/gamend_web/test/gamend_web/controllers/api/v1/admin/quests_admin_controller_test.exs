defmodule GamendWeb.Api.V1.Admin.QuestsAdminControllerTest do
  # Admin quests: definitions, per-user progress and the funnel. Every answer
  # here also passes `GamendWeb.ResponseContract`.
  use GamendWeb.ConnCase, async: false

  alias Gamend.Accounts
  alias Gamend.AccountsFixtures
  alias GamendWeb.Auth.Guardian

  setup %{conn: conn} do
    {:ok, admin} = Accounts.update_user(AccountsFixtures.user_fixture(), %{is_admin: true})
    {:ok, token, _} = Guardian.encode_and_sign(admin)

    %{
      admin_conn: put_req_header(conn, "authorization", "Bearer " <> token),
      player: AccountsFixtures.user_fixture(),
      key: "admin_q_#{System.unique_integer([:positive])}"
    }
  end

  defp create_quest(ctx, attrs \\ %{}) do
    body =
      ctx.admin_conn
      |> post(
        "/api/v1/admin/quests",
        Map.merge(
          %{
            key: ctx.key,
            title: "Win one",
            group_key: "starter",
            objectives: [%{event: "won", target: 1}],
            rewards: [%{type: "currency", code: "coins", amount: 3}]
          },
          attrs
        )
      )
      |> json_response(201)

    body["data"]
  end

  test "create, list, update and delete a definition", ctx do
    quest = create_quest(ctx)
    assert %{"key" => key, "group_key" => "starter", "active" => _} = quest
    assert key == ctx.key

    body = ctx.admin_conn |> get("/api/v1/admin/quests", %{search: ctx.key}) |> json_response(200)
    assert [%{"id" => id}] = body["data"]
    assert id == quest["id"]

    body =
      ctx.admin_conn
      |> patch("/api/v1/admin/quests/#{id}", %{title: "Win two"})
      |> json_response(200)

    assert body["data"]["title"] == "Win two"

    resp =
      ctx.admin_conn |> post("/api/v1/admin/quests", %{title: "no key"}) |> json_response(422)

    assert resp["error"] == "validation_failed"

    assert ctx.admin_conn |> delete("/api/v1/admin/quests/#{id}") |> json_response(200) ==
             %{"ok" => true}
  end

  # Was 422: a cap reached is a refusal, as `too_many_entries` is.
  test "a create past max_quests is 403 quest_limit_reached", ctx do
    previous = Application.get_env(:gamend_core, Gamend.Limits, [])
    Application.put_env(:gamend_core, Gamend.Limits, Keyword.put(previous, :max_quests, 0))
    on_exit(fn -> Application.put_env(:gamend_core, Gamend.Limits, previous) end)

    resp =
      ctx.admin_conn
      |> post("/api/v1/admin/quests", %{
        key: ctx.key,
        title: "Win one",
        objectives: [%{event: "won", target: 1}]
      })
      |> json_response(403)

    assert resp == %{"error" => "quest_limit_reached"}
  end

  test "a quest that is not there, or not completed, is refused by name", ctx do
    missing = %{user_id: ctx.player.id, key: "no_such_quest"}
    assert ctx.admin_conn |> post("/api/v1/admin/quests/grant", missing) |> json_response(404)
    assert ctx.admin_conn |> post("/api/v1/admin/quests/claim", missing) |> json_response(404)

    create_quest(ctx)

    assert ctx.admin_conn
           |> post("/api/v1/admin/quests/claim", %{user_id: ctx.player.id, key: ctx.key})
           |> json_response(403) == %{"error" => "not_completed"}
  end

  test "grant, claim, list progress, funnel and reset for a player", ctx do
    create_quest(ctx)
    body_params = %{user_id: ctx.player.id, key: ctx.key}

    body = ctx.admin_conn |> post("/api/v1/admin/quests/grant", body_params) |> json_response(200)
    assert body["data"]["status"] == "completed"

    resp = ctx.admin_conn |> post("/api/v1/admin/quests/grant", body_params) |> json_response(409)
    assert resp["error"] == "already_completed"

    body = ctx.admin_conn |> post("/api/v1/admin/quests/claim", body_params) |> json_response(200)
    assert body["data"]["progress"]["status"] == "claimed"
    assert [%{"code" => "coins", "amount" => 3}] = body["data"]["rewards"]

    body =
      ctx.admin_conn
      |> get("/api/v1/admin/quests/progress", %{quest_key: ctx.key})
      |> json_response(200)

    assert [%{"user_id" => user_id, "quest_key" => _}] = body["data"]
    assert user_id == ctx.player.id

    body = ctx.admin_conn |> get("/api/v1/admin/quests/#{ctx.key}/funnel") |> json_response(200)
    assert body["data"] == %{"claimed" => 1}

    assert ctx.admin_conn |> post("/api/v1/admin/quests/reset", body_params) |> json_response(200) ==
             %{"ok" => true}

    resp = ctx.admin_conn |> post("/api/v1/admin/quests/reset", body_params) |> json_response(404)
    assert resp["error"] == "no_progress"

    resp = ctx.admin_conn |> post("/api/v1/admin/quests/claim", %{}) |> json_response(400)
    assert resp["error"] == "missing_param"
  end
end
