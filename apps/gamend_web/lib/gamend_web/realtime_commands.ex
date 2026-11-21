defmodule GamendWeb.RealtimeCommands do
  @moduledoc """
  Registry of every client→server channel event: what a channel's `handle_in`
  answers. `GamendWeb.RealtimeEvents` is the other direction.

  `clients/commands.json` (`mix gamend.gen.events`) is this list, and every SDK
  has a function for each row: generated in the C++, C#, Rust and Balaur SDKs,
  by hand in the Godot and JavaScript clients. `realtime_events_drift_test.exs` holds the
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
          types: %{String.t() => type()},
          description: String.t()
        }

  @typedoc "What a payload key holds (`GamendWeb.PayloadContract`)."
  @type type :: GamendWeb.PayloadContract.type()

  @user "user:*"
  @lobby "lobby:*"
  @signaling "signaling:*"

  # {topic, event, required payload keys, optional payload keys, description}.
  # A key is `name: type`, the type its value must be (`GamendWeb.ChannelContract`).
  @commands [
    {@user, "call_hook", [plugin: :string, fn: :string],
     [args: {:free, "the plugin function's own arguments"}],
     "Call a function of a server plugin"},
    {@user, "kv:subscribe", [key: :string], [user_id: :string, lobby_id: :string],
     "Hear `kv_updated` and `kv_deleted` for a row"},
    {@user, "kv:unsubscribe", [key: :string], [user_id: :string, lobby_id: :string],
     "Stop hearing a row"},
    {@user, "results:list", [],
     [kind: :string, status: :string, page: :integer, page_size: :integer],
     "A page of the caller's results"},
    {@user, "results:get", [id: :string], [], "One result and its stats"},
    {@user, "results:events", [id: :string], [after: :string, limit: :integer],
     "A result's events, oldest first"},
    {@user, "webrtc:offer", [sdp: :string], [type: :string],
     "Open a WebRTC session with the server"},
    {@user, "webrtc:ice", [candidate: :string], [sdpMid: :string, sdpMLineIndex: :integer],
     "An ICE candidate for that session"},
    {@user, "webrtc:close", [], [], "Close that session"},
    {@lobby, "get_server_time", [], [], "The server's clock, in unix milliseconds"},
    {@signaling, "offer", [target: :string, sdp: :string], [], "Send one peer an SDP offer"},
    {@signaling, "answer", [target: :string, sdp: :string], [], "Send one peer an SDP answer"},
    {@signaling, "ice", [target: :string, candidate: :string], [],
     "Send one peer an ICE candidate"},
    {@signaling, "broadcast_offer", [sdp: :string], [],
     "Send every peer in the room an SDP offer"},
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
        required: names(required),
        optional: names(optional),
        types: Map.new(required ++ optional, fn {key, type} -> {to_string(key), type} end),
        description: description
      }
    end)
  end

  @doc "The command `event` on `topic` (a joined topic, `user:<id>`, or its pattern), or nil."
  @spec find(String.t(), String.t()) :: entry() | nil
  def find(topic, event) when is_binary(topic) and is_binary(event) do
    pattern = (topic |> String.split(":", parts: 2) |> hd()) <> ":*"
    Enum.find(all(), &(&1.topic == pattern and &1.event == event))
  end

  def find(_topic, _event), do: nil

  defp names(keys), do: Enum.map(keys, fn {key, _type} -> to_string(key) end)

  # What the SDK calls it: `kv:subscribe` is `kv_subscribe`, and off the user
  # channel the channel leads, as `lobby_get_server_time`.
  defp name(@user, event), do: String.replace(event, ":", "_")

  defp name(topic, event) do
    channel = topic |> String.split(":") |> hd()
    "#{channel}_#{String.replace(event, ":", "_")}"
  end
end
