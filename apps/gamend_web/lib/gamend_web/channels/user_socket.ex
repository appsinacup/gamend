defmodule GamendWeb.UserSocket do
  use Phoenix.Socket

  require Logger

  alias Gamend.Accounts.Scope
  alias GamendWeb.Auth.Guardian
  alias GamendWeb.Plugs.ClientSession

  require Gamend.RealtimeEvent, as: RealtimeEvent
  require GamendWeb.Auth.TokenType, as: TokenType
  require GamendWeb.WsFormat, as: WsFormat

  # A Socket handler
  #
  # It's possible to control the websocket connection and
  # assign values that can be accessed by your channel topics.

  ## Channels
  #
  # Declared as data so the list is enumerable (Phoenix's `channel` macro only
  # generates a `__channel__/1` dispatch head). The startup banner and the
  # admin runtime page read `__channels__/0`.
  @channels [
    {"user:*", GamendWeb.UserChannel,
     "Per-user events: profile, notifications, invites, KV, matchmaking, tournaments"},
    {"lobby:*", GamendWeb.LobbyChannel, "One lobby: state, membership, chat, WebRTC signalling"},
    {"lobbies", GamendWeb.LobbiesChannel,
     "Global lobby list: created/updated/deleted, membership counts"},
    {"group:*", GamendWeb.GroupChannel, "One group: state, members, join requests, chat"},
    {"groups", GamendWeb.GroupsChannel, "Global group list: created/updated/deleted"},
    {"party:*", GamendWeb.PartyChannel, "One party: state, members, chat, disband"},
    {"signaling:*", GamendWeb.SignalingChannel, "Signaling channel for WebRTC"}
  ]

  for {pattern, module, _description} <- @channels do
    channel(pattern, module)
  end

  @doc "All channel routes as `{topic_pattern, module, description}`."
  def __channels__, do: @channels

  # Socket params are passed from the client and can
  # be used to verify and authenticate a user. After
  # verification, you can put default assigns into
  # the socket that will be set for all channels, ie
  #
  #     {:ok, assign(socket, :user_id, verified_user_id)}
  #
  # To deny connection, return `:error` or `{:error, term}`. To control the
  # response the client receives in that case, [define an error handler in the
  # websocket
  # configuration](https://hexdocs.pm/phoenix/Phoenix.Endpoint.html#socket/3-websocket-configuration).
  #
  # See `Phoenix.Token` documentation for examples in
  # performing token verification on connect.
  @impl true
  # Generic connect that attempts to extract a token from a variety of
  # param shapes (plain map, nested under "params" or :params, etc.).
  # Unauthenticated connections are rejected (connection-exhaustion DoS
  # guard) — all channel functionality requires a valid JWT token — and
  # each user may hold at most :max_sockets_per_user concurrent sockets, and
  # the server at most :max_sockets in all.
  def connect(params, socket, _connect_info) do
    with token when is_binary(token) <- extract_token(params),
         # Access tokens only: a refresh token is a 30-day credential and must
         # not open a socket. Matches the two HTTP pipelines.
         {:ok, claims} <- Guardian.decode_and_verify(token, %{"typ" => TokenType.access()}),
         {:ok, user} <- Guardian.resource_from_claims(claims),
         false <- socket_limit_reached?(user.id),
         false <- server_full?() do
      format = extract_format(params, socket)
      _ = warn_on_format_downgrade(params, format, user.id)

      GamendWeb.ConnectionTracker.register_ws_socket(user.id, %{
        user_id: user.id,
        authenticated: true,
        # Surfaced on the admin Runtime page: "is this client actually getting
        # protobuf" is otherwise unanswerable from the server side, and the
        # answer is not the same as what the client asked for.
        format: format
      })

      client_session = ClientSession.sanitize(extract_client_session(params))
      ClientSession.put_metadata(client_session)

      socket =
        socket
        |> assign(:current_scope, Scope.for_user(user))
        |> assign(:ws_format, format)
        |> assign(:client_session_id, client_session)

      {:ok, socket}
    else
      _ -> :error
    end
  end

  @doc """
  `{:error, %{reason: "account_banned"}}` when the socket's account is banned
  (`Gamend.Bans`), else `:ok`.

  A banned account still connects, so it hears `account_banned` and
  `account_unbanned` on its user channel. Every other channel refuses it at
  join, and the user channel refuses its actions (hook calls, KV
  subscriptions, WebRTC). A ban placed while it is connected closes the
  socket (`GamendWeb.AccountBanKicks`), so what it had joined is left too.
  """
  @spec refuse_banned(Phoenix.Socket.t()) :: :ok | {:error, %{reason: String.t()}}
  def refuse_banned(socket) do
    with user_id when is_binary(user_id) <- Scope.user_id(socket.assigns[:current_scope]),
         true <- Gamend.Bans.banned?(:account, user_id) do
      {:error, %{reason: RealtimeEvent.account_banned()}}
    else
      _ -> :ok
    end
  end

  # The client's log session id, carried so server lines logged for this socket
  # correlate with the client's own uploaded lines. Same param shapes as the
  # token and format, because clients differ in how they nest connect params.
  defp extract_client_session(%{params: %{"client_session" => v}}), do: v
  defp extract_client_session(%{"params" => %{"client_session" => v}}), do: v
  defp extract_client_session(%{"client_session" => v}), do: v
  defp extract_client_session(_), do: nil

  # Server->client event payload format: "json" (default) or "protobuf".
  # Protobuf events are delivered as binary frames encoded per
  # proto/gamend_realtime.proto; client->server pushes remain JSON.
  defp extract_format(%{params: %{"format" => f}}, socket), do: normalize_format(f, socket)
  defp extract_format(%{"params" => %{"format" => f}}, socket), do: normalize_format(f, socket)
  defp extract_format(%{"format" => f}, socket), do: normalize_format(f, socket)
  defp extract_format(_, _socket), do: WsFormat.json()

  # The format the client ASKED for, before the serializer veto below.
  defp requested_format(%{params: %{"format" => f}}), do: f
  defp requested_format(%{"params" => %{"format" => f}}), do: f
  defp requested_format(%{"format" => f}), do: f
  defp requested_format(_params), do: nil

  # A client asking for protobuf and silently getting JSON is the one failure
  # here with no other symptom: everything keeps working, just uncompressed and
  # with every binary decoder on the client idle. Almost always a missing
  # `vsn=2.0.0` on the socket URL.
  defp warn_on_format_downgrade(params, WsFormat.json(), user_id) do
    if requested_format(params) == WsFormat.protobuf() do
      Logger.info(
        "ws socket: protobuf requested but the connection negotiated the v1 " <>
          "serializer, which cannot carry binary frames — falling back to JSON " <>
          "(user_id=#{user_id}). Check the socket URL sends vsn=2.0.0."
      )
    end
  end

  defp warn_on_format_downgrade(_params, _format, _user_id), do: :ok

  # Binary frames require the V2 channel protocol; the V1 serializer (vsn
  # 1.x, the Phoenix default) cannot emit them, so "protobuf" is only
  # honored on sockets that negotiated a binary-capable serializer.
  defp normalize_format(WsFormat.protobuf(), %{serializer: serializer})
       when serializer != Phoenix.Socket.V1.JSONSerializer,
       do: WsFormat.protobuf()

  defp normalize_format(_, _), do: WsFormat.json()

  # 0 disables; counted per app instance.
  #
  # Counted from the per-user registry key, not by filtering every registered
  # socket: the latter walked a list of every connection on the node on each
  # new connection, which made a reconnect storm quadratic.
  defp socket_limit_reached?(user_id) do
    limit = Gamend.Limits.get(:max_sockets_per_user)

    is_integer(limit) and limit > 0 and
      GamendWeb.ConnectionTracker.count_ws_sockets(user_id) >= limit
  end

  # Every user's sockets together, against `:max_sockets`: what a host
  # sells a server by. 0 disables; counted per app instance.
  defp server_full? do
    limit = Gamend.Limits.get(:max_sockets)

    is_integer(limit) and limit > 0 and
      GamendWeb.ConnectionTracker.count_all_ws_sockets() >= limit
  end

  # Extract token from various parameter shapes:
  # - ChannelTest passes %{params: %{"token" => ...}, ...}
  # - Real WebSocket might pass %{"token" => ...} directly
  defp extract_token(%{params: %{"token" => token}}), do: token
  defp extract_token(%{"params" => %{"token" => token}}), do: token
  defp extract_token(%{"token" => token}), do: token
  defp extract_token(%{token: token}), do: token
  defp extract_token(_), do: nil

  # Return a user-scoped socket ID so we can force-disconnect a specific user:
  #
  #     GamendWeb.Endpoint.broadcast("user_socket:#{user.id}", "disconnect", %{})
  #
  @impl true
  def id(socket) do
    case socket.assigns[:current_scope] do
      %{user_id: user_id} -> "user_socket:#{user_id}"
      _ -> nil
    end
  end
end
