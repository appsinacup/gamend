defmodule GamendWeb.RealtimeCommands do
  @moduledoc """
  Registry of every client→server channel event: what a channel's `handle_in`
  answers. `GamendWeb.RealtimeEvents` is the other direction.

  `clients/commands.json` (`mix gamend.gen.events`) is this list, and every SDK
  has a function for each row: generated in the C++ and Balaur SDKs, by hand in
  the Godot and JavaScript clients. `realtime_events_drift_test.exs` holds the
  list to the channels and `python3 clients/sdkgen lint` holds each SDK to it.

  A command on `user:*` goes to the caller's own channel. On any other topic
  the SDK function takes the id the topic is named for.
  """

  @type entry :: %{
          topic: String.t(),
          event: String.t(),
          name: String.t(),
          required: [String.t()],
          optional: [String.t()],
          description: String.t()
        }

  @user "user:*"
  @lobby "lobby:*"
  @signaling "signaling:*"

  # {topic, event, required payload keys, optional payload keys, description}
  @commands [
    {@user, "call_hook", ~w(plugin fn), ~w(args), "Call a function of a server plugin"},
    {@user, "kv:subscribe", ~w(key), ~w(user_id lobby_id),
     "Hear `kv_updated` and `kv_deleted` for a row"},
    {@user, "kv:unsubscribe", ~w(key), ~w(user_id lobby_id), "Stop hearing a row"},
    {@user, "results:list", [], ~w(kind status page page_size), "A page of the caller's results"},
    {@user, "results:get", ~w(id), [], "One result and its stats"},
    {@user, "results:events", ~w(id), ~w(after limit), "A result's events, oldest first"},
    {@user, "webrtc:offer", ~w(sdp), ~w(type), "Open a WebRTC session with the server"},
    {@user, "webrtc:ice", ~w(candidate), ~w(sdpMid sdpMLineIndex),
     "An ICE candidate for that session"},
    {@user, "webrtc:close", [], [], "Close that session"},
    {@lobby, "get_server_time", [], [], "The server's clock, in unix milliseconds"},
    {@signaling, "offer", ~w(target sdp), [], "Send one peer an SDP offer"},
    {@signaling, "answer", ~w(target sdp), [], "Send one peer an SDP answer"},
    {@signaling, "ice", ~w(target candidate), [], "Send one peer an ICE candidate"},
    {@signaling, "broadcast_offer", ~w(sdp), [], "Send every peer in the room an SDP offer"},
    {@signaling, "list_users", [], [], "Who is in the room"}
  ]

  @doc "Every command, in registry order."
  @spec all() :: [entry()]
  def all do
    Enum.map(@commands, fn {topic, event, required, optional, description} ->
      %{
        topic: topic,
        event: event,
        name: name(topic, event),
        required: required,
        optional: optional,
        description: description
      }
    end)
  end

  # What the SDK calls it: `kv:subscribe` is `kv_subscribe`, and off the user
  # channel the channel leads, as `lobby_get_server_time`.
  defp name(@user, event), do: String.replace(event, ":", "_")

  defp name(topic, event) do
    channel = topic |> String.split(":") |> hd()
    "#{channel}_#{String.replace(event, ":", "_")}"
  end
end
