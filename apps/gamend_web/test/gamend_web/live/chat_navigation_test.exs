defmodule GamendWeb.ChatNavigationTest do
  @moduledoc """
  The conversation a user opens must live in the URL, so a refresh restores it
  and other pages can link straight to it.
  """
  use GamendWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Gamend.Chat
  alias Gamend.Groups

  setup :register_and_log_in_user

  defp own_group(user) do
    {:ok, group} = Groups.create_group(user.id, %{"title" => "Test Guild", "type" => "public"})
    group
  end

  test "a group chat URL selects that conversation (survives refresh)", %{conn: conn, user: user} do
    group = own_group(user)

    {:ok, _view, html} = live(conn, ~p"/chat?#{[type: "group", id: group.id]}")

    # The chat header shows the selected group — the same path a browser
    # refresh takes, since a reload re-requests this exact URL.
    assert html =~ "Test Guild"
  end

  test "opening a group from the sidebar pushes the URL", %{conn: conn, user: user} do
    group = own_group(user)

    {:ok, view, _html} = live(conn, ~p"/chat")

    view
    |> element(~s([phx-click="open_group"][phx-value-id="#{group.id}"]))
    |> render_click()

    # The selection is reflected in the address bar, not just in memory, so a
    # refresh from here keeps the group open.
    assert_patch(view, ~p"/chat?#{[type: "group", id: group.id]}")
    assert render(view) =~ "Test Guild"
  end

  test "the group page links members to that group's chat", %{conn: conn, user: user} do
    group = own_group(user)

    {:ok, _view, html} = live(conn, ~p"/groups/#{group.id}")

    assert html =~ ~s(href="/chat?type=group&amp;id=#{group.id}")
    assert html =~ "Open chat"
  end

  # A message that arrives while its conversation is already open must advance
  # the read cursor too — otherwise it renders but still counts as unread the
  # next time the sidebar is built. Opening a chat goes through handle_params,
  # which marks read unconditionally; this arrival path went through a guard
  # that still expected integer ids, so it silently did nothing.
  test "a message arriving in the open conversation marks it read", %{conn: conn, user: user} do
    group = own_group(user)
    sender = Gamend.AccountsFixtures.user_fixture()
    {:ok, _} = Groups.join_group(sender.id, group.id)

    {:ok, view, _html} = live(conn, ~p"/chat?#{[type: "group", id: group.id]}")

    {:ok, _msg} =
      Chat.send_message(%{user: sender}, %{
        "chat_type" => "group",
        "chat_ref_id" => group.id,
        "content" => "while you watch"
      })

    assert render(view) =~ "while you watch"
    assert Chat.count_unread(user.id, "group", group.id) == 0
  end

  test "the group page shows no chat link to non-members", %{user: user} do
    group = own_group(user)
    other = Gamend.AccountsFixtures.user_fixture()
    other_conn = log_in_user(Phoenix.ConnTest.build_conn(), other)

    {:ok, _view, html} = live(other_conn, ~p"/groups/#{group.id}")

    refute html =~ "Open chat"
  end

  test "a group's chat opens only for its members", %{conn: conn} do
    owner = Gamend.AccountsFixtures.user_fixture()
    {:ok, group} = Groups.create_group(owner.id, %{"title" => "Closed", "type" => "hidden"})

    {:ok, _msg} =
      Chat.send_message(%{user: owner}, %{
        "chat_type" => "group",
        "chat_ref_id" => group.id,
        "content" => "members only"
      })

    {:ok, view, _html} = live(conn, ~p"/chat?#{[type: "group", id: group.id]}")
    assigns = :sys.get_state(view.pid).socket.assigns

    assert assigns.chat_target == nil
    assert assigns.messages == []
  end
end
