defmodule Gamend.Modules.WebRTCLobbyHook do
  @moduledoc """
  Enables WebRTC signaling for every lobby.

  A room *is* a lobby: `Gamend.Signaling` reads configuration from the lobby's
  `webrtc_*` columns, membership from `Gamend.Presence`, and relays over
  PubSub, so this plugin mirrors no state. It sets a default policy and sends
  one notification.

  ## What this plugin does

    * `after_lobby_create/1` — enables **mesh** signaling on the new lobby.
    * `after_lobby_updated/1` — closes the room if WebRTC was switched off,
      since peers would otherwise stay connected, unable to relay, never told
      why.
    * `after_lobby_deleted/1` — closes the room.
    * `after_lobby_host_change/2` — re-notifies the star host when the lobby
      uses star topology.

  ## Changing the default topology

  This plugin is a convenience default. You can change the topology by
  calling `Gamend.Signaling.configure/2` directly instead — for example,
  switching to `:star` with a pinned `host_id` when your game starts, or
  enabling `:mesh` with `late_join: false` for tournament rooms.

  ## Star host and `webrtc_host_id`

  With `:star` topology, one peer relays traffic for everyone. By default the
  star host is `lobby.host_id`. If you want a dedicated server, bot, or other
  user to be the star host instead, pin it with the `host_id` option:

      Gamend.Signaling.configure(lobby,
        enabled: true,
        topology: :star,
        host_id: dedicated_server_user_id
      )

  The `webrtc_host_id` column stores the pinned host. When `nil`,
  `Gamend.Signaling.config/1` falls back to `lobby.host_id`.

  ## Realtime events

  When using `:star`, the star host is notified on its user channel with
  `webrtc:room_ready`, carrying the topic to join, so a headless server-as-host
  can connect on its own.
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
      @room_ready_event =>
        "A signaling room is ready. The star host should connect to the " <>
        "channel topic provided in the payload. Payload fields: " <>
        "`lobby_id`, `topology`, `host_user_id`, `signaling_topic`."
    }
  end

  # Star for every lobby. Written here rather than injected into the create
  # attrs, because the `webrtc_*` columns are deliberately not castable.
  @impl true
  def after_lobby_create(lobby) do
    with {:ok, configured} <- Signaling.configure(lobby, enabled: true, topology: :mesh) do
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
    # Nothing to mirror: `Signaling.config/1` reads the host off the lobby, so
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
