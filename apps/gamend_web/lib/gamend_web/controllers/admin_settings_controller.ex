defmodule GamendWeb.AdminSettingsController do
  @moduledoc """
  The `.env` file the settings page (`GamendWeb.AdminLive.Settings`) links to,
  a controller because a LiveView cannot send a file. It holds the server's
  secrets in the clear, so it sits behind `:require_admin_user`, asks for a
  recent sign-in, and no cache keeps a copy.
  """
  use GamendWeb, :controller

  alias Gamend.Accounts
  alias Gamend.Accounts.Scope
  alias Gamend.Settings.EnvFile

  require Logger

  def export(conn, _params) do
    user = Scope.user(conn.assigns.current_scope)

    if Accounts.sudo_mode?(user, -Accounts.sudo_mode_minutes()) do
      Logger.info("Admin #{user.id} downloaded the settings .env")

      conn
      |> put_resp_header("cache-control", "private, no-store")
      |> send_download({:binary, EnvFile.render()},
        filename: "gamend.env",
        content_type: "text/plain"
      )
    else
      # Back to the page, not this route: a sign-in answered with a file would
      # leave the browser sitting on the sign-in form.
      conn
      |> put_session(:user_return_to, ~p"/admin/settings")
      |> put_flash(:error, "Sign in again to download the settings.")
      |> redirect(to: ~p"/users/log_in")
    end
  end
end
