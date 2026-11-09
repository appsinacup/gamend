defmodule GamendWeb.LeftOutPagesTest do
  @moduledoc """
  A host leaves a page out of its router (`except:`): the page is not found,
  every link to it goes, and the API the game uses stays.
  """
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gamend.AccountsFixtures
  alias Gamend.Theme.JSONConfig
  alias GamendWeb.Auth.Guardian
  alias GamendWeb.Features
  alias GamendWeb.HostLayouts
  alias GamendWeb.MountedRoutes
  alias GamendWeb.Router.Shared
  alias GamendWeb.SmallRouter

  setup do
    previous = Application.get_env(:gamend_web, :router)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:gamend_web, :router, previous),
        else: Application.delete_env(:gamend_web, :router)
    end)

    :ok
  end

  defp leave_out, do: Application.put_env(:gamend_web, :router, SmallRouter)

  describe "MountedRoutes" do
    test "answers from the router the endpoint dispatches to" do
      assert MountedRoutes.mounted?("/chat")
      assert MountedRoutes.settings_tab?("friends")

      leave_out()

      refute MountedRoutes.mounted?("/chat")
      assert MountedRoutes.mounted?("/quests")
      refute MountedRoutes.settings_tab?("friends")
      refute MountedRoutes.settings_tab?("groups")
      assert MountedRoutes.settings_tab?("wallet")
    end
  end

  describe "the build" do
    test "an unknown name in except: fails it" do
      assert_raise ArgumentError, ~r/except: takes a literal list/, fn ->
        Code.eval_string("""
        defmodule GamendWeb.LeftOutPagesTest.TypoRouter do
          use GamendWeb, :router
          import GamendWeb.Router.Shared
          gamend_current_user_routes([], except: [:gruops])
        end
        """)
      end
    end

    test "a flag that became a router option, still set false, fails it" do
      previous = Application.get_env(:gamend_web, Features)

      on_exit(fn ->
        if previous,
          do: Application.put_env(:gamend_web, Features, previous),
          else: Application.delete_env(:gamend_web, Features)
      end)

      Application.put_env(:gamend_web, Features, web_store: false, list_quests: false)
      assert_raise ArgumentError, ~r/\[:web_store\]/, &Shared.refuse_moved_flags!/0

      Application.put_env(:gamend_web, Features, web_friends: true, list_quests: false)
      assert Shared.refuse_moved_flags!() == :ok
    end
  end

  describe "core's default links" do
    setup do
      original = Gamend.SettingsHelpers.get(:gamend_core, Gamend.ContentSettings, :theme_config)
      path = Path.join(System.tmp_dir!(), "bare_#{System.unique_integer([:positive])}.json")
      File.write!(path, Jason.encode!(%{"title" => "Bare"}))
      Gamend.SettingsHelpers.put(:gamend_core, Gamend.ContentSettings, :theme_config, path)
      JSONConfig.reload()

      on_exit(fn ->
        File.rm(path)

        if original,
          do:
            Gamend.SettingsHelpers.put(
              :gamend_core,
              Gamend.ContentSettings,
              :theme_config,
              original
            ),
          else: Gamend.SettingsHelpers.delete(:gamend_core, Gamend.ContentSettings, :theme_config)

        JSONConfig.reload()
      end)

      :ok
    end

    defp primary_hrefs do
      HostLayouts.navigation()["primary_links"]
      |> Enum.flat_map(&[&1 | List.wrap(&1["items"])])
      |> Enum.map(& &1["href"])
    end

    test "go with the page" do
      assert ["/play", "/tournaments", "/groups"] -- primary_hrefs() == []

      leave_out()
      hrefs = primary_hrefs()

      assert "/quests" in hrefs
      refute "/play" in hrefs
      refute "/tournaments" in hrefs
      refute "/groups" in hrefs
    end
  end

  describe "a page left out" do
    setup :register_and_log_in_user

    test "is not found", %{conn: conn} do
      leave_out()

      for path <- ~w(/chat /store /store/success /groups /groups/1 /tournaments /redeem /report
                     /play /users/groups/join/abc) do
        assert conn |> get(path) |> html_response(404), path
      end
    end

    test "loses its links in the menu and on settings", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/users/settings")
      assert has_element?(view, ~s(a[href="/chat"]))
      assert has_element?(view, ~s([phx-value-tab="groups"]))

      leave_out()

      {:ok, view, _html} = live(conn, "/users/settings?tab=groups")
      refute has_element?(view, ~s(a[href="/chat"]))
      refute has_element?(view, ~s([phx-value-tab="groups"]))
      refute has_element?(view, ~s(a[href="/groups"]))
      # `?tab=groups` falls back to the account tab instead of a blank page.
      assert has_element?(view, ~s([phx-value-tab="account"]))
    end

    test "a chat notification keeps its row and loses its button", %{conn: conn, user: user} do
      sender = AccountsFixtures.user_fixture()

      {:ok, _} =
        Gamend.Notifications.admin_create_notification(sender.id, user.id, %{
          "title" => "New message",
          "metadata" => %{"type" => "chat_friend", "friend_id" => sender.id}
        })

      {:ok, view, _html} = live(conn, "/notifications")
      assert has_element?(view, ~s(a[href^="/chat?"]))

      leave_out()

      {:ok, view, html} = live(conn, "/notifications")
      assert html =~ "New message"
      refute has_element?(view, ~s(a[href^="/chat?"]))
    end

    test "friends: the tab and the notification's button go", %{conn: conn, user: user} do
      sender = AccountsFixtures.user_fixture()

      {:ok, _} =
        Gamend.Notifications.admin_create_notification(sender.id, user.id, %{
          "title" => "Friend request",
          "metadata" => %{"type" => "friend_request"}
        })

      {:ok, view, html} = live(conn, "/users/settings?tab=notifications")
      assert has_element?(view, ~s([phx-value-tab="friends"]))
      assert html =~ "Friends and groups"
      {:ok, view, _html} = live(conn, "/notifications")
      assert has_element?(view, ~s(a[href*="tab=friends"]))

      leave_out()

      {:ok, view, _html} = live(conn, "/users/settings?tab=friends")
      refute has_element?(view, ~s([phx-value-tab="friends"]))
      assert has_element?(view, ~s([phx-value-tab="account"]))

      {:ok, _view, html} = live(conn, "/users/settings?tab=notifications")
      refute html =~ "Friends and groups"
      refute html =~ "Chat messages"

      {:ok, view, html} = live(conn, "/notifications")
      assert html =~ "Friend request"
      refute has_element?(view, ~s(a[href*="tab=friends"]))
    end

    test "store: settings lose Open Store", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/users/settings?tab=payments")
      assert has_element?(view, ~s(a[href="/store"]))

      leave_out()

      {:ok, view, _html} = live(conn, "/users/settings?tab=payments")
      refute has_element?(view, ~s(a[href="/store"]))
    end
  end

  describe "the API" do
    setup do
      user = AccountsFixtures.user_fixture()
      {:ok, token, _claims} = Guardian.encode_and_sign(user)

      %{
        conn: build_conn(),
        authed: build_conn() |> put_req_header("authorization", "Bearer " <> token)
      }
    end

    test "the payment ways in are on by default, and gone when left out", %{
      conn: conn,
      authed: authed
    } do
      assert conn |> get("/api/v1/payments/catalog") |> json_response(200)
      # Mounted: it answers (a missing product here, not a missing route).
      assert authed |> post("/api/v1/payments/checkout/stripe", %{}) |> json_response(400)

      leave_out()

      assert conn |> get("/api/v1/payments/catalog") |> response(404)
      assert authed |> post("/api/v1/payments/checkout/stripe", %{}) |> response(404)
      # Signed out too: a 404, never a 401 that says the route exists.
      assert conn |> post("/api/v1/payments/checkout/stripe", %{}) |> response(404)
      assert authed |> post("/api/v1/reports", %{}) |> response(404)
    end

    test "what the game uses stays", %{conn: conn, authed: authed} do
      leave_out()

      assert conn |> get("/api/v1/groups") |> json_response(200)
      assert conn |> get("/api/v1/tournaments") |> json_response(200)
      assert authed |> get("/api/v1/payments/entitlements") |> json_response(200)
    end
  end

  describe "/quests" do
    test "has no redeem link once /redeem is left out", %{conn: conn} do
      {:ok, _quest} =
        Gamend.Quests.create_quest(%{
          key: "left_out_code",
          title: "A gift",
          code_only: true,
          rewards: [%{type: "currency", code: "gold", amount: 100}]
        })

      {:ok, view, _html} = live(conn, "/quests")
      assert has_element?(view, "#quests-redeem-link")

      leave_out()

      {:ok, view, _html} = live(conn, "/quests")
      refute has_element?(view, "#quests-redeem-link")
    end
  end
end
