defmodule GameServerWeb.WebRTCPeer do
  @moduledoc """
  Manages a server-side WebRTC PeerConnection for a single user.

  This GenServer owns an `ExWebRTC.PeerConnection` process and acts as the
  bridge between the Phoenix Channel (signaling) and the WebRTC DataChannels
  for low-latency hook RPC calls.

  ## Lifecycle

  1. Started by `UserChannel` when the client sends a `"webrtc:offer"` event.
  2. Linked to the channel process — auto-terminates when WebSocket disconnects.
  3. Handles SDP offer/answer exchange and ICE candidate relay.
  4. Processes hook RPC calls received on the "events" DataChannel.
  5. Provides `send_data/3` to push hook responses back to the client.

  ## Hook RPC

  Clients send JSON messages on the "events" DataChannel:

      {"type": "call_hook", "plugin": "my_plugin", "fn": "my_func", "args": [1, 2]}

  The server replies on the same channel with:

      {"type": "hook_reply", "plugin": "my_plugin", "fn": "my_func", "data": result}

  Or on error:

      {"type": "hook_error", "plugin": "my_plugin", "fn": "my_func", "error": "reason"}

  ## Messages sent to the controlling channel process

  - `{:webrtc_answer, answer_json}` — SDP answer to send to client
  - `{:webrtc_ice, candidate_json}` — ICE candidate to send to client
  - `{:webrtc_channel_open, ref, label}` — DataChannel opened
  - `{:webrtc_channel_closed, ref}` — DataChannel closed
  - `{:webrtc_connection_state, state}` — connection state change
  """

  use GenServer
  require Logger

  alias ExWebRTC.{
    ICECandidate,
    PeerConnection,
    SessionDescription
  }

  alias GameServer.Accounts
  alias GameServer.Hooks.HookSchemas

  # DataChannel message rate limits (per user) — defaults, overridden by config

  # Max open DataChannels per peer (clients create named channels)
  @max_data_channels 1

  # Max inbound DataChannel message size (bytes) — prevents memory spikes
  @max_dc_message_size 65_536

  # ── Public API ────────────────────────────────────────────────────────────

  @doc """
  Starts a WebRTCPeer linked to the calling process (typically a channel).

  ## Options

  - `:user_id` — the authenticated user's ID (required)
  - `:ice_servers` — list of ICE server configs (optional, defaults to config)
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc """
  Handles an incoming SDP offer from the client.
  Sends `{:webrtc_answer, answer_json}` back to the controlling process.
  """
  def handle_offer(pid, offer_json) do
    GenServer.cast(pid, {:offer, offer_json})
  end

  @doc """
  Adds a remote ICE candidate received from the client.
  """
  def add_ice_candidate(pid, candidate_json) do
    GenServer.cast(pid, {:ice_candidate, candidate_json})
  end

  @doc """
  Sends data to the client over a named DataChannel.
  Returns `:ok` or `{:error, reason}`.
  """
  def send_data(pid, channel_label, data) do
    GenServer.call(pid, {:send_data, channel_label, data})
  end

  @doc """
  Returns the current connection state.
  """
  def connection_state(pid) do
    GenServer.call(pid, :connection_state)
  end

  @doc """
  Closes the WebRTC peer connection and stops this process.
  """
  def close(pid) do
    GenServer.stop(pid, :normal)
  end

  # ── GenServer callbacks ───────────────────────────────────────────────────

  @impl true
  def init(opts) do
    user_id = Keyword.fetch!(opts, :user_id)
    channel_pid = Keyword.get(opts, :channel_pid, self())

    user = Accounts.get_user(user_id)

    ice_servers =
      Keyword.get_lazy(opts, :ice_servers, fn ->
        webrtc_config = Application.get_env(:game_server_web, :webrtc, [])
        Keyword.get(webrtc_config, :ice_servers, [%{urls: "stun:stun.l.google.com:19302"}])
      end)

    {:ok, pc} = PeerConnection.start_link(ice_servers: ice_servers)

    state = %{
      peer_connection: pc,
      channel_pid: channel_pid,
      user: user,
      user_id: user_id,
      # %{ref => label} for open DataChannels
      channels: %{},
      # %{label => ref} reverse lookup for sending by label
      channels_by_label: %{},
      # %{ref => "json" | "protobuf"} negotiated via the DataChannel
      # protocol field (DCEP); empty/unknown protocol means JSON.
      formats: %{}
    }

    GameServerWeb.ConnectionTracker.register(:webrtc_peer, %{user_id: user_id})
    Logger.info("WebRTCPeer started for user=#{user_id}")
    {:ok, state}
  end

  @impl true
  def handle_cast({:offer, offer_json}, state) do
    offer = SessionDescription.from_json(offer_json)
    :ok = PeerConnection.set_remote_description(state.peer_connection, offer)

    {:ok, answer} = PeerConnection.create_answer(state.peer_connection)
    :ok = PeerConnection.set_local_description(state.peer_connection, answer)

    answer_json = SessionDescription.to_json(answer)
    send(state.channel_pid, {:webrtc_answer, answer_json})

    {:noreply, state}
  end

  @impl true
  def handle_cast({:ice_candidate, candidate_json}, state) do
    candidate = ICECandidate.from_json(candidate_json)
    :ok = PeerConnection.add_ice_candidate(state.peer_connection, candidate)
    {:noreply, state}
  end

  @impl true
  def handle_call({:send_data, channel_label, data}, _from, state) do
    case Map.get(state.channels_by_label, channel_label) do
      nil ->
        {:reply, {:error, :channel_not_found}, state}

      ref ->
        :ok = PeerConnection.send_data(state.peer_connection, ref, data)
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call(:connection_state, _from, state) do
    conn_state = PeerConnection.get_connection_state(state.peer_connection)
    {:reply, conn_state, state}
  end

  # ── ExWebRTC messages ─────────────────────────────────────────────────────

  @impl true
  def handle_info({:ex_webrtc, _pc, {:ice_candidate, candidate}}, state) do
    candidate_json = ICECandidate.to_json(candidate)
    send(state.channel_pid, {:webrtc_ice, candidate_json})
    {:noreply, state}
  end

  @impl true
  def handle_info({:ex_webrtc, _pc, {:connection_state_change, conn_state}}, state) do
    Logger.info("WebRTCPeer user=#{state.user_id} connection_state=#{conn_state}")
    send(state.channel_pid, {:webrtc_connection_state, conn_state})

    if conn_state == :failed do
      {:stop, {:shutdown, :connection_failed}, state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(
        {:ex_webrtc, _pc,
         {:data_channel, %ExWebRTC.DataChannel{ref: ref, label: label, protocol: protocol}}},
        state
      ) do
    # Enforce max open DataChannels to prevent resource exhaustion
    if map_size(state.channels) >= @max_data_channels do
      Logger.warning(
        "WebRTCPeer user=#{state.user_id} max DataChannels (#{@max_data_channels}) reached, rejecting: #{label}"
      )

      {:noreply, state}
    else
      format = if protocol == "protobuf", do: "protobuf", else: "json"
      Logger.info("WebRTCPeer user=#{state.user_id} DataChannel opened: #{label} (#{format})")
      send(state.channel_pid, {:webrtc_channel_open, ref, label})

      state = %{
        state
        | channels: Map.put(state.channels, ref, label),
          channels_by_label: Map.put(state.channels_by_label, label, ref),
          formats: Map.put(state.formats, ref, format)
      }

      {:noreply, state}
    end
  end

  @impl true
  def handle_info(
        {:ex_webrtc, _pc, {:data_channel_state_change, _ref, :open}},
        state
      ) do
    # Channel is now fully open — already tracked from :data_channel message
    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:ex_webrtc, _pc, {:data_channel_state_change, ref, :closed}},
        state
      ) do
    label = Map.get(state.channels, ref)
    Logger.info("WebRTCPeer user=#{state.user_id} DataChannel closed: #{inspect(label)}")
    send(state.channel_pid, {:webrtc_channel_closed, ref})

    state = %{
      state
      | channels: Map.delete(state.channels, ref),
        channels_by_label:
          if(label, do: Map.delete(state.channels_by_label, label), else: state.channels_by_label),
        formats: Map.delete(state.formats, ref)
    }

    {:noreply, state}
  end

  @impl true
  def handle_info({:ex_webrtc, _pc, {:data, ref, data}}, state) do
    cond do
      byte_size(data) > @max_dc_message_size ->
        Logger.warning(
          "WebRTCPeer user=#{state.user_id} oversized DC message (#{byte_size(data)} bytes), dropping"
        )

        {:noreply, state}

      not dc_rate_limit_allowed?(state.user_id) ->
        Logger.warning("WebRTCPeer user=#{state.user_id} DataChannel rate limit exceeded")
        send(state.channel_pid, {:webrtc_connection_state, :rate_limited})
        {:stop, {:shutdown, :rate_limited}, state}

      true ->
        label = Map.get(state.channels, ref, "unknown")
        format = Map.get(state.formats, ref, "json")
        maybe_handle_rpc(label, format, data, state)
        {:noreply, state}
    end
  end

  # Ignore other ExWebRTC messages (ICE gathering state, signaling state, etc.)
  @impl true
  def handle_info({:ex_webrtc, _pc, _msg}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({:EXIT, pc, reason}, %{peer_connection: pc} = state) do
    Logger.info("WebRTCPeer user=#{state.user_id} PeerConnection exited: #{inspect(reason)}")

    {:stop, {:shutdown, :pc_exited}, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("WebRTCPeer user=#{state.user_id} terminating: #{inspect(reason)}")

    try do
      if Process.alive?(state.peer_connection) do
        PeerConnection.close(state.peer_connection)
        PeerConnection.stop(state.peer_connection)
      end
    catch
      kind, error ->
        Logger.warning(
          "WebRTCPeer user=#{state.user_id} cleanup error: #{inspect(kind)} #{inspect(error)}"
        )
    end

    :ok
  end

  # ── RPC handling over DataChannels ──────────────────────────────────────────

  defp maybe_handle_rpc("events", "json", data, state) do
    case Jason.decode(data) do
      {:ok, %{"type" => "call_hook", "plugin" => plugin, "fn" => func} = payload} ->
        args = Map.get(payload, "args", [])
        args = if is_list(args), do: args, else: [args]

        resp =
          case call_hook(plugin, func, {:list, args}, :map, state) do
            {:ok, res} ->
              case Jason.encode(%{type: "hook_reply", plugin: plugin, fn: func, data: res}) do
                {:ok, json} ->
                  json

                {:error, _} ->
                  Jason.encode!(%{
                    type: "hook_error",
                    plugin: plugin,
                    fn: func,
                    error: "result_not_json_encodable"
                  })
              end

            {:error, reason} ->
              Jason.encode!(%{
                type: "hook_error",
                plugin: plugin,
                fn: func,
                error: format_error(reason)
              })
          end

        _ = send_on_channel(state, "events", resp)

      _ ->
        :ok
    end
  end

  # Protobuf RPC envelope (proto/gamend_realtime.proto). Unlike the JSON
  # protocol, requests carry an id echoed in the reply so concurrent calls
  # can be correlated.
  defp maybe_handle_rpc("events", "protobuf", data, state) do
    alias Gamend.Realtime.V1, as: PB

    case PB.RtcEnvelope.decode(data) do
      %PB.RtcEnvelope{msg: {:call_hook, %PB.RpcCall{id: id, plugin: plugin, fn: func} = call}} ->
        # HookSchemas converts through the hook's registered schema when one
        # exists: args_raw decodes into the request struct, args_json objects
        # do too, and the reply is encoded back to the caller's wire form.
        {args_input, wire} =
          case call.args do
            {:args_raw, raw} -> {{:raw, raw}, :binary}
            {:args_json, ""} -> {{:list, []}, :map}
            {:args_json, json} -> {{:list, decode_json_args(json)}, :map}
            nil -> {{:list, []}, :map}
          end

        reply =
          case call_hook(plugin, func, args_input, wire, state) do
            {:ok, {:raw, raw}} when is_binary(raw) ->
              %PB.RtcEnvelope{msg: {:hook_reply, %PB.RpcReply{id: id, data: {:data_raw, raw}}}}

            {:ok, res} ->
              %PB.RtcEnvelope{
                msg: {:hook_reply, %PB.RpcReply{id: id, data: {:data_json, Jason.encode!(res)}}}
              }

            {:error, reason} ->
              %PB.RtcEnvelope{
                msg: {:hook_error, %PB.RpcError{id: id, error: format_error(reason)}}
              }
          end

        _ = send_on_channel(state, "events", PB.RtcEnvelope.encode(reply), :binary)

      _ ->
        :ok
    end
  rescue
    # Malformed protobuf frame; drop it.
    _ -> :ok
  end

  defp maybe_handle_rpc(_label, _format, _data, _state), do: :ok

  defp call_hook(plugin, func, args_input, wire, state) do
    # Use the stored full user or refetch if missing
    user = state.user || Accounts.get_user(state.user_id)
    HookSchemas.call(plugin, func, args_input, wire, caller: user)
  end

  defp decode_json_args(json) do
    case Jason.decode(json) do
      {:ok, list} when is_list(list) -> list
      _ -> []
    end
  end

  # Direct send for use from within this GenServer (send_data/3 is a
  # GenServer.call and would deadlock when invoked on self()).
  defp send_on_channel(state, label, data, data_type \\ :string) do
    case Map.get(state.channels_by_label, label) do
      nil -> {:error, :channel_not_found}
      ref -> PeerConnection.send_data(state.peer_connection, ref, data, data_type)
    end
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason) when is_atom(reason), do: to_string(reason)
  defp format_error(reason), do: inspect(reason)

  # ── DataChannel rate limiting ──────────────────────────────────────────────

  defp dc_rate_limit_allowed?(user_id) do
    enabled? = GameServer.Settings.get(GameServerWeb.Plugs.RateLimiter, :enabled)

    if enabled? do
      limit = GameServer.Settings.get(GameServerWeb.Plugs.RateLimiter, :dc_limit)
      window = GameServer.Settings.get(GameServerWeb.Plugs.RateLimiter, :dc_window_ms)

      case GameServerWeb.RateLimit.hit("dc:#{user_id}", window, limit) do
        {:allow, _count} -> true
        {:deny, _retry_after} -> false
      end
    else
      true
    end
  end
end
