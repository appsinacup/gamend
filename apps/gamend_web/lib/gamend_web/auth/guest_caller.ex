defmodule GamendWeb.Auth.GuestCaller do
  @moduledoc """
  The guest a sign-in comes from, on the API's sign-in routes.

  A game client signed in as a guest (`Gamend.Accounts.User.anonymous?/1`)
  that logs in to an account, registers one or signs in with a provider
  sends the guest's access token as usual. This assigns that guest as
  `conn.assigns.guest`, so the sign-in merges what the guest did into the
  account (`GamendWeb.UserAuth.merge_guest/2`), as the website's sign-in
  does with its session.

  Nothing else changes: a request with no token, a token that is invalid,
  expired or revoked, or one of an account that is no guest signs in as it
  always did, with no merge. The routes are sign-ins, so a stale token is
  never a reason to refuse one.
  """

  import Plug.Conn

  alias Gamend.Accounts.User

  require GamendWeb.Auth.TokenType, as: TokenType

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, %User{} = user, _claims} <-
           Guardian.resource_from_token(GamendWeb.Auth.Guardian, token, %{
             "typ" => TokenType.access()
           }),
         true <- User.anonymous?(user) do
      assign(conn, :guest, user)
    else
      _no_guest -> conn
    end
  end
end
