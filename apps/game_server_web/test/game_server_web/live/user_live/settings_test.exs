defmodule GameServerWeb.UserLive.SettingsTest do
  use GameServerWeb.ConnCase, async: true

  alias GameServer.Accounts
  alias GameServer.Accounts.User
  alias GameServer.Friends
  alias GameServer.Repo
  import Ecto.Query
  import Phoenix.LiveViewTest
  import GameServer.AccountsFixtures

  describe "Settings page" do
    test "renders settings page", %{conn: conn} do
      user = user_fixture()

      {:ok, user} =
        user
        |> User.admin_changeset(%{
          "display_name" => "Tester",
          "is_admin" => true
        })
        |> Repo.update()

      {:ok, lv, html} =
        conn
        |> log_in_user(user)
        |> live(~p"/users/settings")

      assert html =~ "Email"
      assert html =~ "Data"
      assert html =~ "Save"
      assert html =~ "Link"
      assert has_element?(lv, "#password_form")
      assert html =~ "Tester"
    end

    test "friends panel shows and can accept incoming requests", %{conn: conn} do
      # a will accept b's request
      a = user_fixture()
      b = user_fixture(%{email: unique_user_email(), display_name: "B-User"})

      {:ok, _} = Friends.create_request(b.id, a.id)

      logged_conn = conn |> log_in_user(a)

      {:ok, view, _html} = live(logged_conn, ~p"/users/settings")

      # Switch to friends tab
      view
      |> element(~s(button[phx-click="settings_tab"][phx-value-tab="friends"]))
      |> render_click()

      # incoming should be present
      assert render(view) =~ "Incoming requests"

      f =
        Repo.one(
          from fr in Friends.Friendship,
            where: fr.requester_id == ^b.id and fr.target_id == ^a.id
        )

      accept_btn = element(view, "#request-#{f.id} button", "Accept")
      assert render_click(accept_btn)

      f2 = Repo.get!(Friends.Friendship, f.id)
      assert f2.status == "accepted"
    end

    test "incoming request can be blocked from settings", %{conn: conn} do
      a = user_fixture()
      b = user_fixture(%{email: unique_user_email(), display_name: "B-User"})

      {:ok, _} = Friends.create_request(b.id, a.id)

      logged_conn = conn |> log_in_user(a)

      {:ok, view, _html} = live(logged_conn, ~p"/users/settings")

      # Switch to friends tab
      view
      |> element(~s(button[phx-click="settings_tab"][phx-value-tab="friends"]))
      |> render_click()

      f =
        Repo.one(
          from fr in Friends.Friendship,
            where: fr.requester_id == ^b.id and fr.target_id == ^a.id
        )

      block_btn = element(view, "#request-#{f.id} button", "Block")
      assert render_click(block_btn)

      f2 = Repo.get!(Friends.Friendship, f.id)
      assert f2.status == "blocked"
    end

    test "blocked users appear in list and can be unblocked", %{conn: conn} do
      a = user_fixture()
      b = user_fixture(%{email: unique_user_email(), display_name: "B-User"})

      {:ok, _} = Friends.create_request(b.id, a.id)

      logged_conn = conn |> log_in_user(a)
      {:ok, view, _html} = live(logged_conn, ~p"/users/settings")

      # Switch to friends tab
      view
      |> element(~s(button[phx-click="settings_tab"][phx-value-tab="friends"]))
      |> render_click()

      f =
        Repo.one(
          from fr in Friends.Friendship,
            where: fr.requester_id == ^b.id and fr.target_id == ^a.id
        )

      # block
      block_btn = element(view, "#request-#{f.id} button", "Block")
      assert render_click(block_btn)

      # blocked list should show entry
      assert render(view) =~ "Blocked users"
      assert has_element?(view, "#blocked-#{f.id}")

      # unblock using UI
      unblock_btn = element(view, "#blocked-#{f.id} button", "Unblock")
      assert render_click(unblock_btn)

      # friendship should be removed
      assert Repo.get(Friends.Friendship, f.id) == nil
    end

    test "redirects if user is not logged in", %{conn: conn} do
      assert {:error, redirect} = live(conn, ~p"/users/settings")

      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log_in"
      assert %{"error" => "Failed"} = flash
    end
  end

  describe "update email form" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "updates the user email", %{conn: conn, user: user} do
      new_email = unique_user_email()

      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> form("#email_form", %{
          "user" => %{"email" => new_email}
        })
        |> render_submit()

      assert result =~ "Success."
      assert Accounts.get_user_by_email(user.email)
    end

    test "renders errors with invalid data (phx-change)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> element("#email_form")
        |> render_change(%{
          "action" => "update_email",
          "user" => %{"email" => "with spaces"}
        })

      assert result =~ "Email"
      assert result =~ "must have the @ sign and no spaces"
    end

    test "renders errors with invalid data (phx-submit)", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> form("#email_form", %{
          "user" => %{"email" => user.email}
        })
        |> render_submit()

      assert result =~ "Email"
      assert result =~ "did not change"
    end
  end

  describe "update display name form" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "updates the user display name", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      new_display = "NewName"

      form =
        form(lv, "#display_form", %{
          "user" => %{"display_name" => new_display}
        })

      render_submit(form)

      assert render(lv) =~ "Success."

      # reload from DB
      reloaded = Repo.get(User, user.id)
      assert reloaded.display_name == new_display
    end

    test "renders errors with invalid data (too long) (phx-change)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      long_name = String.duplicate("a", 200)

      result =
        lv
        |> element("#display_form")
        |> render_change(%{"user" => %{"display_name" => long_name}})

      assert has_element?(lv, "#display_form")
      assert result =~ "should be at most"
    end
  end

  describe "friends search and send" do
    setup %{conn: conn} do
      a = user_fixture()
      %{conn: log_in_user(conn, a), user: a}
    end

    test "searches users by display_name and send request without showing email", %{
      conn: conn,
      user: a
    } do
      b = user_fixture(%{email: "friend-search@example.com"})
      {:ok, b} = Accounts.update_user_display_name(b, %{"display_name" => "FriendSearch"})

      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      # Switch to friends tab
      lv
      |> element(~s(button[phx-click="settings_tab"][phx-value-tab="friends"]))
      |> render_click()

      # find search form and trigger change
      search_el = element(lv, "form[phx-change=\"search_users\"]")
      render_change(search_el, %{"q" => "FriendSearch"})

      # search results should include our user
      html = render(lv)
      assert html =~ b.display_name
      refute html =~ b.email

      # send request using button for the search result
      send_btn = element(lv, "#search-#{b.id} button", "Send")
      assert render_click(send_btn)

      # outgoing should now include the request
      f =
        Repo.one(
          from fr in Friends.Friendship,
            where: fr.requester_id == ^a.id and fr.target_id == ^b.id
        )

      assert f.status == "pending"
    end

    test "friends pagination displays totals and disables Next on last page", %{
      conn: conn,
      user: a
    } do
      # create 30 users who friend 'a' and have their requests accepted so a has 30 friends
      other = for _ <- 1..30, do: user_fixture()

      Enum.each(other, fn u ->
        {:ok, _} = Friends.create_request(u.id, a.id)

        f =
          Repo.one(
            from fr in Friends.Friendship,
              where: fr.requester_id == ^u.id and fr.target_id == ^a.id
          )

        {:ok, _} = Friends.accept_friend_request(f.id, %User{id: a.id})
      end)

      {:ok, lv, _html} = live(conn |> log_in_user(a), ~p"/users/settings")

      # Switch to friends tab
      lv
      |> element(~s(button[phx-click="settings_tab"][phx-value-tab="friends"]))
      |> render_click()

      rendered = render(lv)
      # total_count 30 should be displayed and total_pages should be 2 for default page_size 25
      assert rendered =~ "30"
      assert rendered =~ "/ 2"

      # On first page, Next should be enabled (no disabled attr on friends_next)
      assert rendered =~ ~s(phx-click="friends_next")
      refute rendered =~ ~r/<button[^>]*phx-click="friends_next"[^>]*disabled/

      # click next to go to page 2
      lv |> element("button[phx-click=\"friends_next\"]") |> render_click()

      rendered2 = render(lv)
      # on page 2, Next should be disabled
      assert rendered2 =~ ~r/<button[^>]*phx-click="friends_next"[^>]*disabled/
    end
  end

  describe "update password form" do
    setup %{conn: conn} do
      user = user_fixture()
      %{conn: log_in_user(conn, user), user: user}
    end

    test "updates the user password", %{conn: conn, user: user} do
      new_password = valid_user_password()

      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      form =
        form(lv, "#password_form", %{
          "user" => %{
            "email" => user.email,
            "password" => new_password,
            "password_confirmation" => new_password
          }
        })

      render_submit(form)

      new_password_conn = follow_trigger_action(form, conn)

      assert redirected_to(new_password_conn) == ~p"/users/settings"

      assert get_session(new_password_conn, :user_token) != get_session(conn, :user_token)

      assert Phoenix.Flash.get(new_password_conn.assigns.flash, :info) =~
               "Success."

      assert Accounts.get_user_by_email_and_password(user.email, new_password)
    end

    test "renders errors with invalid data (phx-change)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> element("#password_form")
        |> render_change(%{
          "user" => %{
            "password" => "short",
            "password_confirmation" => "does not match"
          }
        })

      assert has_element?(lv, "#password_form")
      assert result =~ "should be at least 8 character(s)"
      assert result =~ "does not match password"
    end

    test "renders errors with invalid data (phx-submit)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      result =
        lv
        |> form("#password_form", %{
          "user" => %{
            "password" => "short",
            "password_confirmation" => "does not match"
          }
        })
        |> render_submit()

      assert has_element?(lv, "#password_form")
      assert result =~ "should be at least 8 character(s)"
      assert result =~ "does not match password"
    end
  end

  describe "linking/unlinking providers" do
    setup %{conn: conn} do
      user = user_fixture(%{email: unique_user_email()})
      %{conn: log_in_user(conn, user), user: user}
    end

    test "can unlink a provider when another provider remains", %{conn: conn, user: user} do
      _user =
        Repo.update!(
          Ecto.Changeset.change(user, %{
            discord_id: "d1",
            google_id: "g1",
            profile_url: "https://cdn.discordapp.com/avatars/d1/a_abc.gif"
          })
        )

      {:ok, lv, html} = live(conn, ~p"/users/settings")

      assert html =~ "Remove"

      # Click unlink on discord
      lv |> element("button[phx-value-provider=\"discord\"]") |> render_click()

      # page should show link button for discord (now unlinked)
      assert render(lv) =~ "Link"
      # google is now the last linked provider and unlink is disabled
      refute has_element?(lv, "button[phx-value-provider=\"google\"]")
      assert render(lv) =~ "btn-disabled"
    end

    test "cannot unlink last remaining social provider", %{conn: conn, user: user} do
      _user = Repo.update!(Ecto.Changeset.change(user, %{discord_id: "d1"}))

      {:ok, lv, _html} = live(conn, ~p"/users/settings")

      # Unlink is disabled for the last provider
      refute has_element?(lv, "button[phx-value-provider=\"discord\"]")
      assert render(lv) =~ "btn-disabled"
    end

    test "can delete conflicting account when other account has no password (provider-only)", %{
      conn: conn
    } do
      # other account is provider-only (no password) and already has the discord_id
      other_user = user_fixture(%{discord_id: "d_conflict"})

      {:ok, lv, html} =
        live(
          conn,
          ~p"/users/settings?conflict_provider=discord&conflict_user_id=#{other_user.id}"
        )

      assert html =~ "Failed"
      assert has_element?(lv, "button[phx-value-id=\"#{other_user.id}\"]")

      # click delete
      lv |> element("button[phx-value-id=\"#{other_user.id}\"]") |> render_click()

      # other account should be removed
      refute Repo.get(User, other_user.id)
      assert render(lv) =~ "Success."
    end

    test "cannot delete conflicting account when other account has a password", %{conn: conn} do
      other_user = user_fixture(%{discord_id: "d_conflict"})
      # set a password for the other_user so it's a real claimed account
      other_user = set_password(other_user)

      {:ok, lv, html} =
        live(
          conn,
          ~p"/users/settings?conflict_provider=discord&conflict_user_id=#{other_user.id}"
        )

      assert html =~ "Failed"

      lv |> element("button[phx-value-id=\"#{other_user.id}\"]") |> render_click()

      # other account should remain
      assert Repo.get(User, other_user.id)
      assert render(lv) =~ "Failed"
    end
  end

  describe "confirm email" do
    setup %{conn: conn} do
      user = user_fixture()
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{conn: log_in_user(conn, user), token: token, email: email, user: user}
    end

    test "updates the user email once", %{conn: conn, user: user, token: token, email: email} do
      {:error, redirect} = live(conn, ~p"/users/settings/confirm_email/#{token}")

      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/settings"
      assert %{"info" => message} = flash
      assert message == "Success."
      refute Accounts.get_user_by_email(user.email)
      assert Accounts.get_user_by_email(email)

      # use confirm token again
      {:error, redirect} = live(conn, ~p"/users/settings/confirm_email/#{token}")
      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/settings"
      assert %{"error" => message} = flash
      assert message == "Failed"
    end

    test "does not update email with invalid token", %{conn: conn, user: user} do
      {:error, redirect} = live(conn, ~p"/users/settings/confirm_email/oops")
      assert {:live_redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/settings"
      assert %{"error" => message} = flash
      assert message == "Failed"
      assert Accounts.get_user_by_email(user.email)
    end

    test "redirects if user is not logged in", %{token: token} do
      conn = build_conn()
      {:error, redirect} = live(conn, ~p"/users/settings/confirm_email/#{token}")
      assert {:redirect, %{to: path, flash: flash}} = redirect
      assert path == ~p"/users/log_in"
      assert %{"error" => message} = flash
      assert message == "Failed"
    end
  end
end
