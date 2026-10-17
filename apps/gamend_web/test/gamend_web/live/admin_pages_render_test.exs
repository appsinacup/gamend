defmodule GamendWeb.AdminPagesRenderTest do
  @moduledoc """
  Basic render + permission tests for admin LiveView pages
  (live_session :require_admin).
  Ensures unauthenticated and non-admin users are redirected,
  and admin users can render every page.
  Also verifies pages render correctly when data exists (catches
  struct field access errors in templates).
  """
  use GamendWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Repo

  @admin_routes [
    {"/admin", "Admin"},
    {"/admin/config", "Config"},
    {"/admin/runtime", "Runtime"},
    {"/admin/kv", "KV"},
    {"/admin/lobbies", "Lobbies"},
    {"/admin/leaderboards", "Leaderboards"},
    {"/admin/tournaments", "Tournaments"},
    {"/admin/matchmaking", "Matchmaking"},
    {"/admin/users", "Users"},
    {"/admin/sessions", "Sessions"},
    {"/admin/notifications", "Notifications"},
    {"/admin/push", "Push"},
    {"/admin/groups", "Groups"},
    {"/admin/parties", "Parties"},
    {"/admin/blacklist", "Blacklist"},
    {"/admin/friends", "Friends"},
    {"/admin/chat", "Chat"},
    {"/admin/chat/reports", "reports"},
    {"/admin/chat/mutes", "mutes"},
    {"/admin/chat/filter", "filter"},
    {"/admin/quests", "Quests"},
    {"/admin/payments", "Payments"},
    {"/admin/translations", "Translation"},
    {"/admin/lobby_snapshots", "Lobby snapshots"},
    {"/admin/retention", "Retention"},
    {"/admin/storage", "Storage"},
    {"/admin/economy", "Economy"},
    {"/admin/analytics", "Analytics"},
    {"/admin/settings", "Settings"},
    {"/admin/lobbies/live", "Lobbies"},
    {"/admin/reports", "Reports"},
    {"/admin/connections", "Connections"},
    {"/admin/rate_limiting", "Rate limiting"},
    {"/admin/logs", "Logs"},
    {"/admin/geo", "Geo"},
    {"/admin/system", "System"},
    {"/admin/analytics/features", "Features"},
    {"/admin/analytics/explore", "Explore"},
    {"/admin/analytics/people", "People"},
    {"/admin/analytics/counters", "Counters"},
    {"/admin/analytics/economy", "Economy"}
  ]

  defp create_admin(_context) do
    admin = AccountsFixtures.user_fixture()

    {:ok, admin} =
      admin
      |> User.admin_changeset(%{"is_admin" => true})
      |> Repo.update()

    %{admin: admin}
  end

  describe "unauthenticated users are redirected from all admin pages" do
    for {path, _label} <- @admin_routes do
      test "GET #{path} redirects unauthenticated", %{conn: conn} do
        assert {:error, {:redirect, _}} = live(conn, unquote(path))
      end
    end
  end

  describe "non-admin authenticated users are redirected from all admin pages" do
    setup do
      # Ensure a first user exists so the test user is not auto-promoted
      _first = AccountsFixtures.user_fixture()
      user = AccountsFixtures.user_fixture()
      assert user.is_admin == false
      %{user: user}
    end

    for {path, _label} <- @admin_routes do
      test "GET #{path} redirects non-admin user", %{conn: conn, user: user} do
        conn = log_in_user(conn, user)

        assert {:error, {:redirect, _}} = live(conn, unquote(path))
      end
    end
  end

  describe "admin users can render all admin pages" do
    setup [:create_admin]

    for {path, _label} <- @admin_routes do
      test "GET #{path} renders for admin", %{conn: conn, admin: admin} do
        {:ok, _view, _html} = conn |> log_in_user(admin) |> live(unquote(path))
      end
    end
  end

  describe "Oban Web dashboard (/admin/oban) is admin-gated" do
    test "redirects unauthenticated users", %{conn: conn} do
      assert {:error, {:redirect, _}} = live(conn, "/admin/oban")
    end

    test "redirects non-admin users", %{conn: conn} do
      _first = AccountsFixtures.user_fixture()
      user = AccountsFixtures.user_fixture()
      assert user.is_admin == false
      assert {:error, {:redirect, _}} = live(log_in_user(conn, user), "/admin/oban")
    end
  end

  # ---------------------------------------------------------------------------
  # Data-seeded render tests — catches struct field access errors in templates
  # ---------------------------------------------------------------------------

  @seeded_routes [
    {"/admin/lobbies", "Lobbies"},
    {"/admin/parties", "Parties"},
    {"/admin/blacklist", "Blacklist"},
    {"/admin/groups", "Groups"},
    {"/admin/leaderboards", "Leaderboards"},
    {"/admin/quests", "Quests"},
    {"/admin/payments", "Payments"},
    {"/admin/kv", "KV"},
    {"/admin/notifications", "Notifications"},
    {"/admin/users", "Users"},
    {"/admin/matchmaking", "Matchmaking"}
  ]

  defp seed_data(admin) do
    # Create a second user for relationships
    other = AccountsFixtures.user_fixture()

    # Lobby with a member
    {:ok, lobby} =
      Gamend.Lobbies.create_lobby(%{title: "Seeded Lobby", hostless: true, max_users: 10})

    # Ready check, so /admin/matchmaking renders its table rather than the empty
    # state. Opened over the hostless lobby: seating a member would fire the
    # join hooks asynchronously, and this file is async.
    {:ok, _check} = Gamend.ReadyChecks.open(lobby, [admin.id], opened_by: admin.id)

    # Group with a member
    {:ok, _group} =
      Gamend.Groups.create_group(admin.id, %{
        "title" => "Seeded Group",
        "type" => "public",
        "max_members" => 50
      })

    # Party (requires friendship for invite, so just create with leader)
    {:ok, _party} = Gamend.Parties.create_party(admin, %{max_size: 4})

    # Matchmaking ticket
    {:ok, _ticket} = Gamend.Matchmaking.join(other, %{"mode" => "seeded"})

    # Blacklist entry
    {:ok, _block} = Gamend.Friends.block_user(admin, other.id)

    # Leaderboard with a score
    {:ok, lb} =
      Gamend.Leaderboards.create_leaderboard(%{
        slug: "seeded_lb_#{System.unique_integer([:positive])}",
        title: "Seeded LB",
        sort_order: :desc,
        operator: :incr
      })

    Gamend.Leaderboards.submit_score(lb.id, admin.id, 100)

    # Quest (completed by the admin user)
    quest_key = "seeded_quest_#{System.unique_integer([:positive])}"

    {:ok, _quest} =
      Gamend.Quests.create_quest(%{
        key: quest_key,
        title: "Seeded Quest",
        kind: "achievement",
        auto_claim: true,
        objectives: [%{event: quest_key, target: 1}]
      })

    Gamend.Quests.admin_complete(admin.id, quest_key)

    # KV entry
    Gamend.KV.put("seeded:key", %{v: 1}, %{"meta" => "data"})

    # Payment data
    {:ok, product} =
      Gamend.Payments.create_product(%{
        "sku" => "seeded_pay_#{System.unique_integer([:positive])}",
        "title" => "Seeded Payment Product",
        "kind" => "consumable",
        "grant_config" => %{"hook_payload" => %{"coins" => 10}}
      })

    {:ok, provider_product} =
      Gamend.Payments.create_provider_product(%{
        "product_id" => product.id,
        "provider" => "stripe",
        "external_id" => "price_seeded_#{System.unique_integer([:positive])}",
        "currency" => "USD",
        "unit_amount" => 100
      })

    {:ok, purchase} = Gamend.Payments.create_purchase(admin, provider_product)
    Gamend.Payments.fulfill_purchase(purchase)

    # Notification
    Gamend.Notifications.admin_create_notification(admin.id, other.id, %{
      "title" => "Seeded Notification",
      "content" => "Test",
      "metadata" => %{"type" => "system"}
    })

    :ok
  end

  describe "admin pages render correctly with actual data" do
    setup [:create_admin]

    setup %{admin: admin} do
      seed_data(admin)
      :ok
    end

    for {path, label} <- @seeded_routes do
      test "GET #{path} renders with #{label} data", %{conn: conn, admin: admin} do
        {:ok, _view, _html} = conn |> log_in_user(admin) |> live(unquote(path))
      end
    end
  end
end
