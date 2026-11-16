defmodule GamendWeb.ProtobufBenchTest do
  @moduledoc """
  The protobuf encoding of a realtime event is smaller than its JSON, event by
  event: the reason a client opts into `?format=protobuf` at all.

  For every representative event fixture this encodes the same payload map
  through both production paths:

    * JSON — `Jason.encode_to_iodata!/1`, what the Phoenix V2 serializer
      runs for each `push/3`
    * protobuf — `GamendWeb.EventCodec.encode/3`, what
      `GamendWeb.ChannelPush.push_event/3` runs on `?format=protobuf`
      sockets

  WebSocket JSON traffic is usually permessage-deflate compressed on the
  wire, so this overstates the real WS difference; it is the honest number
  for WebRTC DataChannels, which have no compression.

  Every fixture is a *full* payload. Realtime state events stopped sending
  partial maps when JSON delta encoding was removed, so a fixture with a
  handful of fields would measure a payload the server cannot produce.
  """

  use ExUnit.Case, async: true

  alias GamendWeb.EventCodec

  test "protobuf encoding is smaller per event" do
    {:ok, ts, _} = DateTime.from_iso8601("2026-07-16T09:12:33Z")
    uuid = fn i -> "9f1c2d3e-4b5a-6c7d-8e9f-0a1b2c3d4e#{String.pad_leading("#{i}", 2, "0")}" end

    fixtures = [
      {"user:x", "updated",
       %{
         id: uuid.(1),
         email: "alice@example.com",
         profile_url: "",
         metadata: %{"rank" => 12},
         username: "alice",
         display_name: "Alice",
         lobby_id: "",
         party_id: "",
         is_online: true,
         last_seen_at: ts,
         linked_providers: %{
           google: false,
           facebook: false,
           discord: true,
           apple: false,
           steam: false,
           device: true,
           github: false
         },
         has_password: true
       }},
      {"user:x", "notification_created",
       %{
         id: uuid.(2),
         sender_id: uuid.(3),
         sender_name: "Alice",
         recipient_id: uuid.(4),
         title: "Friend request",
         content: "Alice sent you a friend request",
         metadata: %{"kind" => "friend_request"},
         inserted_at: ts
       }},
      {"user:x", "chat_message_created",
       %{
         id: uuid.(5),
         content: "gg wp everyone, rematch in 5?",
         metadata: %{},
         sender_id: uuid.(6),
         sender_name: "Alice",
         chat_type: "lobby",
         chat_ref_id: uuid.(7),
         inserted_at: ts
       }},
      {"user:x", "match_found",
       %{lobby_id: uuid.(11), match_params: %{"mode" => "ranked", "band" => "2"}}},
      {"user:x", "kv_updated",
       %{key: "loadout", user_id: uuid.(8), lobby_id: nil, data: %{"weapon" => 12}, metadata: %{}}},
      {"lobby:x", "updated",
       %{
         id: uuid.(9),
         title: "Ranked #4",
         host_id: uuid.(10),
         host_name: "Alice",
         hostless: false,
         max_users: 8,
         is_hidden: false,
         is_locked: true,
         metadata: %{"map" => "dust2"},
         is_passworded: false,
         slowdown: 0,
         spectator_count: 2
       }}
    ]

    for {topic, event, payload} <- fixtures do
      json_bytes = payload |> Jason.encode_to_iodata!() |> IO.iodata_length()
      {:ok, iodata} = EventCodec.encode(topic, event, payload)
      pb_bytes = IO.iodata_length(iodata)

      assert pb_bytes < json_bytes,
             "protobuf (#{pb_bytes}B) not smaller than JSON (#{json_bytes}B) for #{topic} #{event}"
    end
  end
end
