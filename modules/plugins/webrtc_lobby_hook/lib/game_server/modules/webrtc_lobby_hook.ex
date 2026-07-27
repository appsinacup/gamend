defmodule GameServer.Modules.WebRTCLobbyHook do
  @moduledoc """
  Keeps a WebRTC signaling room in sync with a lobby.

  This is the only module that connects the lobby system to the WebRTC
  signaling layer. When a lobby has `metadata.webrtc.enabled = true`, a
  signaling room with the same id as the lobby is created automatically.
  The room is closed when the lobby is deleted, and the allowed-user list
  is kept in sync with lobby joins and leaves.

  When a star-topology room is created, the designated host is notified on
  its user channel (`user:<host_user_id>`) with a `webrtc:room_ready` event
  so a headless server can connect automatically.

  Configuration is read from `lobby.metadata.webrtc`:

      %{
        "enabled" => true,
        "topology" => "star" | "mesh",
        "late_join" => true,
        "reconnect_timeout" => 30000,
        "host_user_id" => "optional-server-user-id"
      }

  In `:star` mode the host is resolved in this order:
    1. `metadata.webrtc.host_user_id`
    2. `lobby.host_id`

  The allowed-user list is seeded from the lobby members at creation time.
  Late joiners are added via `after_lobby_join/2`.
  """

  use GameServer.Hooks

  require Logger

  alias GameServer.Signaling
  alias GameServer.Lobbies
  alias GameServerWeb.Endpoint

  # Force WebRTC Star for all lobbies.
  @impl true
  def before_lobby_create(attrs) do
    metadata = Map.get(attrs, :metadata) || Map.get(attrs, "metadata") || %{}

    metadata =
      Map.new(metadata, fn {k, v} ->
        {to_string(k), v}
      end)

    webrtc_meta = %{
      "webrtc" => %{
        "enabled" => true,
        "topology" => "star",
        "late_join" => true,
        "reconnect_timeout" => 30000,
        "host_user_id" => "example_host_id"
      }
    }

    new_metadata = Map.merge(metadata, webrtc_meta)

    metadata_key =
      cond do
        Map.has_key?(attrs, "metadata") -> "metadata"
        Map.has_key?(attrs, :metadata) -> :metadata
        true -> "metadata"
      end

    new_attrs = Map.put(attrs, metadata_key, new_metadata)

    {:ok, new_attrs}
  end

  @impl true
  def after_lobby_create(lobby) do
    ensure_room(lobby)
  end

  @impl true
  def after_lobby_updated(lobby) do
    # If WebRTC is enabled later, create the room. If disabled, close it.
    ensure_room(lobby)
  end

  @impl true
  def after_lobby_deleted(lobby) do
    Logger.info("WebRTC: closing signaling room for deleted lobby=#{lobby.id}")
    Signaling.close_room(lobby.id)
  end

  @impl true
  def after_lobby_join(user, lobby) do
    # Late join: allow the user into the signaling room.
    role = role_for(user.id, lobby)
    Logger.info("WebRTC: late join allowed lobby=#{lobby.id} user=#{user.id} role=#{role}")
    Signaling.allow_user(lobby.id, user.id, role)
  end

  @impl true
  def after_lobby_leave(user, lobby) do
    Logger.info("WebRTC: user left lobby, removing from signaling room lobby=#{lobby.id} user=#{user.id}")
    Signaling.disallow_user(lobby.id, user.id)
  end

  @impl true
  def after_lobby_host_change(lobby, new_host_id) do
    # In star topology, update the host user id when the lobby host changes.
    with {:ok, %{topology: :star}} <- Signaling.get_room(lobby.id) do
      Logger.info("WebRTC: updating star host lobby=#{lobby.id} host=#{new_host_id}")
      Signaling.allow_user(lobby.id, new_host_id, :host)
      Signaling.update_room_host(lobby.id, new_host_id)
      notify_host_ready(lobby.id, :star, new_host_id)
    else
      _ -> :ok
    end
  end

  # ── Private helpers ─────────────────────────────────────────────────────

  defp ensure_room(lobby) do
    with %{"webrtc" => %{"enabled" => true, "topology" => topology}} <- lobby.metadata,
         topology_atom <- parse_topology(topology),
         {:ok, host_user_id} <- resolve_host(lobby, topology_atom) do
      if Signaling.exists_room?(lobby.id) do
        :ok
      else
        allowed_users = build_allowed_users(lobby, host_user_id, topology_atom)
        late_join = get_in(lobby.metadata, ["webrtc", "late_join"]) || true
        reconnect_timeout = get_in(lobby.metadata, ["webrtc", "reconnect_timeout"]) || 30_000

        Logger.info("WebRTC: creating signaling room lobby=#{lobby.id} topology=#{topology} host=#{host_user_id} allowed_users=#{map_size(allowed_users)}")

        :ok = Signaling.create_room(lobby.id, topology_atom,
          host_user_id: host_user_id,
          allowed_users: allowed_users,
          late_join: late_join,
          reconnect_timeout: reconnect_timeout
        )

        # Notify the host so a headless server can join automatically.
        if topology_atom == :star do
          notify_host_ready(lobby.id, topology_atom, host_user_id)
        end

        :ok
      end
    else
      _ ->
        # WebRTC not enabled or invalid config; close room if it exists.
        if Signaling.exists_room?(lobby.id) do
          Signaling.close_room(lobby.id)
        end

        :ok
    end
  end

  # Broadcasts a notification to the host's user channel so the headless
  # server can connect to the signaling room automatically.
  defp notify_host_ready(lobby_id, topology, host_user_id) do
    Logger.info("WebRTC: notifying host user=#{host_user_id} of ready room=#{lobby_id}")

    Endpoint.broadcast("user:#{host_user_id}", "webrtc:room_ready", %{
      "lobby_id" => lobby_id,
      "topology" => to_string(topology),
      "host_user_id" => host_user_id,
      "signaling_topic" => "signaling:#{lobby_id}"
    })

    Logger.info("WebRTC: notifying host=#{host_user_id} about signaling room lobby=#{lobby_id}")
  end

  defp build_allowed_users(lobby, host_user_id, topology) do
    # Returns lobby members to build the list of allowed users.
    members = Lobbies.get_lobby_members(lobby)

    # Convert everything to strings so Ecto UUIDs, binaries and atoms all
    # interop cleanly. The host_user_id is always forced to :host.
    host_id = to_string(host_user_id)

    users =
      Map.new(members, fn member ->
        id = to_string(member.id)

        role =
          cond do
            topology == :star and id == host_id -> :host
            topology == :star -> :client
            true -> :user
          end

        {id, role}
      end)

    # Ensure the dedicated host is allowed even if it is not a lobby member.
    # This is critical for headless servers that never join the lobby itself.
    users =
      if topology == :star and is_binary(host_user_id) and host_user_id != "" do
        Map.put(users, host_id, :host)
      else
        users
      end

    Logger.info("WebRTC: build_allowed_users host=#{host_id} users=#{inspect(users)}")
    users
  end

  defp role_for(user_id, lobby) do
    webrtc = lobby.metadata["webrtc"] || %{}
    topology = parse_topology(webrtc["topology"] || "mesh")
    host_user_id = webrtc["host_user_id"] || lobby.host_id

    cond do
      topology == :star and to_string(user_id) == to_string(host_user_id) -> :host
      topology == :star -> :client
      true -> :user
    end
  end

  defp resolve_host(%{metadata: %{"webrtc" => %{"host_user_id" => host_id}}}, :star)
       when is_binary(host_id) and host_id != "",
       do: {:ok, host_id}

  defp resolve_host(%{host_id: host_id}, :star)
       when is_binary(host_id) and host_id != "",
       do: {:ok, host_id}

  defp resolve_host(_, :star), do: {:error, :no_host_for_star}
  defp resolve_host(_, :mesh), do: {:ok, nil}

  defp parse_topology("star"), do: :star
  defp parse_topology("mesh"), do: :mesh

  defp parse_topology(other) do
    Logger.warning("WebRTC: unknown topology=#{other}, defaulting to mesh")
    :mesh
  end
end
