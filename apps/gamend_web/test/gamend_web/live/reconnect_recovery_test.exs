defmodule GamendWeb.ReconnectRecoveryTest do
  @moduledoc """
  A dropped connection re-mounts the LiveView in a new process, so anything
  that lived only in socket assigns is gone. LiveView then re-sends each form's
  values through its `phx-change`, but only for a form that has an id, has
  `phx-change`, and is in the new mount's render. These tests pin both halves:
  the URL renders the form on mount, and `phx-change` keeps what was typed in
  the value the input is bound to.
  """
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Chat
  alias Gamend.Groups
  alias Gamend.Lobbies
  alias Gamend.Repo

  defp own_group(user, title \\ "Test Guild") do
    {:ok, group} = Groups.create_group(user.id, %{"title" => title, "type" => "public"})
    group
  end

  describe "chat" do
    setup :register_and_log_in_user

    setup %{user: user} do
      group = own_group(user)

      {:ok, msg} =
        Chat.send_message(%{user: user}, %{
          "chat_type" => "group",
          "chat_ref_id" => group.id,
          "content" => "original text"
        })

      %{group: group, msg: msg}
    end

    test "the composer keeps its draft in the rendered value", %{conn: conn, group: group} do
      {:ok, view, _html} = live(conn, ~p"/chat?#{[type: "group", id: group.id]}")

      view |> form("#chat-send-form", content: "half typed") |> render_change()

      assert has_element?(view, ~s(#chat-send-form input[name="content"][value="half typed"]))
    end

    test "sending clears the draft", %{conn: conn, group: group} do
      {:ok, view, _html} = live(conn, ~p"/chat?#{[type: "group", id: group.id]}")

      view |> form("#chat-send-form", content: "hello there") |> render_change()
      view |> form("#chat-send-form", content: "hello there") |> render_submit()

      assert has_element?(view, ~s(#chat-send-form input[name="content"][value=""]))
      assert render(view) =~ "hello there"
    end

    test "Edit puts the message in the URL", %{conn: conn, group: group, msg: msg} do
      {:ok, view, _html} = live(conn, ~p"/chat?#{[type: "group", id: group.id]}")

      view
      |> element(~s([phx-click="chat_edit_start"][phx-value-id="#{msg.id}"]))
      |> render_click()

      assert_patch(view, ~p"/chat?#{[type: "group", id: group.id, edit: msg.id]}")
      assert has_element?(view, ~s(#edit-#{msg.id}[phx-change="chat_edit_change"]))
    end

    test "the edit URL renders the edit form on mount", %{conn: conn, group: group, msg: msg} do
      {:ok, view, _html} =
        live(conn, ~p"/chat?#{[type: "group", id: group.id, edit: msg.id]}")

      assert has_element?(
               view,
               ~s(#edit-#{msg.id} input[name="content"][value="original text"])
             )

      view |> form("#edit-#{msg.id}", content: "rewritten") |> render_change()

      assert has_element?(view, ~s(#edit-#{msg.id} input[name="content"][value="rewritten"]))
    end

    test "saving an edit drops it from the URL", %{conn: conn, group: group, msg: msg} do
      {:ok, view, _html} =
        live(conn, ~p"/chat?#{[type: "group", id: group.id, edit: msg.id]}")

      view |> form("#edit-#{msg.id}", content: "rewritten") |> render_submit()

      assert_patch(view, ~p"/chat?#{[type: "group", id: group.id]}")
      refute has_element?(view, "#edit-#{msg.id}")
      assert render(view) =~ "rewritten"
    end

    # `msg` is the oldest; thirty newer ones push it past the first page.
    test "an edit further back than the first page still finds its form", %{
      conn: conn,
      user: user,
      group: group,
      msg: msg
    } do
      for n <- 1..30 do
        Repo.insert!(%Chat.Message{
          content: "newer #{n}",
          chat_type: "group",
          chat_ref_id: group.id,
          sender_id: user.id
        })
      end

      # A function rather than a list to append to: the query's order is what
      # `assert_patch/2` compares, so the base has to stay in front.
      chat = fn extra -> [type: "group", id: group.id] ++ extra end
      {:ok, view, _html} = live(conn, ~p"/chat?#{chat.([])}")
      refute has_element?(view, ~s([phx-click="chat_edit_start"][phx-value-id="#{msg.id}"]))

      view |> element(~s(button[phx-click="load_more"])) |> render_click()
      assert_patch(view, ~p"/chat?#{chat.(page: 2)}")

      view
      |> element(~s([phx-click="chat_edit_start"][phx-value-id="#{msg.id}"]))
      |> render_click()

      assert_patch(view, ~p"/chat?#{chat.(page: 2, edit: msg.id)}")

      {:ok, fresh, _html} = live(conn, ~p"/chat?#{chat.(page: 2, edit: msg.id)}")
      assert has_element?(fresh, "#edit-#{msg.id}")

      # The page number lost, or out of date: loaded until found.
      {:ok, fresh, _html} = live(conn, ~p"/chat?#{chat.(edit: msg.id)}")
      assert has_element?(fresh, ~s(#edit-#{msg.id} input[name="content"][value="original text"]))
    end

    test "another member's message cannot be opened for editing", %{
      conn: conn,
      group: group
    } do
      other = AccountsFixtures.user_fixture()
      {:ok, _} = Groups.join_group(other.id, group.id)

      {:ok, theirs} =
        Chat.send_message(%{user: other}, %{
          "chat_type" => "group",
          "chat_ref_id" => group.id,
          "content" => "not yours"
        })

      {:ok, view, _html} =
        live(conn, ~p"/chat?#{[type: "group", id: group.id, edit: theirs.id]}")

      refute has_element?(view, "#edit-#{theirs.id}")
    end
  end

  describe "settings groups tab" do
    setup :register_and_log_in_user

    test "the create form opens from the URL", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/settings?tab=groups&create=1")

      assert has_element?(view, "#create-group-form")

      view |> form("#create-group-form", group: %{title: "Half a name"}) |> render_change()

      assert has_element?(
               view,
               ~s(#create-group-form input[name="group[title]"][value="Half a name"])
             )
    end

    test "Create puts the open form in the URL", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/settings?tab=groups")

      view |> element(~s(button[phx-click="groups_toggle_create"])) |> render_click()

      assert_patch(view, ~p"/users/settings?tab=groups&create=1")
      assert has_element?(view, "#create-group-form")
    end

    test "the edit form opens from the URL", %{conn: conn, user: user} do
      group = own_group(user)

      {:ok, view, _html} =
        live(conn, ~p"/users/settings?#{[tab: "groups", group: group.id, edit: 1]}")

      assert has_element?(view, "#group-edit-form")

      view |> form("#group-edit-form", group: %{title: "Renamed Guild"}) |> render_change()

      assert has_element?(
               view,
               ~s(#group-edit-form input[name="group[title]"][value="Renamed Guild"])
             )
    end

    test "opening a group and its edit form moves the URL", %{conn: conn, user: user} do
      group = own_group(user)
      {:ok, view, _html} = live(conn, ~p"/users/settings?tab=groups")

      view |> element("#my-group-#{group.id} a") |> render_click()
      ref = Gamend.Groups.full_slug(group)

      assert_patch(view, ~p"/users/settings?#{[tab: "groups", group: ref]}")

      view |> element(~s(button[phx-click="group_toggle_edit"])) |> render_click()

      assert_patch(view, ~p"/users/settings?#{[tab: "groups", group: ref, edit: 1]}")
      assert has_element?(view, "#group-edit-form")
    end

    test "a group the user is not in does not open", %{conn: conn} do
      owner = AccountsFixtures.user_fixture()
      group = own_group(owner, "Someone Else's Guild")

      {:ok, view, _html} =
        live(conn, ~p"/users/settings?#{[tab: "groups", group: group.id, edit: 1]}")

      refute has_element?(view, "#group-members-table")
      refute has_element?(view, "#group-edit-form")
    end
  end

  describe "admin live lobbies" do
    setup %{conn: conn} do
      {:ok, admin} =
        AccountsFixtures.user_fixture()
        |> User.admin_changeset(%{"is_admin" => true})
        |> Repo.update()

      %{conn: log_in_user(conn, admin), admin: admin}
    end

    test "the create form keeps its title", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/lobbies/live")

      view |> form("#lobby-create-form", title: "Friday night") |> render_change()

      assert has_element?(view, ~s(#lobby-create-form input[name="title"][value="Friday night"]))
    end

    test "the manage form opens from the URL", %{conn: conn, admin: admin} do
      {:ok, lobby} = Lobbies.create_lobby(%{title: "Hosted Lobby", host_id: admin.id})

      {:ok, view, _html} = live(conn, ~p"/admin/lobbies/live?#{[manage: lobby.id]}")

      assert has_element?(view, "#lobby-manage-#{lobby.id}")

      view
      |> form("#lobby-manage-#{lobby.id}", title: "Renamed Lobby", is_locked: "true")
      |> render_change()

      assert has_element?(
               view,
               ~s(#lobby-manage-#{lobby.id} input[name="title"][value="Renamed Lobby"])
             )

      assert has_element?(view, ~s(#lobby-manage-#{lobby.id} input[name="is_locked"][checked]))
    end

    test "Edit puts the managed lobby in the URL", %{conn: conn, admin: admin} do
      {:ok, lobby} = Lobbies.create_lobby(%{title: "Hosted Lobby", host_id: admin.id})
      {:ok, view, _html} = live(conn, ~p"/admin/lobbies/live")

      view
      |> element(~s([phx-click="start_manage"][phx-value-id="#{lobby.id}"]))
      |> render_click()

      assert_patch(view, ~p"/admin/lobbies/live?#{[manage: lobby.id]}")
      assert has_element?(view, "#lobby-manage-#{lobby.id}")
    end

    test "the password prompt opens from the URL", %{conn: conn} do
      {:ok, lobby} = Lobbies.create_lobby(%{title: "Locked Door", password: "sesame"})

      {:ok, view, _html} = live(conn, ~p"/admin/lobbies/live?#{[join: lobby.id]}")

      assert has_element?(view, "#lobby-join-#{lobby.id}")

      view |> form("#lobby-join-#{lobby.id}", password: "ses") |> render_change()

      assert has_element?(view, ~s(#lobby-join-#{lobby.id} input[name="password"][value="ses"]))
    end
  end

  describe "login" do
    test "a typed email is kept, and the password never crosses the socket", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/users/log_in")

      # The change binding sits on the email input alone: on the form it would
      # serialize the password with every keystroke.
      refute has_element?(view, "#login_form_password[phx-change]")

      view
      |> element(~s(#login_form_password input[name="user[email]"]))
      |> render_change(%{user: %{email: "typed@example.com"}})

      # Both forms show the address, so the other one survives a reconnect too.
      assert has_element?(
               view,
               ~s(#login_form_magic input[name="user[email]"][value="typed@example.com"])
             )
    end
  end
end
