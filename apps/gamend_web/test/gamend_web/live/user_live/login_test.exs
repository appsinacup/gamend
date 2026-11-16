defmodule GamendWeb.UserLive.LoginTest do
  use GamendWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Gamend.AccountsFixtures

  describe "login page" do
    test "remember me is one checkbox, on by default, beside a single submit", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log_in")

      assert has_element?(
               lv,
               "#login_form_password input[type=checkbox][name='user[remember_me]'][checked]"
             )

      # The unchecked box must still post a value, or "false" never arrives.
      assert has_element?(
               lv,
               "#login_form_password input[type=hidden][name='user[remember_me]'][value=false]"
             )

      assert lv |> element("#login_form_password button:not([type=button])") |> render() =~
               "Log in"
    end

    test "forgot password points at the magic link", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log_in")

      assert has_element?(lv, "#forgot_password_link[phx-click]")
      assert has_element?(lv, "#forgot_password_hint.hidden", "magic link")
    end
  end

  describe "user login - magic link" do
    test "sends magic link email when user exists", %{conn: conn} do
      user = user_fixture()

      {:ok, lv, _html} = live(conn, ~p"/users/log_in")

      {:ok, _lv, html} =
        form(lv, "#login_form_magic", user: %{email: user.email})
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log_in")

      assert html =~ "If that email has an account, we sent it a login link."

      assert Gamend.Repo.get_by!(Gamend.Accounts.UserToken, user_id: user.id).context ==
               "login"
    end

    test "does not disclose if user is registered", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log_in")

      {:ok, _lv, html} =
        form(lv, "#login_form_magic", user: %{email: "idonotexist@example.com"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/users/log_in")

      assert html =~ "If that email has an account, we sent it a login link."
    end
  end

  describe "user login - password" do
    test "redirects if user logs in with valid credentials", %{conn: conn} do
      user = user_fixture() |> set_password()

      {:ok, lv, _html} = live(conn, ~p"/users/log_in")

      form =
        form(lv, "#login_form_password",
          user: %{email: user.email, password: valid_user_password(), remember_me: true}
        )

      conn = submit_form(form, conn)

      assert redirected_to(conn) == ~p"/"
    end

    test "redirects to login page with a flash error if credentials are invalid", %{
      conn: conn
    } do
      {:ok, lv, _html} = live(conn, ~p"/users/log_in")

      form =
        form(lv, "#login_form_password", user: %{email: "test@email.com", password: "123456"})

      render_submit(form, %{user: %{remember_me: true}})

      conn = follow_trigger_action(form, conn)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Failed"
      assert redirected_to(conn) == ~p"/users/log_in"
    end
  end

  describe "login navigation" do
    test "redirects to registration page when the Register button is clicked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log_in")

      {:ok, _login_live, login_html} =
        lv
        |> element("main a", "Register")
        |> render_click()
        |> follow_redirect(conn, ~p"/users/register")

      assert login_html =~ "Register"
    end
  end

  describe "re-authentication (sudo mode)" do
    setup %{conn: conn} do
      user = user_fixture()
      %{user: user, conn: log_in_user(conn, user)}
    end

    test "shows login page with email filled in", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/log_in")

      refute has_element?(lv, "main a", "Register")
      assert has_element?(lv, ~s(#login_form_magic_email[type=email][value="#{user.email}"]))
    end
  end
end
