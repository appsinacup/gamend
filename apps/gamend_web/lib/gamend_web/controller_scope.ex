defmodule GamendWeb.ControllerScope do
  @moduledoc """
  Resolving "who is asking, and what are they in" once per request.

  `with_user/2`, `with_lobby/2` and `with_party/2` each answer the request
  themselves when the precondition fails, so a controller action reads as the
  happy path and nothing else:

      def create(conn, params) do
        with_lobby(conn, fn user, lobby -> ... end)
      end

  `with_lobby/2` and `with_party/2` were byte-identical in the chat-mute and
  ready-check controllers, which is what prompted this; `with_user/2` came
  along because they are built on it and splitting them would have left the
  same duplication one level down.
  """

  import GamendWeb.Reply, only: [reply_error: 3]

  alias Gamend.Accounts.Scope
  alias Gamend.Accounts.User
  alias Gamend.Lobbies
  alias Gamend.Parties

  @doc "Runs `fun` with the signed-in user, or replies 401."
  @spec with_user(Plug.Conn.t(), (User.t() -> Plug.Conn.t())) :: Plug.Conn.t()
  def with_user(conn, fun) do
    case Scope.user(conn.assigns[:current_scope]) do
      %User{} = user -> fun.(user)
      _ -> reply_error(conn, :unauthorized, "not_authenticated")
    end
  end

  @doc "Runs `fun` with the user and the lobby they are in, or replies 401/404."
  @spec with_lobby(Plug.Conn.t(), (User.t(), Lobbies.Lobby.t() -> Plug.Conn.t())) :: Plug.Conn.t()
  def with_lobby(conn, fun) do
    # The signed-in user can be a cached copy, still naming a lobby since deleted.
    with_user(conn, fn user ->
      case user.lobby_id && Lobbies.get_lobby(user.lobby_id) do
        %Lobbies.Lobby{} = lobby -> fun.(user, lobby)
        _ -> reply_error(conn, :not_found, "not_in_lobby")
      end
    end)
  end

  @doc "Runs `fun` with the user and the party they are in, or replies 401/404."
  @spec with_party(Plug.Conn.t(), (User.t(), Parties.Party.t() -> Plug.Conn.t())) :: Plug.Conn.t()
  def with_party(conn, fun) do
    with_user(conn, fn user ->
      case user.party_id && Parties.get_party(user.party_id) do
        %Parties.Party{} = party -> fun.(user, party)
        _ -> reply_error(conn, :not_found, "not_in_party")
      end
    end)
  end
end
