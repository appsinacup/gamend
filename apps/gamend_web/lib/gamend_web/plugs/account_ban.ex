defmodule GamendWeb.Plugs.AccountBan do
  @moduledoc """
  Refuses an API request made by a banned account (`Gamend.Bans`, kind
  `:account`): 403 `account_banned`. The ban's end and reason are in
  `GET /me`, which a banned account can still read.

  It runs in the `:api_auth` and `:api_optional_auth` pipelines, after the
  caller is known, so every authenticated call is covered, a personal API
  token's too. A banned account keeps what `:api_auth_while_banned` routes:
  reading itself (`GET /me`, which carries the ban) and deleting itself.
  Signing in, refreshing and signing out are unauthenticated routes, so a
  banned player can still log in and see why.

  The check is an ETS read, no query.
  """

  import Plug.Conn

  alias Gamend.Accounts.Scope
  alias Gamend.Bans

  require GamendWeb.ChannelError, as: ChannelError

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    with user_id when is_binary(user_id) <- Scope.user_id(conn.assigns[:current_scope]),
         true <- Bans.banned?(:account, user_id) do
      body = %{
        error: ChannelError.account_banned(),
        message: "This account is banned; GET /api/v1/me says why."
      }

      conn
      |> put_resp_content_type("application/json")
      |> send_resp(403, Jason.encode!(body))
      |> halt()
    else
      _ -> conn
    end
  end
end
