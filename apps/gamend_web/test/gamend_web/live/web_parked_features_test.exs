defmodule GamendWeb.WebParkedFeaturesTest do
  @moduledoc """
  `web_chat`, `web_groups`, `web_friends`, `web_tournaments`, `web_store` and
  `web_registration` park a feature on the website: its pages 404, every link to them goes, and
  the API the game uses stays.
  """
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gamend.Accounts
  alias Gamend.Accounts.Scope
  alias GamendWeb.Features
  alias GamendWeb.UserAuth

  setup do
    previous = Application.get_env(:gamend_web, Features)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:gamend_web, Features, previous),
        else: Application.delete_env(:gamend_web, Features)
    end)

    :ok
  end

  defp disable(features) do
    config = Application.get_env(:gamend_web, Features, [])
    off = Enum.map(features, &{&1, false})
    Application.put_env(:gamend_web, Features, Keyword.merge(config, off))
  end

  describe "drop_disabled/1" do
    test "drops entries naming a disabled flag, at any depth" do
      disable([:web_groups])

      config = %{
        "links" => [
          %{"href" => "/quests"},
          %{"href" => "/groups", "feature" => "web_groups"},
          %{"items" => [%{"href" => "/groups", "feature" => "web_groups"}]}
        ]
      }

      assert Features.drop_disabled(config) == %{
               "links" => [%{"href" => "/quests"}, %{"items" => []}]
             }
    end

    test "drops a map's value naming a disabled flag: a whole theme page" do
      disable([:play])

      config = %{
        "pages" => %{
          "game" => %{"feature" => "play", "path" => "/game"},
          "about" => %{"path" => "/about"}
        }
      }

      assert Features.drop_disabled(config) == %{"pages" => %{"about" => %{"path" => "/about"}}}
    end

    test "doc_visible?/1 hides a guide whose front matter names a disabled flag" do
      disable([:play])

      refute Features.doc_visible?(%{meta: %{"feature" => "play"}})
      assert Features.doc_visible?(%{meta: %{"feature" => "no_such_flag"}})
      assert Features.doc_visible?(%{meta: %{}})
      assert Features.doc_visible?(%{slug: "x"})
    end

    test "keeps entries for enabled or unknown flags" do
      config = [
        %{"href" => "/groups", "feature" => "web_groups"},
        %{"href" => "/x", "feature" => "no_such_flag"}
      ]

      assert Features.drop_disabled(config) == config
    end
  end

  describe "web_chat, web_groups and web_tournaments off" do
    setup :register_and_log_in_user

    test "the pages are not found", %{conn: conn} do
      disable([:web_chat, :web_groups, :web_tournaments])

      assert_raise GamendWeb.NotFoundError, fn -> live(conn, "/chat") end
      assert_raise GamendWeb.NotFoundError, fn -> live(conn, "/groups") end
      assert_raise GamendWeb.NotFoundError, fn -> live(conn, "/groups/1") end
      assert_raise GamendWeb.NotFoundError, fn -> live(conn, "/tournaments") end
    end

    test "the account menu and settings lose their links", %{conn: conn} do
      {:ok, _view, before} = live(conn, "/users/settings")
      assert before =~ ~s(href="/chat")
      assert before =~ ~s(phx-value-tab="groups")

      disable([:web_chat, :web_groups])

      {:ok, view, html} = live(conn, "/users/settings?tab=groups")
      refute html =~ ~s(href="/chat")
      refute html =~ ~s(phx-value-tab="groups")
      refute html =~ ~s(href="/groups")

      # `?tab=groups` falls back to the account tab instead of a blank page.
      assert render(view) =~ ~s(phx-value-tab="account")
    end

    test "a chat notification keeps its row but loses its button", %{conn: conn, user: user} do
      sender = Gamend.AccountsFixtures.user_fixture()

      {:ok, _} =
        Gamend.Notifications.admin_create_notification(sender.id, user.id, %{
          "title" => "New message",
          "metadata" => %{"type" => "chat_friend", "friend_id" => sender.id}
        })

      {:ok, _view, before} = live(conn, "/notifications")
      assert before =~ "/chat?"

      disable([:web_chat])

      {:ok, _view, html} = live(conn, "/notifications")
      assert html =~ "New message"
      refute html =~ "/chat?"
    end

    test "web_friends off: settings lose the Friends tab, notifications its button",
         %{conn: conn, user: user} do
      sender = Gamend.AccountsFixtures.user_fixture()

      {:ok, _} =
        Gamend.Notifications.admin_create_notification(sender.id, user.id, %{
          "title" => "Friend request",
          "metadata" => %{"type" => "friend_request"}
        })

      {:ok, _view, before} = live(conn, "/users/settings?tab=notifications")
      assert before =~ ~s(phx-value-tab="friends")
      assert before =~ "Friends and groups"
      {:ok, _view, before} = live(conn, "/notifications")
      assert before =~ "tab=friends"

      disable([:web_friends, :web_groups, :web_chat])

      {:ok, view, html} = live(conn, "/users/settings?tab=friends")
      refute html =~ ~s(phx-value-tab="friends")
      # `?tab=friends` falls back to the account tab instead of a blank page.
      assert render(view) =~ ~s(phx-value-tab="account")

      {:ok, _view, html} = live(conn, "/users/settings?tab=notifications")
      refute html =~ "Friends and groups"
      refute html =~ "Chat messages"

      {:ok, _view, html} = live(conn, "/notifications")
      assert html =~ "Friend request"
      refute html =~ "tab=friends"
    end

    test "web_store off: the store is not found, and settings lose Open Store", %{conn: conn} do
      {:ok, _view, before} = live(conn, "/users/settings?tab=payments")
      assert before =~ ~s(href="/store")

      disable([:web_store])

      assert_raise GamendWeb.NotFoundError, fn -> live(conn, "/store") end
      assert_raise GamendWeb.NotFoundError, fn -> live(conn, "/store/success") end

      {:ok, _view, html} = live(conn, "/users/settings?tab=payments")
      refute html =~ ~s(href="/store")
    end

    test "the API the game uses stays open", %{conn: conn} do
      disable([:web_chat, :web_groups, :web_friends, :web_tournaments, :web_store])

      assert conn |> get("/api/v1/groups") |> json_response(200)
      assert conn |> get("/api/v1/tournaments") |> json_response(200)
    end
  end

  describe "web_registration off" do
    # A guest: a device account, as the website makes one for a visitor
    # (`UserAuth.ensure_user/1`).
    defp guest do
      {:ok, guest} =
        Accounts.find_or_create_from_device("guest-#{System.unique_integer([:positive])}")

      guest
    end

    test "the register page is not found, for a visitor, a guest and an account", %{conn: conn} do
      assert {:ok, _view, _html} = live(conn, "/users/register")

      disable([:web_registration])

      assert_raise GamendWeb.NotFoundError, fn -> live(conn, "/users/register") end

      for user <- [guest(), Gamend.AccountsFixtures.user_fixture()] do
        conn = log_in_user(conn, user)
        assert_raise GamendWeb.NotFoundError, fn -> live(conn, "/users/register") end
      end
    end

    test "a visitor's bar and menu offer Log in alone, and the log-in page no Register",
         %{conn: conn} do
      {:ok, _view, before} = live(conn, "/leaderboards")
      assert before =~ ~s(href="/users/register")
      {:ok, _view, before} = live(conn, "/users/log_in")
      assert before =~ ~s(href="/users/register")

      disable([:web_registration])

      {:ok, _view, html} = live(conn, "/leaderboards")
      refute html =~ ~s(href="/users/register")
      # Log in is the bar's one button, so it is the primary one.
      assert html =~ ~r{href="/users/log_in"\s+class="btn gap-1 btn-primary"}

      {:ok, _view, html} = live(conn, "/users/log_in")
      refute html =~ ~s(href="/users/register")
      assert html =~ ~s(id="login_form_password")
    end

    test "a guest's bar and menu offer Log in alone", %{conn: conn} do
      conn = log_in_user(conn, guest())
      {:ok, _view, before} = live(conn, "/leaderboards")
      assert before =~ ~s(href="/users/register")

      disable([:web_registration])

      {:ok, _view, html} = live(conn, "/leaderboards")
      refute html =~ ~s(href="/users/register")
      assert html =~ ~r{href="/users/log_in"\s+class="btn gap-1 btn-primary"}
      # The phone's account section: Log in opens what Register opened.
      assert html =~
               ~r{<li class="w-full border-t border-base-300 mt-1 pt-1">\s*<a href="/users/log_in"}
    end

    test "a page for registered accounts sends a guest to log in" do
      session_conn = fn user ->
        build_conn()
        |> Map.replace!(:secret_key_base, GamendWeb.endpoint().config(:secret_key_base))
        |> init_test_session(%{})
        |> fetch_flash()
        |> assign(:current_scope, Scope.for_user(user))
        |> UserAuth.require_registered_user([])
      end

      assert redirected_to(session_conn.(guest())) == "/users/register?return_to=%2F"

      disable([:web_registration])

      conn = session_conn.(guest())
      assert conn.halted
      assert redirected_to(conn) == "/users/log_in?return_to=%2F"
      refute session_conn.(Gamend.AccountsFixtures.user_fixture()).halted
    end

    test "a theme link marked web_registration goes" do
      disable([:web_registration])

      buttons = [
        %{"href" => "/users/log_in"},
        %{"href" => "/users/register", "feature" => "web_registration"}
      ]

      assert Features.drop_disabled(buttons) == [%{"href" => "/users/log_in"}]
    end

    test "the game still registers its players", %{conn: conn} do
      disable([:web_registration])

      email = Gamend.AccountsFixtures.unique_user_email()
      conn = post(conn, "/api/v1/register", %{"email" => email})

      assert json_response(conn, 201)
      assert Accounts.get_user_by_email(email)
    end
  end
end
