defmodule GamendWeb.AdminLive.QuestsTest do
  # The admin quests page (`AdminLive.Quests`): filters and pagers, a quest
  # created, edited and deleted from its forms, granted to a player, and a
  # player's progress completed, claimed and reset from the progress table.
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Quests
  alias Gamend.Repo

  setup do
    admin = AccountsFixtures.user_fixture()
    {:ok, admin} = admin |> User.admin_changeset(%{"is_admin" => true}) |> Repo.update()

    {:ok, quest} =
      Quests.create_quest(%{
        key: "admin_quest_#{System.unique_integer([:positive])}",
        title: "Say hello",
        reset: "never",
        objectives: [%{event: "admin_test_event", target: 1}]
      })

    %{admin: admin, quest: quest, player: AccountsFixtures.user_fixture()}
  end

  defp page(conn, admin) do
    {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/admin/quests")
    view
  end

  defp assigns(view), do: :sys.get_state(view.pid).socket.assigns

  test "the filters and pagers keep the quest listed", %{conn: conn, admin: admin, quest: quest} do
    view = page(conn, admin)
    assert has_element?(view, "#admin-quest-#{quest.id}")

    render_change(view, "filter_category", %{"category" => "nonexistent"})
    refute has_element?(view, "#admin-quest-#{quest.id}")
    render_change(view, "filter_category", %{"category" => ""})
    render_click(view, "next_page", %{})
    render_click(view, "prev_page", %{})
    render_click(view, "page_size", %{"size" => "50"})
    assert has_element?(view, "#admin-quest-#{quest.id}")
  end

  test "a quest is created from the form", %{conn: conn, admin: admin} do
    view = page(conn, admin)
    render_click(view, "new_quest", %{})
    assert has_element?(view, "#quest-form")

    key = "made_in_admin_#{System.unique_integer([:positive])}"

    render_submit(view, "save_quest", %{
      "quest" => %{"key" => key, "title" => "From the page", "reset" => "never"},
      "objectives_json" => ~s([{"event": "login", "target": 2}]),
      "rewards_json" => "[]"
    })

    refute has_element?(view, "#quest-form")
    assert Enum.any?(Quests.list_quests(), &(&1.key == key))
  end

  test "a quest is edited, the form cancelled, then deleted", %{
    conn: conn,
    admin: admin,
    quest: quest
  } do
    view = page(conn, admin)

    render_click(view, "edit_quest", %{"id" => quest.id})
    assert assigns(view).selected_quest.id == quest.id

    render_submit(view, "save_quest", %{
      "quest" => %{"title" => "Renamed"},
      "objectives_json" => ~s([{"event": "login", "target": 1}]),
      "rewards_json" => "[]"
    })

    assert Quests.get_quest(quest.id).title == "Renamed"

    render_click(view, "edit_quest", %{"id" => quest.id})
    render_click(view, "cancel_edit", %{})
    refute has_element?(view, "#quest-form")

    render_click(view, "delete_quest", %{"id" => quest.id})
    assert Quests.get_quest(quest.id) == nil
    render_click(view, "delete_quest", %{"id" => quest.id})
  end

  test "a quest is granted to a player; a bad id is refused", %{
    conn: conn,
    admin: admin,
    quest: quest,
    player: player
  } do
    view = page(conn, admin)

    render_click(view, "grant_form", %{"id" => quest.id})
    assert has_element?(view, "#grant-form")
    render_submit(view, "grant_quest", %{"grant" => %{"user_id" => "not-a-uuid"}})
    assert has_element?(view, "#grant-form")

    render_submit(view, "grant_quest", %{"grant" => %{"user_id" => player.id}})
    refute has_element?(view, "#grant-form")

    render_click(view, "grant_form", %{"id" => quest.id})
    render_submit(view, "grant_quest", %{"grant" => %{"user_id" => player.id}})
    render_click(view, "cancel_grant", %{})
    refute has_element?(view, "#grant-form")
  end

  test "a player's progress is completed, claimed and reset from its row", %{
    conn: conn,
    admin: admin,
    quest: quest,
    player: player
  } do
    view = page(conn, admin)
    args = %{"user" => player.id, "key" => quest.key}

    render_click(view, "force_complete", args)
    render_change(view, "filter_progress", %{"user_id" => player.id, "quest_key" => quest.key})
    assert assigns(view).progress_rows != []

    render_click(view, "force_claim", args)
    render_click(view, "reset_progress", args)
    render_click(view, "reset_progress", args)

    render_click(view, "progress_next_page", %{})
    render_click(view, "progress_prev_page", %{})
    render_click(view, "progress_page_size", %{"size" => "50"})
    assert render(view)
  end

  test "a quest deleted elsewhere while the page is open is answered, not crashed on", %{
    conn: conn,
    admin: admin,
    quest: quest
  } do
    view = page(conn, admin)
    {:ok, _} = Quests.delete_quest(quest)

    render_click(view, "edit_quest", %{"id" => quest.id})
    refute has_element?(view, "#quest-form")

    render_click(view, "grant_form", %{"id" => quest.id})
    refute has_element?(view, "#grant-form")
  end
end
