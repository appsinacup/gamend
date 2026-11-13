defmodule GamendWeb.AdminSettingsController do
  @moduledoc """
  The `.env` file the settings page (`GamendWeb.AdminLive.Settings`) posts to,
  a controller because a LiveView cannot send a file. It holds the server's
  secrets in the clear, so it sits behind `:require_admin_user`, asks for a
  recent sign-in and the admin's password typed again, and no cache keeps a
  copy.
  """
  use GamendWeb, :controller

  alias Gamend.Accounts
  alias Gamend.Accounts.Scope
  alias Gamend.Settings.EnvFile

  require Logger

  def export(conn, params) do
    user = Scope.user(conn.assigns.current_scope)

    cond do
      not Accounts.sudo_mode?(user, -Accounts.sudo_mode_minutes()) ->
        # Back to the page, not this route: a sign-in answered with a file
        # would leave the browser sitting on the sign-in form.
        conn
        |> put_session(:user_return_to, ~p"/admin/settings")
        |> put_flash(:error, "Sign in again to download the settings.")
        |> redirect(to: ~p"/users/log_in")

      not password_confirmed?(user, params["password"]) ->
        Logger.warning("Admin #{user.id} was refused the settings .env: wrong password")

        conn
        |> put_flash(:error, "Wrong password. Nothing was downloaded.")
        |> redirect(to: ~p"/admin/settings")

      true ->
        Logger.warning("Admin #{user.id} downloaded the settings .env")

        conn
        |> put_resp_header("cache-control", "private, no-store")
        |> send_download({:binary, EnvFile.render()},
          filename: "gamend.env",
          content_type: "text/plain"
        )
    end
  end

  # A session left open on someone else's desk is not enough for the server's
  # secrets. An account that signs in only through a provider has no password
  # to ask for: its recent sign-in is the proof.
  defp password_confirmed?(user, password) do
    if Accounts.has_password?(user),
      do: Accounts.valid_password?(user, password),
      else: true
  end
end
