defmodule GamendWeb.Api.V1.QuestRedeemControllerTest do
  # A player's redemption codes over the API. Every answer here also passes
  # `GamendWeb.ResponseContract`.
  use GamendWeb.ConnCase, async: false

  alias Gamend.Accounts
  alias Gamend.AccountsFixtures
  alias Gamend.Economy
  alias Gamend.Quests
  alias GamendWeb.Auth.Guardian

  defmodule VetoHook do
    use Gamend.TestSupport.NoopHooks

    @impl true
    def before_quest_claim(_user_id, _quest, _progress), do: {:error, "not during maintenance"}
  end

  defp auth_conn(conn, user) do
    {:ok, token, _} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer " <> token)
  end

  defp code_quest(attrs \\ %{}) do
    {:ok, quest} =
      Quests.create_quest(
        Map.merge(
          %{
            key: "code_#{System.unique_integer([:positive])}",
            title: "Spring gift",
            code_only: true,
            rewards: [%{type: "currency", code: "gold", amount: 100}]
          },
          attrs
        )
      )

    quest
  end

  defp code(quest, attrs \\ %{}) do
    {:ok, code} =
      Quests.create_code(
        quest,
        Map.merge(%{token: "T#{System.unique_integer([:positive])}"}, attrs)
      )

    code
  end

  defp redeem(conn, token), do: post(conn, "/api/v1/me/quests/redeem", %{token: token})

  describe "POST /api/v1/me/quests/redeem" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      %{user: user, authed: auth_conn(conn, user)}
    end

    test "answers what a claim answers, and pays", %{authed: authed, user: user} do
      code = code(code_quest())

      body = authed |> redeem(code.token) |> json_response(200)

      assert %{"progress" => %{"status" => "claimed"}, "rewards" => [%{"amount" => 100}]} =
               body["data"]

      assert Economy.balance(user.id, "gold") == 100
    end

    test "the token never comes back to a player", %{authed: authed} do
      code = code(code_quest())

      refute authed |> redeem(code.token) |> response(200) =~ code.token
    end

    test "404 for a code that does not work", %{authed: authed} do
      assert %{"error" => "code_not_found"} = authed |> redeem("nope") |> json_response(404)
    end

    test "409 for a quest the player already has", %{authed: authed} do
      code = code(code_quest())

      authed |> redeem(code.token) |> json_response(200)

      assert %{"error" => "already_redeemed"} =
               authed |> redeem(code.token) |> json_response(409)
    end

    test "403 with the hook's words, and the code is not spent", %{authed: authed} do
      code = code(code_quest())

      previous = Application.get_env(:gamend_core, :hooks_module)
      Application.put_env(:gamend_core, :hooks_module, VetoHook)
      on_exit(fn -> Application.put_env(:gamend_core, :hooks_module, previous) end)

      assert %{"error" => "rejected", "message" => "not during maintenance"} =
               authed |> redeem(code.token) |> json_response(403)

      assert Quests.get_code(code.id).uses == 0
    end

    test "403 for a guest where the host requires an account", %{conn: conn} do
      previous = Application.get_env(:gamend_core, Gamend.AccountRequired, [])
      Application.put_env(:gamend_core, Gamend.AccountRequired, [:quest_claims])
      on_exit(fn -> Application.put_env(:gamend_core, Gamend.AccountRequired, previous) end)

      {:ok, guest} = Accounts.find_or_create_from_device("redeem_#{System.unique_integer()}")

      assert %{"error" => "account_required"} =
               conn |> auth_conn(guest) |> redeem(code(code_quest()).token) |> json_response(403)
    end

    test "400 with no token", %{authed: authed} do
      assert %{"error" => "missing_param"} =
               authed |> post("/api/v1/me/quests/redeem", %{}) |> json_response(400)
    end

    test "401 signed out", %{conn: conn} do
      assert conn |> redeem("anything") |> json_response(401)
    end

    test "429 past the per-minute tries", %{authed: authed} do
      limiter = Application.get_env(:gamend_web, GamendWeb.Plugs.RateLimiter, [])
      limits = Application.get_env(:gamend_core, Gamend.Limits, [])

      Application.put_env(
        :gamend_web,
        GamendWeb.Plugs.RateLimiter,
        Keyword.put(limiter, :enabled, true)
      )

      Application.put_env(
        :gamend_core,
        Gamend.Limits,
        Keyword.put(limits, :max_redeem_attempts_per_min, 2)
      )

      on_exit(fn ->
        Application.put_env(:gamend_web, GamendWeb.Plugs.RateLimiter, limiter)
        Application.put_env(:gamend_core, Gamend.Limits, limits)
      end)

      assert authed |> redeem("nope") |> json_response(404)
      assert authed |> redeem("nope") |> json_response(404)
      assert %{"error" => "redeem_rate_limit"} = authed |> redeem("nope") |> json_response(429)
    end
  end

  describe "GET /api/v1/quests/redeemable" do
    test "lists the open ones signed out, and narrows to one", %{conn: conn} do
      quest = code_quest()
      code_quest()

      body = conn |> get("/api/v1/quests/redeemable") |> json_response(200)
      assert body["meta"]["total_count"] == 2
      assert Enum.all?(body["data"], & &1["code_only"])

      body = conn |> get("/api/v1/quests/redeemable?quest=#{quest.key}") |> json_response(200)
      assert [%{"key" => key, "progress" => nil}] = body["data"]
      assert key == quest.key
    end

    test "carries the caller's row once redeemed", %{conn: conn} do
      quest = code_quest()
      code = code(quest)
      user = AccountsFixtures.user_fixture()
      {:ok, _} = Quests.redeem_code(user.id, code.token)

      body = conn |> auth_conn(user) |> get("/api/v1/quests/redeemable") |> json_response(200)

      assert [%{"progress" => %{"status" => "claimed"}}] = body["data"]
    end
  end

  describe "the other quest lists" do
    test "the catalog leaves out code-only quests", %{conn: conn} do
      quest = code_quest()

      body = conn |> get("/api/v1/quests") |> json_response(200)

      refute Enum.any?(body["data"], &(&1["key"] == quest.key))
    end

    test "a player sees one only once redeemed", %{conn: conn} do
      quest = code_quest()
      code = code(quest)
      user = AccountsFixtures.user_fixture()
      authed = auth_conn(conn, user)

      before = authed |> get("/api/v1/me/quests") |> json_response(200)
      refute Enum.any?(before["data"], &(&1["key"] == quest.key))

      {:ok, _} = Quests.redeem_code(user.id, code.token)

      later = authed |> get("/api/v1/me/quests") |> json_response(200)
      assert %{"code_only" => true} = Enum.find(later["data"], &(&1["key"] == quest.key))
    end
  end
end
