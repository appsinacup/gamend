defmodule GameServerWeb.UserSessionController do
  use GameServerWeb, :controller

  alias GameServer.Accounts
  alias GameServer.Accounts.Scope
  alias GameServerWeb.UserAuth

  def create(conn, %{"_action" => "confirmed"} = params) do
    create(conn, params, gettext("Success."))
  end

  def create(conn, params) do
    create(conn, params, gettext("Success."))
  end

  # magic link login
  defp create(conn, %{"user" => %{"token" => token} = user_params}, info) do
    case Accounts.login_user_by_magic_link(token) do
      {:ok, {user, tokens_to_disconnect}} ->
        if Accounts.user_activated?(user) do
          UserAuth.disconnect_sessions(tokens_to_disconnect)

          conn
          |> put_flash(:info, info)
          |> UserAuth.log_in_user(user, user_params)
        else
          conn
          |> put_flash(:error, gettext("Your account is pending activation."))
          |> redirect(to: ~p"/users/log_in")
        end

      _ ->
        conn
        |> put_flash(:error, gettext("Failed"))
        |> redirect(to: ~p"/users/log_in")
    end
  end

  # email + password login
  defp create(conn, %{"user" => user_params}, info) do
    %{"email" => email, "password" => password} = user_params

    if user = Accounts.get_user_by_email_and_password(email, password) do
      if Accounts.user_activated?(user) do
        conn
        |> put_flash(:info, info)
        |> UserAuth.log_in_user(user, user_params)
      else
        conn
        |> put_flash(:error, gettext("Your account is pending activation."))
        |> redirect(to: ~p"/users/log_in")
      end
    else
      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      conn
      |> put_flash(:error, gettext("Failed"))
      |> put_flash(:email, String.slice(email, 0, 160))
      |> redirect(to: ~p"/users/log_in")
    end
  end

  def update_password(conn, %{"user" => user_params} = params) do
    user = Scope.user(conn.assigns.current_scope)

    if Accounts.sudo_mode?(user) do
      {:ok, {_user, expired_tokens}} = Accounts.update_user_password(user, user_params)

      # disconnect all existing LiveViews with old sessions
      UserAuth.disconnect_sessions(expired_tokens)

      conn
      |> put_session(:user_return_to, ~p"/users/settings")
      |> create(params, gettext("Success."))
    else
      conn
      |> put_flash(:error, gettext("Failed"))
      |> redirect(to: ~p"/users/log_in")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, gettext("Success."))
    |> UserAuth.log_out_user()
  end

  def confirm(conn, %{"token" => token}) do
    case Accounts.confirm_user_by_token(token) do
      {:ok, user} ->
        if Accounts.user_activated?(user) do
          # Auto-login the user after successful confirmation and send them to settings
          conn
          |> put_session(:user_return_to, ~p"/users/settings")
          |> put_flash(:info, gettext("Success."))
          |> UserAuth.log_in_user(user, %{})
        else
          conn
          |> put_flash(:info, gettext("Your account is pending activation."))
          |> redirect(to: ~p"/users/log_in")
        end

      _ ->
        conn
        |> put_flash(:error, gettext("Failed"))
        |> redirect(to: ~p"/users/log_in")
    end
  end
end
