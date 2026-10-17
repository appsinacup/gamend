defmodule GamendWeb.UserLive.ConfirmationTest do
  use GamendWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Gamend.AccountsFixtures

  alias Gamend.Accounts

  setup do
    %{unconfirmed_user: unconfirmed_user_fixture(), confirmed_user: user_fixture()}
  end

  describe "Confirm user" do
    test "renders confirmation page for unconfirmed user", %{conn: conn, unconfirmed_user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_login_instructions(user, url)
        end)

      {:ok, lv, html} = live(conn, ~p"/users/log_in/#{token}")
      assert html =~ "Confirm"
      refute has_element?(lv, "#confirmation-password-notice")
    end

    test "says a password set before confirming goes away", %{
      conn: conn,
      unconfirmed_user: user
    } do
      user = set_password(user)

      token =
        extract_user_token(fn url ->
          Accounts.deliver_login_instructions(user, url)
        end)

      {:ok, lv, _html} = live(conn, ~p"/users/log_in/#{token}")
      assert has_element?(lv, "#confirmation_form #confirmation-password-notice")
    end

    test "renders login page for confirmed user", %{conn: conn, confirmed_user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_login_instructions(user, url)
        end)

      {:ok, _lv, html} = live(conn, ~p"/users/log_in/#{token}")
      refute html =~ "Confirm my account"
      assert html =~ "Log in"
      assert html =~ user.email
    end

    test "confirms the given token once", %{conn: conn, unconfirmed_user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_login_instructions(user, url)
        end)

      {:ok, lv, _html} = live(conn, ~p"/users/log_in/#{token}")

      form = form(lv, "#confirmation_form", %{"user" => %{"token" => token}})
      render_submit(form)

      conn = follow_trigger_action(form, conn)

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Success."

      assert Accounts.get_user!(user.id).confirmed_at
      # we are logged in now
      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"

      # log out, new conn
      conn = build_conn()

      {:ok, _lv, html} =
        live(conn, ~p"/users/log_in/#{token}")
        |> follow_redirect(conn, ~p"/users/log_in")

      assert html =~ "Failed"
    end

    test "logs confirmed user in without changing confirmed_at", %{
      conn: conn,
      confirmed_user: user
    } do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_login_instructions(user, url)
        end)

      {:ok, lv, _html} = live(conn, ~p"/users/log_in/#{token}")

      form = form(lv, "#login_form", %{"user" => %{"token" => token}})
      render_submit(form)

      conn = follow_trigger_action(form, conn)

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Success."

      assert Accounts.get_user!(user.id).confirmed_at == user.confirmed_at

      # log out, new conn
      conn = build_conn()

      {:ok, _lv, html} =
        live(conn, ~p"/users/log_in/#{token}")
        |> follow_redirect(conn, ~p"/users/log_in")

      assert html =~ "Failed"
    end

    test "raises error for invalid token", %{conn: conn} do
      {:ok, _lv, html} =
        live(conn, ~p"/users/log_in/invalid-token")
        |> follow_redirect(conn, ~p"/users/log_in")

      assert html =~ "Failed"
    end
  end

  describe "the confirmation email's link" do
    defp confirm_token(user) do
      {encoded, user_token} = Accounts.UserToken.build_email_token(user, "confirm")
      Gamend.Repo.insert!(user_token)
      encoded
    end

    test "opening it confirms nothing; its button does", %{conn: conn, unconfirmed_user: user} do
      token = confirm_token(user)

      {:ok, lv, _html} = live(conn, ~p"/users/confirm/#{token}")
      assert has_element?(lv, "#confirmation_form")
      refute has_element?(lv, "#login_form")
      refute Accounts.get_user!(user.id).confirmed_at

      form = form(lv, "#confirmation_form", %{"user" => %{"token" => token}})
      render_submit(form)
      conn = follow_trigger_action(form, conn)

      assert redirected_to(conn) == ~p"/users/settings"
      assert get_session(conn, :user_token)
      assert Accounts.get_user!(user.id).confirmed_at
    end

    test "says a password set before confirming goes away", %{
      conn: conn,
      unconfirmed_user: user
    } do
      token = user |> set_password() |> confirm_token()

      {:ok, lv, _html} = live(conn, ~p"/users/confirm/#{token}")
      assert has_element?(lv, "#confirmation_form #confirmation-password-notice")
    end

    test "a spent or unknown link goes to the login page", %{conn: conn, unconfirmed_user: user} do
      token = confirm_token(user)
      {:ok, _} = Accounts.confirm_user_by_token(token)

      {:ok, _lv, html} =
        live(conn, ~p"/users/confirm/#{token}")
        |> follow_redirect(conn, ~p"/users/log_in")

      assert html =~ "Failed"
    end
  end
end
