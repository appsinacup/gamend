defmodule GamendWeb.UserSessionControllerTest do
  use GamendWeb.ConnCase, async: true

  import Gamend.AccountsFixtures
  alias Gamend.Accounts

  setup do
    %{unconfirmed_user: unconfirmed_user_fixture(), user: user_fixture()}
  end

  describe "POST /users/log_in - email and password" do
    test "logs the user in", %{conn: conn, user: user} do
      user = set_password(user)

      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"

      # Now do a logged in request and assert on the menu
      conn = get(conn, ~p"/")
      response = html_response(conn, 200)
      assert response =~ ~p"/users/settings"
      assert response =~ ~p"/users/log_out"
    end

    test "logs the user in with remember me", %{conn: conn, user: user} do
      user = set_password(user)

      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password(),
            "remember_me" => "true"
          }
        })

      assert conn.resp_cookies["_gamend_web_user_remember_me"]
      assert redirected_to(conn) == ~p"/"
    end

    test "logs the user in with return to", %{conn: conn, user: user} do
      user = set_password(user)

      conn =
        conn
        |> init_test_session(user_return_to: "/foo/bar")
        |> post(~p"/users/log_in", %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password()
          }
        })

      assert redirected_to(conn) == "/foo/bar"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Success."
    end

    test "refuses the right password until the email is confirmed", %{
      conn: conn,
      unconfirmed_user: user
    } do
      user = set_password(user)

      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      refute get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/users/log_in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Confirm your email first"
    end

    test "a wrong password on an unconfirmed email says only Failed", %{
      conn: conn,
      unconfirmed_user: user
    } do
      user = set_password(user)

      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"email" => user.email, "password" => "invalid_password"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Failed"
    end

    test "redirects to login page with invalid credentials", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log_in?mode=password", %{
          "user" => %{"email" => user.email, "password" => "invalid_password"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Failed"
      assert redirected_to(conn) == ~p"/users/log_in"
    end
  end

  describe "POST /users/log_in - magic link" do
    test "logs the user in", %{conn: conn, user: user} do
      {token, _hashed_token} = generate_user_magic_link_token(user)

      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"token" => token}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"

      # Now do a logged in request and assert on the menu
      conn = get(conn, ~p"/")
      response = html_response(conn, 200)
      assert response =~ ~p"/users/settings"
      assert response =~ ~p"/users/log_out"
    end

    test "confirms unconfirmed user", %{conn: conn, unconfirmed_user: user} do
      {token, _hashed_token} = generate_user_magic_link_token(user)
      refute user.confirmed_at

      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"token" => token},
          "_action" => "confirmed"
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Success."

      assert Accounts.get_user!(user.id).confirmed_at

      # Now do a logged in request and assert on the menu
      conn = get(conn, ~p"/")
      response = html_response(conn, 200)
      assert response =~ ~p"/users/settings"
      assert response =~ ~p"/users/log_out"
    end

    test "confirms an unconfirmed user with a password, and removes the password", %{
      conn: conn,
      unconfirmed_user: user
    } do
      user = set_password(user)
      {token, _hashed_token} = generate_user_magic_link_token(user)

      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"token" => token},
          "_action" => "confirmed"
        })

      assert get_session(conn, :user_token)
      assert %{confirmed_at: %DateTime{}, hashed_password: nil} = Accounts.get_user!(user.id)
    end

    test "redirects to login page when magic link is invalid", %{conn: conn} do
      conn =
        post(conn, ~p"/users/log_in", %{
          "user" => %{"token" => "invalid"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Failed"

      assert redirected_to(conn) == ~p"/users/log_in"
    end

    test "POST /users/confirm confirms an unconfirmed user and signs them in", %{
      conn: conn,
      unconfirmed_user: user
    } do
      {encoded_token, user_token} = Accounts.UserToken.build_email_token(user, "confirm")
      Gamend.Repo.insert!(user_token)

      conn = post(conn, ~p"/users/confirm", %{"user" => %{"token" => encoded_token}})

      # Signed in and sent to settings, where the account sets a password.
      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/users/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Success."

      assert Accounts.get_user!(user.id).confirmed_at
    end

    test "POST /users/confirm removes a password set before the email was confirmed", %{
      conn: conn,
      unconfirmed_user: user
    } do
      user = set_password(user)
      {encoded_token, user_token} = Accounts.UserToken.build_email_token(user, "confirm")
      Gamend.Repo.insert!(user_token)

      post(conn, ~p"/users/confirm", %{"user" => %{"token" => encoded_token}})

      assert %{confirmed_at: %DateTime{}, hashed_password: nil} = Accounts.get_user!(user.id)

      conn =
        post(build_conn(), ~p"/users/log_in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      refute get_session(conn, :user_token)
    end

    test "POST /users/confirm handles an invalid token", %{conn: conn} do
      conn = post(conn, ~p"/users/confirm", %{"user" => %{"token" => "invalid-token"}})

      assert redirected_to(conn) == ~p"/users/log_in"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Failed"
    end
  end

  describe "DELETE /users/log_out" do
    test "logs the user out", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> delete(~p"/users/log_out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Success."
    end

    test "succeeds even if the user is not logged in", %{conn: conn} do
      conn = delete(conn, ~p"/users/log_out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Success."
    end
  end
end
