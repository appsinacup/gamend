defmodule GamendWeb.EventCodecCoverageTest do
  @moduledoc """
  Keeps `GamendWeb.RealtimeEvents`' `pb:` flag honest against what
  `GamendWeb.EventCodec` actually encodes.

  The registry is the published contract: it is what the admin Runtime page
  renders as a "pb+json" or "json" badge per event, and what a client author
  reads to decide whether to expect a binary frame. Nothing checked it. The two
  could disagree in either direction, and both directions are silent:

    * `pb: true`, no mapping — the client waits for a binary frame that never
      comes, or worse, was written to decode one and gets JSON instead.
    * `pb: false`, mapping exists — the client treats the event as JSON and
      fails to parse the binary frame the server actually sends.

  The second is not hypothetical: `chat_muted` and `chat_unmuted` were declared
  `pb: false` while `EventCodec` mapped both.

  `realtime_events_drift_test.exs` already keeps the registry's *event list* in
  sync with the source. This covers the column that test does not read.
  """
  use ExUnit.Case, async: true

  alias Gamend.Realtime.V1, as: PB
  alias GamendWeb.EventCodec
  alias GamendWeb.RealtimeEvents

  # Registry topics are patterns ("user:*", "lobby:*") or bare ("lobbies").
  # EventCodec dispatches on the segment before the colon, so any concrete id
  # works — the same event can map on one topic and not another.
  defp concrete_topic(topic), do: String.replace(topic, ":*", ":1")

  # An empty payload is enough to tell mapped from unmapped: `message_for/3`
  # dispatches on topic and event only, and every builder it reaches tolerates
  # missing keys (proto3 fields default). A builder that raised would be
  # rescued into `:json` by `encode/3` — which is itself worth catching, since
  # an event that cannot encode its own empty payload is not really mapped.
  defp mapped?(topic, event) do
    EventCodec.encode(concrete_topic(topic), event, %{}) != :json
  end

  describe "registry pb: flag" do
    test "matches what EventCodec actually encodes" do
      mismatches =
        for row <- RealtimeEvents.all(),
            actual = mapped?(row.topic, row.event),
            actual != row.pb,
            do: {row.topic, row.event, row.pb, actual}

      assert mismatches == [],
             """
             GamendWeb.RealtimeEvents disagrees with GamendWeb.EventCodec.

             #{Enum.map_join(mismatches, "\n", fn {t, e, declared, actual} -> "  #{t} #{e}: registry says pb=#{declared}, codec says #{actual}" end)}

             Either add/remove the `message_for` clause in EventCodec, or
             correct the `pb:` column in RealtimeEvents. The registry is what
             the admin Runtime page and client authors read, so a wrong flag
             ships as wrong documentation.
             """
    end

    test "the registry is actually populated" do
      # Without this, an empty or unloadable registry makes every assertion
      # above pass vacuously.
      rows = RealtimeEvents.all()

      assert length(rows) > 50, "only #{length(rows)} registry entries"
      assert Enum.any?(rows, & &1.pb), "no event is marked pb: true"
      assert Enum.any?(rows, &(not &1.pb)), "no event is marked pb: false"
    end
  end

  describe "protobuf coverage" do
    test "every topic kind in the registry reaches the codec" do
      # A topic EventCodec has no clauses for at all encodes nothing, which
      # would show up as a uniform pb: false across that topic rather than as
      # an obvious hole. Signaling is that case today and is expected.
      by_topic =
        RealtimeEvents.all()
        |> Enum.group_by(& &1.topic)
        |> Enum.reject(fn {_topic, rows} -> Enum.any?(rows, & &1.pb) end)
        |> Enum.map(&elem(&1, 0))
        |> Enum.sort()

      assert by_topic == ["signaling:*"],
             """
             These topics have no protobuf-mapped events at all: #{inspect(by_topic)}

             Signaling is deliberate — its payloads are SDP blobs and ICE
             candidates, opaque strings protobuf would wrap without shrinking,
             and the peer path negotiates its own format in WebRtcPeer. Any
             other topic here is a gap.
             """
    end

    test "state_changed carries the payload, with atoms rendered as strings" do
      # The states are atoms in-process — Gamend.Lobbies builds the payload from
      # the schema field — and must not reach the wire as ":waiting".
      {:ok, iodata} =
        EventCodec.encode("lobby:1", "state_changed", %{
          lobby_id: "lob-1",
          from: :waiting,
          to: :in_progress,
          state_changed_at: ~U[2026-08-09 12:00:00Z]
        })

      decoded = PB.LobbyStateChanged.decode(IO.iodata_to_binary(iodata))

      assert decoded.lobby_id == "lob-1"
      assert decoded.from == "waiting"
      assert decoded.to == "in_progress"

      assert decoded.state_changed_at_ms ==
               DateTime.to_unix(~U[2026-08-09 12:00:00Z], :millisecond)
    end

    test "state_changed matches the bytes the Godot client is tested against" do
      # A Godot client's decoder is hand-written GDScript (the godobuf checkout
      # is a different generator version, so that file cannot be regenerated
      # wholesale), so encoder and decoder can drift apart silently. This vector
      # is the contract: the server pins it here, and the client's own test
      # decodes these exact bytes. Encoding and decoding with one library proves
      # nothing about whether two implementations agree.
      {:ok, iodata} =
        EventCodec.encode("lobby:1", "state_changed", %{
          lobby_id: "lob-1",
          from: :waiting,
          to: :in_progress,
          state_changed_at: ~U[2026-08-09 12:00:00Z]
        })

      assert Base.encode64(IO.iodata_to_binary(iodata)) ==
               "CgVsb2ItMRIHd2FpdGluZxoLaW5fcHJvZ3Jlc3MggMyTs/4z"
    end

    # The client MERGES these three into a long-lived cache (GamendPresence:
    # apply_user_update and cache_user), so for them an absent field means
    # "unchanged", not "empty". proto3 does not write an implicit-presence
    # scalar that holds its zero value — so a field declared without `optional`
    # can never tell that cache a value was CLEARED, and the stale one lives on.
    # That is precisely how a deleted lobby went unnoticed.
    #
    # Every other message in the schema is an event consumed whole, where an
    # omitted empty simply reads as empty; only these three are merged, so only
    # these three need the guarantee.
    test "everything merged into the client cache keeps explicit presence" do
      proto = Path.expand("../../../../../proto/gamend_realtime.proto", __DIR__)
      assert File.exists?(proto), "the schema moved — this test can no longer see it"
      source = File.read!(proto)

      # The message key, never empty, and the one field that may stay implicit.
      allowed_implicit = %{"MemberEvent" => ["user_id"]}

      for message <- ["User", "UserBrief", "MemberEvent"] do
        [_, body] = Regex.run(~r/^message #{message} \{\n(.*?)^\}/ms, source)

        implicit =
          body
          |> String.split("\n")
          |> Enum.map(&String.trim/1)
          # Blank lines, comments and explicitly-optional fields alike: none of
          # them is a field that carries implicit presence.
          |> Enum.reject(&(&1 == "" or String.starts_with?(&1, ["//", "optional "])))
          |> Enum.map(fn line ->
            [_, name] = Regex.run(~r/(\w+)\s*=\s*\d+;/, line)
            name
          end)
          |> Enum.reject(&(&1 in Map.get(allowed_implicit, message, [])))

        assert implicit == [],
               "#{message} has implicit-presence field(s) #{inspect(implicit)} — " <>
                 "clearing one would not reach the client, which merges this message"
      end
    end

    test "a cleared lobby_id is written, not omitted" do
      # How a player learns their lobby was deleted around them: `delete_lobby`
      # broadcasts this with lobby_id emptied. proto3 omits empty scalars unless
      # the field has explicit presence, and an omitted lobby_id decodes as "no
      # value given" — the client would merge nothing and go on believing it
      # holds a seat the server has already taken away. `optional string
      # lobby_id = 6` is what stops that, and this is what proves it.
      {:ok, iodata} =
        EventCodec.encode("user:user-1", "updated", %{
          id: "user-1",
          email: "",
          profile_url: "",
          metadata: %{},
          username: "",
          display_name: "Ana",
          lobby_id: "",
          party_id: "",
          is_online: true,
          last_seen_at: nil,
          linked_providers: %{},
          has_password: false
        })

      bytes = IO.iodata_to_binary(iodata)

      # Field 6, wire type 2, length 0 — the empty string, present on the wire.
      assert <<0x32, 0x00>> = binary_part(bytes, 21, 2)

      # Pinned for the same reason as the vector above: a client test decodes
      # these exact bytes.
      assert Base.encode64(bytes) == "CgZ1c2VyLTESABoAIgJ7fSoDQW5hMgA6AEABUgBYAGoA"
    end
  end
end
