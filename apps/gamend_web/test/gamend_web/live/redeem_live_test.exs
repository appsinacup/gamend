defmodule GamendWeb.RedeemLiveTest do
  @moduledoc """
  `/redeem`: the box, the list of what codes can finish, the link to one, and
  a signed-out visitor becoming a guest only for a code that works.
  """
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gamend.Accounts
  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Economy
  alias Gamend.Quests
  alias Gamend.Repo

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

  defp submit(view, token) do
    view |> form("#redeem-form", redeem: %{token: token}) |> render_submit()
  end

  defp flash(view, kind) do
    view |> element("#flash-#{kind}") |> render()
  end

  defp account_count, do: Repo.aggregate(User, :count)

  describe "what it lists" do
    test "every open code-only quest, to anyone", %{conn: conn} do
      first = code_quest()
      second = code_quest()
      {:ok, view, _html} = live(conn, "/redeem")

      assert has_element?(view, "#redeem-form")
      assert has_element?(view, "#redeem-card-#{first.key}")
      assert has_element?(view, "#redeem-card-#{second.key}")
      refute has_element?(view, "#redeem-show-all")
    end

    test "?quest= narrows it to one, and All goes back", %{conn: conn} do
      first = code_quest()
      second = code_quest()
      {:ok, view, _html} = live(conn, "/redeem?quest=#{first.key}")

      assert has_element?(view, "#redeem-form")
      assert has_element?(view, "#redeem-card-#{first.key}")
      refute has_element?(view, "#redeem-card-#{second.key}")

      view |> element("#redeem-show-all") |> render_click()

      assert has_element?(view, "#redeem-card-#{second.key}")
      assert_patch(view, "/redeem")
    end

    test "a link to a quest that is not there still has the box", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/redeem?quest=nothing")

      assert has_element?(view, "#redeem-form")
      refute has_element?(view, "#redeem-list")
    end

    test "a hidden quest is off the list", %{conn: conn} do
      quest = code_quest(%{hidden: true})
      {:ok, view, _html} = live(conn, "/redeem?quest=#{quest.key}")

      refute has_element?(view, "#redeem-card-#{quest.key}")
    end

    test "/quests has no link while there is nothing to redeem", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/quests")

      refute has_element?(view, "#quests-redeem-link")
    end
  end

  describe "a signed-in player" do
    setup %{conn: conn} do
      user = AccountsFixtures.user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "redeems, is told what they got, and the card turns", %{conn: conn, user: user} do
      quest = code_quest()
      code = code(quest)
      {:ok, view, _html} = live(conn, "/redeem")

      refute has_element?(view, "#redeem-card-#{quest.key} .badge-success")

      submit(view, String.downcase(code.token))

      assert flash(view, :info) =~ "Spring gift"
      assert flash(view, :info) =~ "+100 gold"
      assert has_element?(view, "#redeem-card-#{quest.key} .badge-success")
      assert Economy.balance(user.id, "gold") == 100
    end

    test "says when a code does not work", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/redeem")

      submit(view, "nope")

      assert has_element?(view, "#flash-error")
    end

    test "says when they already have it", %{conn: conn, user: user} do
      code = code(code_quest())
      {:ok, _} = Quests.redeem_code(user.id, code.token)
      {:ok, view, _html} = live(conn, "/redeem")

      submit(view, code.token)

      assert has_element?(view, "#flash-error")
    end

    test "offers registration where the host requires an account", %{conn: conn} do
      previous = Application.get_env(:gamend_core, Gamend.AccountRequired, [])
      Application.put_env(:gamend_core, Gamend.AccountRequired, [:quest_claims])
      on_exit(fn -> Application.put_env(:gamend_core, Gamend.AccountRequired, previous) end)

      {:ok, guest} = Accounts.find_or_create_from_device("redeem_#{System.unique_integer()}")
      conn = log_in_user(conn, guest)
      code = code(code_quest())
      {:ok, view, _html} = live(conn, "/redeem")

      submit(view, code.token)

      assert has_element?(view, "#redeem-register")
    end

    test "a blank box does nothing", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/redeem")

      submit(view, "   ")

      refute has_element?(view, "#flash-error")
    end

    test "redeeming shows on /quests", %{conn: conn, user: user} do
      quest = code_quest()
      {:ok, _} = Quests.redeem_code(user.id, code(quest).token)

      {:ok, _view, html} = live(conn, "/quests")

      assert html =~ quest.title
    end
  end

  describe "a signed-out visitor" do
    setup do
      previous = Application.get_env(:gamend_core, Gamend.Accounts, [])

      Application.put_env(
        :gamend_core,
        Gamend.Accounts,
        Keyword.put(previous, :device_auth_enabled, true)
      )

      on_exit(fn -> Application.put_env(:gamend_core, Gamend.Accounts, previous) end)
      :ok
    end

    test "a working code makes a guest and redeems on it", %{conn: conn} do
      quest = code_quest()
      code = code(quest, %{max_uses: nil})
      accounts = account_count()
      {:ok, view, _html} = live(conn, "/redeem")

      submit(view, code.token)

      assert account_count() == accounts + 1
      assert_push_event(view, "gamend:anonymous_session", %{token: _, notice: true})
      assert has_element?(view, "#redeem-card-#{quest.key} .badge-success")
      assert Quests.get_code(code.id).uses == 1
    end

    test "a code that does not work makes no account", %{conn: conn} do
      accounts = account_count()
      {:ok, view, _html} = live(conn, "/redeem")

      submit(view, "nope")

      assert account_count() == accounts
      assert has_element?(view, "#flash-error")
    end

    test "makes no guest where the host requires an account", %{conn: conn} do
      previous = Application.get_env(:gamend_core, Gamend.AccountRequired, [])
      Application.put_env(:gamend_core, Gamend.AccountRequired, [:quest_claims])
      on_exit(fn -> Application.put_env(:gamend_core, Gamend.AccountRequired, previous) end)

      code = code(code_quest())
      accounts = account_count()
      {:ok, view, _html} = live(conn, "/redeem")

      submit(view, code.token)

      assert account_count() == accounts
      assert has_element?(view, "#redeem-register")
      assert Quests.get_code(code.id).uses == 0
    end

    test "cannot submit until the socket is up, so a code never reaches the URL", %{conn: conn} do
      disabled =
        conn
        |> get("/redeem")
        |> html_response(200)
        |> LazyHTML.from_document()
        |> LazyHTML.query("#redeem-submit[disabled]")

      assert Enum.count(disabled) == 1

      {:ok, view, _html} = live(conn, "/redeem")
      refute has_element?(view, "#redeem-submit[disabled]")
    end

    test "with device accounts off, it asks to register", %{conn: conn} do
      Application.put_env(:gamend_core, Gamend.Accounts, device_auth_enabled: false)
      code = code(code_quest())
      {:ok, view, _html} = live(conn, "/redeem")

      submit(view, code.token)

      assert has_element?(view, "#redeem-register")
      assert Quests.get_code(code.id).uses == 0
    end
  end
end
