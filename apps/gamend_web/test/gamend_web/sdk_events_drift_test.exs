defmodule GamendWeb.SdkEventsDriftTest do
  @moduledoc """
  Holds every client SDK to the one registry of server→client events
  (`GamendWeb.RealtimeEvents`, itself held to the channel code by
  `realtime_events_drift_test.exs` and to the codec by
  `event_codec_coverage_test.exs`):

    * `clients/events.json`, which the Balaur and C++ SDKs are generated
      from, is the registry as `mix gamend.gen.events` writes it;
    * the Godot client routes every event of its channels to a signal
      (`GamendApi.gd`'s `_handle_*_event`, WebRTC's in `GamendWebRTC.gd`,
      signaling's in `GamendSignalingClient.gd`);
    * the Godot and JavaScript clients decode every event sent as protobuf
      (`GamendProto.gd`, `gamend_proto.js`): one they cannot decode reaches
      the game as raw bytes on a `?format=protobuf` socket.

  A new event fails here until each client has it. The hand-written halves
  stay hand-written; only their coverage is checked.
  """
  use ExUnit.Case, async: true

  alias GamendWeb.EventCodec
  alias GamendWeb.RealtimeEvents
  alias Mix.Tasks.Gamend.Gen.Events

  @clients Path.expand("../../../../clients", __DIR__)
  @godot Path.join(@clients, "gamend_template")

  defp rows do
    Enum.map(RealtimeEvents.all(), fn entry ->
      channel = entry.topic |> String.split(":") |> hd()

      Map.merge(entry, %{
        channel: channel,
        message: EventCodec.message_name(entry.topic, entry.event)
      })
    end)
  end

  defp read(path), do: File.read!(path)

  test "clients/events.json and commands.json are the registries as generated" do
    assert read(Path.join(@clients, "events.json")) == Events.render(),
           "clients/events.json is stale: run `mix gamend.gen.events`"

    assert read(Path.join(@clients, "commands.json")) == Events.render_commands(),
           "clients/commands.json is stale: run `mix gamend.gen.events`"
  end

  @handlers %{
    "user" => "_handle_user_event",
    "lobby" => "_handle_lobby_event",
    "lobbies" => "_handle_lobbies_event",
    "party" => "_handle_party_event",
    "group" => "_handle_group_event",
    "groups" => "_handle_groups_event"
  }

  # A GDScript function's body: from its `func` line to the next one.
  defp body(source, name) do
    case Regex.run(~r/^func #{name}\(.*?\n(.*?)(?=^func |\z)/ms, source) do
      [_, body] -> body
      nil -> flunk("GamendApi.gd has no func #{name}")
    end
  end

  # Where the Godot client routes `row`'s event.
  defp routing(row, api, webrtc, signaling) do
    cond do
      String.starts_with?(row.event, "webrtc:") -> webrtc
      row.channel == "signaling" -> signaling
      handler = @handlers[row.channel] -> body(api, handler)
    end
  end

  test "the Godot client routes every event of its channels" do
    api = read(Path.join(@godot, "GamendApi.gd"))
    webrtc = read(Path.join(@godot, "GamendWebRTC.gd"))
    signaling = read(Path.join(@godot, "GamendSignalingClient.gd"))

    missing =
      for row <- rows(),
          not String.contains?(routing(row, api, webrtc, signaling), ~s("#{row.event}")),
          do: "#{row.channel}/#{row.event}"

    assert missing == [], "Godot does not route: #{Enum.join(missing, ", ")}"
  end

  test "the Godot client decodes every event sent as protobuf" do
    proto = read(Path.join(@godot, "GamendProto.gd"))

    missing =
      for row <- rows(),
          row.message,
          not String.contains?(proto, ~s("#{row.event}")),
          do: "#{row.channel}/#{row.event} (#{row.message})"

    assert missing == [], "GamendProto.gd cannot decode: #{Enum.join(missing, ", ")}"
  end

  test "the JavaScript client decodes every event sent as protobuf" do
    js = read(Path.join(@clients, "gamend_proto.js"))

    missing =
      for row <- rows(),
          row.message,
          not Regex.match?(~r/^\s*['"]?#{Regex.escape(row.event)}['"]?\s*:/m, js),
          do: "#{row.channel}/#{row.event} (#{row.message})"

    assert missing == [], "gamend_proto.js cannot decode: #{Enum.join(missing, ", ")}"
  end
end
