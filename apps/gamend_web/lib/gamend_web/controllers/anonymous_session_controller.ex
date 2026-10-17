defmodule GamendWeb.AnonymousSessionController do
  @moduledoc """
  `POST /users/anonymous_session`: writes into the browser's session the
  anonymous account a LiveView made for it (`GamendWeb.UserAuth.ensure_user/1`).
  `app.js` sends the encrypted token the page pushed, then reconnects the
  socket. 204 on success, 422 for a token that is missing, stale or not an
  anonymous account's.

  A 422 leaves an account the browser will never hold: its next save makes
  another one. Logged as a warning, since nothing else shows it.
  """
  use GamendWeb, :controller

  alias GamendWeb.UserAuth

  require Logger

  def create(conn, %{"token" => token}) when is_binary(token) do
    case UserAuth.put_anonymous_session(conn, token) do
      {:ok, conn} ->
        send_resp(conn, 204, "")

      :error ->
        Logger.warning("guest session not written: the token was stale, altered or not a guest's")

        send_resp(conn, 422, "")
    end
  end

  def create(conn, _params) do
    Logger.warning("guest session not written: no token sent")
    send_resp(conn, 422, "")
  end
end
