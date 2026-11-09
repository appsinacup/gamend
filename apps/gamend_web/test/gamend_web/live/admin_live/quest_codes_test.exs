defmodule GamendWeb.AdminLive.QuestCodesTest do
  @moduledoc """
  `/admin/quests/:id/codes`, its CSV, and the two things `/admin/quests` gained
  for it.
  """
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gamend.Accounts
  alias Gamend.AccountsFixtures
  alias Gamend.Quests

  setup %{conn: conn} do
    {:ok, admin} = Accounts.update_user(AccountsFixtures.user_fixture(), %{is_admin: true})

    {:ok, quest} =
      Quests.create_quest(%{
        key: "codes_#{System.unique_integer([:positive])}",
        title: "Spring gift",
        code_only: true
      })

    %{conn: log_in_user(conn, admin), quest: quest}
  end

  defp open(conn, quest) do
    {:ok, view, _html} = live(conn, "/admin/quests/#{quest.key}/codes")
    view
  end

  test "generates codes", %{conn: conn, quest: quest} do
    view = open(conn, quest)

    view
    |> form("#quest-codes-generate", generate: %{count: "3", max_uses: "", metadata: ~s({"a":1})})
    |> render_submit()

    render_async(view)

    assert [%{max_uses: nil, metadata: %{"a" => 1}} | _] = Quests.list_codes(quest.key)
    assert Quests.count_codes(quest.key) == 3
  end

  test "refuses a bad generate", %{conn: conn, quest: quest} do
    view = open(conn, quest)

    view
    |> form("#quest-codes-generate", generate: %{count: "0", max_uses: "1", metadata: ""})
    |> render_submit()

    assert has_element?(view, "#flash-error")
    assert Quests.count_codes(quest.key) == 0
  end

  test "adds one code, and says when it is taken", %{conn: conn, quest: quest} do
    view = open(conn, quest)

    view
    |> form("#quest-codes-add", code: %{token: "春节快乐", max_uses: "", metadata: ""})
    |> render_submit()

    assert [%{token: "春节快乐", max_uses: nil} = code] = Quests.list_codes(quest.key)
    assert has_element?(view, "#quest-code-#{code.id}")

    view
    |> form("#quest-codes-add", code: %{token: "春节 快乐", max_uses: "", metadata: ""})
    |> render_submit()

    assert has_element?(view, "#flash-error")
    assert Quests.count_codes(quest.key) == 1
  end

  test "revokes and restores", %{conn: conn, quest: quest} do
    {:ok, code} = Quests.create_code(quest, %{token: "STOP"})
    view = open(conn, quest)

    view |> element("#quest-code-#{code.id} button", "Revoke") |> render_click()
    assert Quests.get_code(code.id).status == "revoked"

    view |> element("#quest-code-#{code.id} button", "Restore") |> render_click()
    assert Quests.get_code(code.id).status == "active"
  end

  test "searches for an exact code, and says who used one", %{conn: conn, quest: quest} do
    {:ok, code} = Quests.create_code(quest, %{token: "FIND-ME"})
    {:ok, other} = Quests.create_code(quest, %{token: "OTHER"})
    player = AccountsFixtures.user_fixture()
    {:ok, _} = Quests.redeem_code(player.id, "FIND-ME")

    view = open(conn, quest)

    assert view |> element("#quest-code-#{code.id}") |> render() =~ player.username

    view |> form("#quest-codes-search", search: "find me") |> render_change()

    assert has_element?(view, "#quest-code-#{code.id}")
    refute has_element?(view, "#quest-code-#{other.id}")
  end

  test "a quest that is not code-only has no such page", %{conn: conn} do
    {:ok, quest} =
      Quests.create_quest(%{
        key: "plain_#{System.unique_integer([:positive])}",
        title: "Plain",
        objectives: [%{event: "won", target: 1}]
      })

    assert_raise GamendWeb.NotFoundError, fn -> live(conn, "/admin/quests/#{quest.key}/codes") end
  end

  test "the breadcrumb skips the quest's key, which is no page", %{quest: quest} do
    assert GamendWeb.AdminBreadcrumbs.trail("/admin/quests/#{quest.key}/codes") == [
             {"Home", "/"},
             {"Admin", "/admin"},
             {"Quests", "/admin/quests"},
             {"Codes", nil}
           ]
  end

  test "a player cannot open it", %{quest: quest} do
    conn = log_in_user(build_conn(), AccountsFixtures.user_fixture())

    assert {:error, {:redirect, _}} = live(conn, "/admin/quests/#{quest.key}/codes")
  end

  describe "the CSV" do
    test "has every code", %{conn: conn, quest: quest} do
      {:ok, _} = Quests.create_code(quest, %{token: "a,b", max_uses: 5})
      {:ok, _} = Quests.create_code(quest, %{token: "PLAIN"})

      conn = get(conn, "/admin/quests/#{quest.key}/codes/export")

      assert response(conn, 200) ==
               ~s(token,max_uses,uses,status\n"a,b",5,0,active\nPLAIN,,0,active\n)

      assert [type] = get_resp_header(conn, "content-type")
      assert type =~ "text/csv"
    end

    test "is for admins", %{quest: quest} do
      conn = log_in_user(build_conn(), AccountsFixtures.user_fixture())

      assert redirected_to(get(conn, "/admin/quests/#{quest.key}/codes/export"))
    end
  end

  describe "/admin/quests" do
    test "a code-only row opens its codes", %{conn: conn, quest: quest} do
      {:ok, view, _html} = live(conn, "/admin/quests")

      view |> element("#admin-quest-codes-#{quest.id}") |> render_click()

      assert_redirect(view, "/admin/quests/#{quest.key}/codes")
    end

    test "Only by code drops the form's example objective", %{conn: conn} do
      key = "made_#{System.unique_integer([:positive])}"
      {:ok, view, _html} = live(conn, "/admin/quests")

      view |> element("button", "+ Create Quest") |> render_click()

      view
      |> form("#quest-form", quest: %{key: key, title: "By code", code_only: "true"})
      |> render_submit()

      assert %{code_only: true, objectives: []} = Quests.get_quest_by_key(key)
    end
  end
end
