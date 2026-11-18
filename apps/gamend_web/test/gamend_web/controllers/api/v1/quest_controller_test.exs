defmodule GamendWeb.Api.V1.QuestControllerTest do
  use GamendWeb.ConnCase

  alias Gamend.AccountsFixtures
  alias Gamend.Quests
  alias GamendWeb.Auth.Guardian

  defp auth_conn(conn, user) do
    {:ok, token, _} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer " <> token)
  end

  defp create_quest(attrs) do
    defaults = %{
      key: "quest_#{System.unique_integer([:positive])}",
      title: "Test Quest",
      objectives: [%{event: "test_event", target: 1}]
    }

    {:ok, quest} = Quests.create_quest(Map.merge(defaults, attrs))
    quest
  end

  describe "GET /api/v1/me/quests reset cycles" do
    test "a repeat quest serializes its reset, so the SDK enum accepts it", %{conn: conn} do
      create_quest(%{key: "treasure_find", reset: "repeat", category: "treasure"})
      user = AccountsFixtures.user_fixture()

      body =
        conn
        |> auth_conn(user)
        |> get("/api/v1/me/quests")
        |> json_response(200)

      # The spec hardcoded the reset list in three places and missed "repeat";
      # a generated client then rejected the whole payload.
      assert Enum.find(body["data"], &(&1["key"] == "treasure_find"))["reset"] == "repeat"
    end
  end

  describe "the host's fields" do
    defmodule Host do
      @moduledoc false
      def action(nil, _quest), do: {"Look", "/catalog"}
      def action(_user_id, _quest), do: {"Play", "/games"}
      def note(_user_id, _quest), do: %{label: "Done in:", items: [%{name: "French", flag: "fr"}]}
      def lock(_user_id, %{key: "locked"}), do: "Pro"
      def lock(_user_id, _quest), do: nil
    end

    setup do
      create_quest(%{key: "open"})
      create_quest(%{key: "locked"})

      for {name, fun} <- [quest_action: :action, quest_note: :note, quest_lock_filter: :lock] do
        Application.put_env(:gamend_core, name, {Host, fun})
        on_exit(fn -> Application.delete_env(:gamend_core, name) end)
      end

      :ok
    end

    test "a reader gets where each quest is done, the host's note and its lock", %{conn: conn} do
      body =
        conn
        |> auth_conn(AccountsFixtures.user_fixture())
        |> get("/api/v1/me/quests")
        |> json_response(200)

      open = Enum.find(body["data"], &(&1["key"] == "open"))
      assert open["action"] == %{"label" => "Play", "path" => "/games"}

      assert open["note"] == %{
               "label" => "Done in:",
               "items" => [%{"title" => "French", "flag" => "fr"}]
             }

      assert open["lock"] == ""
      assert Enum.find(body["data"], &(&1["key"] == "locked"))["lock"] == "Pro"
    end

    test "a visitor gets the action for no one, and no note or lock", %{conn: conn} do
      body = conn |> get("/api/v1/quests") |> json_response(200)
      open = Enum.find(body["data"], &(&1["key"] == "open"))

      assert open["action"] == %{"label" => "Look", "path" => "/catalog"}
      assert open["note"] == nil
      assert open["lock"] == ""
    end

    test "with no host there is no action, note or lock", %{conn: conn} do
      for name <- [:quest_action, :quest_note, :quest_lock_filter],
          do: Application.delete_env(:gamend_core, name)

      body = conn |> get("/api/v1/quests") |> json_response(200)
      open = Enum.find(body["data"], &(&1["key"] == "open"))
      assert open["action"] == nil and open["note"] == nil and open["lock"] == ""
    end
  end

  describe "POST /api/v1/me/quests/:key/claim" do
    setup do
      quest =
        create_quest(%{
          key: "repeatable",
          reset: "repeat",
          objectives: [%{event: "found", target: 1}],
          rewards: [%{type: "currency", code: "coins", amount: 50}]
        })

      %{quest: quest, user: AccountsFixtures.user_fixture()}
    end

    test "claiming pays once and re-arms for the next run", %{conn: conn, user: user} do
      {:ok, _} = Quests.report_event(user.id, "found")

      first =
        conn
        |> auth_conn(user)
        |> post("/api/v1/me/quests/repeatable/claim")
        |> json_response(200)

      assert [%{"amount" => 50}] = first["data"]["rewards"]
      assert Gamend.Economy.balance(user.id, "coins") == 50

      # Re-armed: active again, and the second find pays a second time rather
      # than being swallowed as an already-used reward key.
      {:ok, _} = Quests.report_event(user.id, "found")

      conn
      |> auth_conn(user)
      |> post("/api/v1/me/quests/repeatable/claim")
      |> json_response(200)

      assert Gamend.Economy.balance(user.id, "coins") == 100
    end

    test "claim_count rides along so a repeat quest can show its run", %{conn: conn, user: user} do
      body =
        conn |> auth_conn(user) |> get("/api/v1/me/quests") |> json_response(200)

      # No progress row yet, so nothing to count from.
      assert Enum.find(body["data"], &(&1["key"] == "repeatable"))["progress"] == nil

      {:ok, _} = Quests.report_event(user.id, "found")
      conn |> auth_conn(user) |> post("/api/v1/me/quests/repeatable/claim") |> json_response(200)

      body = conn |> auth_conn(user) |> get("/api/v1/me/quests") |> json_response(200)
      entry = Enum.find(body["data"], &(&1["key"] == "repeatable"))

      # One finished run, re-armed for the next — which is what lets a client
      # show "1/2" instead of a bare 0/1 every time.
      assert entry["progress"]["claim_count"] == 1
      assert entry["progress"]["status"] == "active"
    end

    test "a second claim of the same run does not double-pay", %{conn: conn, user: user} do
      {:ok, _} = Quests.report_event(user.id, "found")

      conn |> auth_conn(user) |> post("/api/v1/me/quests/repeatable/claim") |> json_response(200)

      # Re-armed to active, so there is nothing completed to claim.
      resp =
        conn
        |> auth_conn(user)
        |> post("/api/v1/me/quests/repeatable/claim")
        |> json_response(403)

      assert resp["error"] == "not_completed"

      assert Gamend.Economy.balance(user.id, "coins") == 50
    end

    test "claiming a quest that was never completed is refused", %{conn: conn, user: user} do
      resp =
        conn
        |> auth_conn(user)
        |> post("/api/v1/me/quests/repeatable/claim")
        |> json_response(403)

      assert resp["error"] == "not_completed"

      assert Gamend.Economy.balance(user.id, "coins") == 0
    end
  end

  describe "public quest endpoints" do
    setup do
      quest =
        create_quest(%{
          key: "public_once",
          category: "achievement",
          objectives: [%{event: "won", target: 1}],
          rewards: [%{type: "currency", code: "coins", amount: 5}]
        })

      %{quest: quest, user: AccountsFixtures.user_fixture()}
    end

    test "the catalog is a page with no progress when signed out", %{conn: conn} do
      body = conn |> get("/api/v1/quests", %{page_size: 1}) |> json_response(200)

      assert [%{"progress" => nil, "claimable" => false}] = body["data"]
      assert body["meta"]["page_size"] == 1
      assert body["meta"]["total_count"] >= 1
    end

    test "stats are counters under data", %{conn: conn} do
      body = conn |> get("/api/v1/quests/stats") |> json_response(200)
      assert %{"quests_total" => _, "completed" => _, "claimed" => _} = body["data"]
    end

    test "a user's completions list what they finished", %{conn: conn, user: user} do
      {:ok, _} = Quests.report_event(user.id, "won")

      body = conn |> get("/api/v1/quests/user/#{user.id}") |> json_response(200)

      assert [%{"key" => "public_once", "progress" => %{"status" => "completed"}}] =
               body["data"]

      assert body["meta"]["total_count"] == 1

      resp = conn |> get("/api/v1/quests/user/not-a-uuid") |> json_response(400)
      assert resp["error"] == "invalid_id"
    end

    test "a claim answers not_found, then already_claimed", %{conn: conn, user: user} do
      resp =
        conn |> auth_conn(user) |> post("/api/v1/me/quests/no_such/claim") |> json_response(404)

      assert resp["error"] == "not_found"

      {:ok, _} = Quests.report_event(user.id, "won")

      body =
        conn
        |> auth_conn(user)
        |> post("/api/v1/me/quests/public_once/claim")
        |> json_response(200)

      assert body["data"]["rewards"] == [
               %{"type" => "currency", "code" => "coins", "amount" => 5}
             ]

      assert body["data"]["progress"]["status"] == "claimed"

      resp =
        conn
        |> auth_conn(user)
        |> post("/api/v1/me/quests/public_once/claim")
        |> json_response(409)

      assert resp["error"] == "already_claimed"
    end
  end

  describe "GET /api/v1/me/quests group collapsing" do
    setup do
      for id <- ["ro", "es", "pl"] do
        create_quest(%{
          key: "visit_#{id}",
          title: "Visit #{id}",
          group_key: "countries",
          group_title: "Visit countries",
          objectives: [%{event: "city_visited", target: 5, params: %{"country" => id}}]
        })
      end

      create_quest(%{key: "ungrouped", title: "Solo"})
      %{user: AccountsFixtures.user_fixture()}
    end

    test "a group is one row carrying its size and title", %{conn: conn, user: user} do
      body =
        conn
        |> auth_conn(user)
        |> get("/api/v1/me/quests")
        |> json_response(200)

      assert length(body["data"]) == 2, "three countries collapse to one row, plus the solo quest"
      assert body["meta"]["total_count"] == 2

      group = Enum.find(body["data"], &(&1["group_key"] == "countries"))
      assert group["group_size"] == 3
      assert group["group_title"] == "Visit countries"

      solo = Enum.find(body["data"], &(&1["key"] == "ungrouped"))
      assert solo["group_key"] == ""
      assert solo["group_size"] == 1
    end

    test "?group= opens that group into its members", %{conn: conn, user: user} do
      body =
        conn
        |> auth_conn(user)
        |> get("/api/v1/me/quests", %{group: "countries"})
        |> json_response(200)

      keys = Enum.map(body["data"], & &1["key"]) |> Enum.sort()
      assert keys == ["ungrouped", "visit_es", "visit_pl", "visit_ro"]
      assert body["meta"]["total_count"] == 4
    end

    test "an empty ?group= is no filter, not a group nothing matches", %{conn: conn, user: user} do
      body =
        conn
        |> auth_conn(user)
        |> get("/api/v1/me/quests", %{group: "", category: ""})
        |> json_response(200)

      assert length(body["data"]) == 2
    end
  end

  describe "GET /api/v1/me/quests category filter" do
    setup do
      daily = create_quest(%{category: "daily", reset: "daily"})
      achievement = create_quest(%{category: "achievement"})
      %{daily: daily, achievement: achievement, user: AccountsFixtures.user_fixture()}
    end

    test "an empty category lists every category, not none", ctx do
      # `?category=` is what a client asking for ALL quests sends: the generated
      # SDKs always include the param and default it to "". Treating that as a
      # literal category matched nothing and returned an empty list.
      resp =
        ctx.conn
        |> auth_conn(ctx.user)
        |> get("/api/v1/me/quests", %{category: "", page: 1, page_size: 100})
        |> json_response(200)

      keys = Enum.map(resp["data"], & &1["key"])
      assert ctx.daily.key in keys
      assert ctx.achievement.key in keys
      assert resp["meta"]["total_count"] == length(keys)
    end

    test "an omitted category lists every category", ctx do
      resp =
        ctx.conn
        |> auth_conn(ctx.user)
        |> get("/api/v1/me/quests")
        |> json_response(200)

      keys = Enum.map(resp["data"], & &1["key"])
      assert ctx.daily.key in keys
      assert ctx.achievement.key in keys
    end

    test "a named category still filters", ctx do
      resp =
        ctx.conn
        |> auth_conn(ctx.user)
        |> get("/api/v1/me/quests", %{category: "daily"})
        |> json_response(200)

      keys = Enum.map(resp["data"], & &1["key"])
      assert ctx.daily.key in keys
      refute ctx.achievement.key in keys
    end
  end
end
