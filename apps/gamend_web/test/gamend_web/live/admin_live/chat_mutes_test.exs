defmodule GamendWeb.AdminLive.ChatMutesTest do
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Chat
  alias Gamend.Chat.Moderation.Cache
  alias Gamend.Repo

  setup do
    admin = AccountsFixtures.user_fixture()
    {:ok, admin} = admin |> User.admin_changeset(%{"is_admin" => true}) |> Repo.update()
    player = AccountsFixtures.user_fixture()
    on_exit(fn -> Cache.apply_remote(:mute_deleted, {player.id, "global", nil}) end)
    %{admin: admin, player: player}
  end

  defp page(conn, admin, path \\ ~p"/admin/chat/mutes") do
    {:ok, view, _html} = conn |> log_in_user(admin) |> live(path)
    view
  end

  defp mute_row(view, player) do
    Enum.find(:sys.get_state(view.pid).socket.assigns.mutes, &(&1.user_id == player.id))
  end

  test "a global mute added from the form mutes the player and lists them", %{
    conn: conn,
    admin: admin,
    player: player
  } do
    view = page(conn, admin)

    view
    |> form("#chat-mute-add-form", %{
      "user_id" => " #{player.id} ",
      "scope" => "global",
      "duration" => "1h",
      "reason" => "spam",
      "notify" => "false"
    })
    |> render_submit()

    assert Cache.muted?(player.id, "lobby", Ecto.UUID.generate())
    mute = mute_row(view, player)
    assert mute.reason == "spam"
    assert has_element?(view, "#mute-#{mute.id}")
  end

  test "no player id, or a scoped mute with no room, is refused", %{
    conn: conn,
    admin: admin,
    player: player
  } do
    view = page(conn, admin)

    render_submit(view, "mute", %{"user_id" => "  ", "scope" => "global"})
    assert :sys.get_state(view.pid).socket.assigns.form_error =~ "player id"

    render_submit(view, "mute", %{
      "user_id" => player.id,
      "scope" => "lobby",
      "scope_ref_id" => ""
    })

    assert :sys.get_state(view.pid).socket.assigns.form_error =~ "lobby, group or party id"
    refute Cache.muted?(player.id, "lobby", nil)
  end

  test "a mute is edited in place and lifted from its row", %{
    conn: conn,
    admin: admin,
    player: player
  } do
    {:ok, _mute} =
      Chat.mute_user(player.id, "global", nil, %{"reason" => "first", "muted_by" => admin.id})

    view = page(conn, admin)
    mute = mute_row(view, player)

    render_click(view, "edit", %{"id" => mute.id})
    assert has_element?(view, "#chat-mute-edit-form")

    render_change(view, "edit_change", %{
      "duration" => "24h",
      "reason" => "second",
      "notify" => "false"
    })

    render_submit(view, "save_edit", %{
      "duration" => "keep",
      "reason" => "second",
      "notify" => "false"
    })

    assert mute_row(view, player).reason == "second"
    refute has_element?(view, "#chat-mute-edit-form")

    render_click(view, "unmute", %{"id" => mute.id})
    refute Cache.muted?(player.id, "lobby", nil)
  end

  test "an edit cancelled closes its form; an unknown mute says so", %{
    conn: conn,
    admin: admin,
    player: player
  } do
    {:ok, _mute} = Chat.mute_user(player.id, "global", nil, %{"muted_by" => admin.id})
    view = page(conn, admin)

    render_click(view, "edit", %{"id" => mute_row(view, player).id})
    render_click(view, "cancel_edit", %{})
    refute has_element?(view, "#chat-mute-edit-form")

    render_click(view, "edit", %{"id" => Ecto.UUID.generate()})
    render_click(view, "unmute", %{"id" => Ecto.UUID.generate()})
    refute has_element?(view, "#chat-mute-edit-form")
  end

  test "the filters narrow by scope and by whether a mute is still in force", %{
    conn: conn,
    admin: admin,
    player: player
  } do
    {:ok, _} = Chat.mute_user(player.id, "global", nil, %{"muted_by" => admin.id})
    view = page(conn, admin)

    view |> form("#chat-mutes-filter-form", %{"scope" => "lobby"}) |> render_change()
    assert mute_row(view, player) == nil

    render_change(view, "filter", %{"scope" => "global", "active" => "true"})
    assert mute_row(view, player)

    render_change(view, "filter", %{"scope" => "", "active" => "false"})
    assert mute_row(view, player)
  end

  test "a player id in the URL fills the form; the pager and refresh keep the page", %{
    conn: conn,
    admin: admin,
    player: player
  } do
    view = page(conn, admin, ~p"/admin/chat/mutes?user_id=#{player.id}")
    assert :sys.get_state(view.pid).socket.assigns.form["user_id"] == player.id

    render_change(view, "form_change", %{
      "user_id" => player.id,
      "scope" => "group",
      "duration" => "7d"
    })

    assert :sys.get_state(view.pid).socket.assigns.form["scope"] == "group"

    render_click(view, "next_page", %{})
    render_click(view, "prev_page", %{})
    render_click(view, "page_size", %{"size" => "50"})
    render_click(view, "refresh", %{})
    assert :sys.get_state(view.pid).socket.assigns.page_size == 50
  end
end
