defmodule Gamend.Modules.WebRTCLobbyHook do
  @moduledoc """
  Turns WebRTC signaling on for every lobby, and tells a star host when to
  connect.

  A room *is* a lobby: `Gamend.Signaling` reads configuration from the
  lobby's `webrtc_*` columns, membership from presence, and relays over PubSub,
  so this plugin mirrors no state. It sets policy and sends one notification:

    * `after_lobby_create/1` — enables star signaling on the new lobby.
    * `after_lobby_updated/1` — closes the room if WebRTC was switched off,
      since peers would otherwise stay connected, unable to relay, never told
      why.
    * `after_lobby_deleted/1` — closes the room.
    * `after_lobby_host_change/2` — re-notifies the new star host.
      `Signaling.config/1` reads the host of the lobby, so the next join
      already sees the new one.

  The star host is notified on its user channel with `webrtc:room_ready`,
  carrying the topic to join, so a headless server-as-host connects on its own.

  Configuration goes through `Gamend.Signaling.configure/2` (see its docs);
  the star host is always `lobby.host_id`. Drop this plugin to drive
  `configure/2` yourself — for mesh rooms, or to enable signaling only once a
  match actually starts.
  """

  use Gamend.Hooks

  require Logger

  alias Gamend.Realtime
  alias Gamend.Signaling

  @room_ready_event "webrtc:room_ready"

  @doc """
  Realtime events this plugin pushes with `Gamend.Realtime.push_to_user/3`.
  """
  def realtime_events do
    %{
      @room_ready_event => "A signaling room is ready; the star host should connect to it."
    }
  end

  # Star for every lobby. Written here rather than injected into the create
  # attrs, because the `webrtc_*` columns are deliberately not castable.
  @impl true
  def after_lobby_create(lobby) do
    with {:ok, configured} <- Signaling.configure(lobby, enabled: true, topology: :star, host_id: "host_user_id") do
      ensure_room(configured)
    end

    :ok
  end

  @impl true
  def after_lobby_deleted(lobby) do
    Logger.info("WebRTC: closing signaling room for deleted lobby=#{lobby.id}")
    Signaling.close(lobby.id)
  end

  @impl true
  def after_lobby_host_change(lobby, new_host_id) do
    # Nothing to mirror: `Signaling.config/1` reads the host of the lobby, so
    # the next join already sees the new one. The notification is the only
    # side effect a headless host still needs.
    case Signaling.config(lobby.id) do
      {:ok, %{topology: :star}} ->
        Logger.info("WebRTC: star host changed lobby=#{lobby.id} host=#{new_host_id}")
        notify_host_ready(lobby.id, :star, new_host_id)

      _mesh_or_disabled ->
        :ok
    end
  end

  # ── Private helpers ─────────────────────────────────────────────────────

  # There is no room to create — `Gamend.Signaling` derives everything from
  # the lobby. All that is left is telling a star host it can connect.
  defp ensure_room(lobby) do
    case Signaling.config(lobby.id) do
      {:ok, %{topology: :star, host_user_id: host_user_id}} when is_binary(host_user_id) ->
        notify_host_ready(lobby.id, :star, host_user_id)

      {:ok, _mesh} ->
        :ok

      # WebRTC was turned off on a live lobby. Peers stay connected and tracked
      # otherwise, unable to relay anything and never told why.
      {:error, :room_not_found} ->
        Signaling.close(lobby.id)
    end
  end

  # Broadcasts a notification to the host's user channel so the headless
  # server can connect to the signaling room automatically.
  defp notify_host_ready(lobby_id, topology, host_user_id) do
    Logger.info("WebRTC: notifying host user=#{host_user_id} of ready room=#{lobby_id}")

    Realtime.push_to_user(host_user_id, @room_ready_event, %{
      "lobby_id" => lobby_id,
      "topology" => to_string(topology),
      "host_user_id" => host_user_id,
      "signaling_topic" => "signaling:#{lobby_id}"
    })

    Logger.info("WebRTC: notifying host=#{host_user_id} about signaling room lobby=#{lobby_id}")
  end
end
