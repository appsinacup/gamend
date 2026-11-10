defmodule GamendWeb.ProtobufFormatTest do
  use ExUnit.Case, async: false

  import Phoenix.ChannelTest

  alias Gamend.AccountsFixtures
  alias Gamend.KV
  alias Gamend.Realtime.V1, as: PB
  alias GamendWeb.Auth.Guardian
  alias GamendWeb.EventCodec

  @endpoint GamendWeb.Endpoint

  setup tags do
    Gamend.DataCase.setup_sandbox(tags)
    :ok
  end

  # ── Socket format negotiation ────────────────────────────────────────────

  test "socket connected with format=protobuf receives binary updated push" do
    user = user_fixture()
    socket = join_user_channel(user, "protobuf")

    assert_push "updated", {:binary, bin}
    decoded = PB.User.decode(bin)

    assert decoded.id == user.id
    assert decoded.email == user.email
    assert decoded.is_online == true
    assert is_integer(decoded.last_seen_at_ms) and decoded.last_seen_at_ms > 0
    assert %PB.LinkedProviders{} = decoded.linked_providers
    assert Jason.decode!(decoded.metadata_json) == (user.metadata || %{})

    _ = socket
  end

  test "socket without format still receives JSON payloads" do
    user = user_fixture()
    _socket = join_user_channel(user, nil)

    assert_push "updated", %{id: _}
  end

  test "kv_updated arrives as decodable KvEntry on protobuf sockets" do
    user = user_fixture()
    socket = join_user_channel(user, "protobuf")
    assert_push "updated", {:binary, _}

    key = "pbtest_#{System.unique_integer([:positive])}"
    ref = push(socket, "kv:subscribe", %{"key" => key, "user_id" => user.id})
    assert_reply ref, :ok, _

    {:ok, _entry} = KV.put(key, %{"score" => 42}, %{}, user_id: user.id)

    assert_push "kv_updated", {:binary, bin}
    decoded = PB.KvEntry.decode(bin)
    assert decoded.key == key
    assert decoded.user_id == user.id
    assert Jason.decode!(decoded.data_json) == %{"score" => 42}
  end

  # ── EventCodec contract ──────────────────────────────────────────────────

  test "notification payload round-trips with declared transforms" do
    {:ok, ts, _} = DateTime.from_iso8601("2026-07-16T09:12:33Z")

    payload = %{
      id: "9f1c2d3e-4b5a-6c7d-8e9f-0a1b2c3d4e5f",
      sender_id: "7a8b9c0d-1e2f-3a4b-5c6d-7e8f9a0b1c2d",
      sender_name: "Alice",
      recipient_id: "3c4d5e6f-7a8b-9c0d-1e2f-3a4b5c6d7e8f",
      title: "Friend request",
      content: "Alice sent you a friend request",
      group: "social",
      metadata: %{"kind" => "friend_request"},
      inserted_at: ts
    }

    {:ok, bin} = EventCodec.encode("user:x", "notification_created", payload)
    decoded = PB.Notification.decode(IO.iodata_to_binary(bin))

    assert decoded.id == payload.id
    assert decoded.group == "social"
    assert decoded.title == payload.title
    assert decoded.inserted_at_ms == DateTime.to_unix(ts, :millisecond)
    assert Jason.decode!(decoded.metadata_json) == %{"kind" => "friend_request"}
  end

  test "absent payload keys stay unset, not zero-valued" do
    {:ok, bin} = EventCodec.encode("lobby:x", "updated", %{is_locked: true, max_users: 8})
    decoded = PB.Lobby.decode(IO.iodata_to_binary(bin))

    assert decoded.is_locked == true
    assert decoded.max_users == 8
    assert decoded.id == nil
    assert decoded.title == nil
    assert decoded.metadata_json == nil
    assert decoded.has_members == nil
    assert decoded.members == []
  end

  test "lobby updated carries the lifecycle state like the JSON payload does" do
    # Without it, protobuf clients only ever learned state from a separate
    # state_changed event — one a rejoined long-playing lobby never sends —
    # and every consumer gating on lobby.state read "" and dropped the payload.
    {:ok, bin} = EventCodec.encode("lobby:x", "updated", %{id: "l1", state: :playing})
    decoded = PB.Lobby.decode(IO.iodata_to_binary(bin))

    assert decoded.state == "playing"

    {:ok, no_state} = EventCodec.encode("lobby:x", "updated", %{id: "l1"})
    assert PB.Lobby.decode(IO.iodata_to_binary(no_state)).state == nil
  end

  test "friend_updated maps friend ids to user payloads" do
    payload = %{friends: %{"abc" => %{display_name: "Bob", is_online: false}}}
    {:ok, bin} = EventCodec.encode("user:x", "friend_updated", payload)
    decoded = PB.FriendUpdate.decode(IO.iodata_to_binary(bin))

    assert %PB.User{display_name: "Bob", is_online: false, id: nil} = decoded.friends["abc"]
  end

  test "string-keyed payloads (post-PubSub) encode identically" do
    atom_keyed = %{key: "k", user_id: "u", data: [1, 2]}
    string_keyed = %{"key" => "k", "user_id" => "u", "data" => [1, 2]}

    {:ok, a} = EventCodec.encode("user:x", "kv_updated", atom_keyed)
    {:ok, b} = EventCodec.encode("user:x", "kv_updated", string_keyed)
    assert IO.iodata_to_binary(a) == IO.iodata_to_binary(b)
  end

  test "list-feed events encode on lobbies/groups topics" do
    {:ok, bin} =
      EventCodec.encode("lobbies", "lobby_created", %{id: "l1", title: "Room", max_users: 4})

    assert %PB.Lobby{id: "l1", title: "Room", max_users: 4} =
             PB.Lobby.decode(IO.iodata_to_binary(bin))

    {:ok, bin} = EventCodec.encode("lobbies", "lobby_deleted", %{id: "l1"})
    assert %PB.EntityId{id: "l1"} = PB.EntityId.decode(IO.iodata_to_binary(bin))

    {:ok, bin} = EventCodec.encode("groups", "group_updated", %{id: "g1", member_count: 3})
    assert %PB.Group{id: "g1", member_count: 3} = PB.Group.decode(IO.iodata_to_binary(bin))

    {:ok, bin} = EventCodec.encode("groups", "group_deleted", %{id: "g1"})
    assert %PB.EntityId{id: "g1"} = PB.EntityId.decode(IO.iodata_to_binary(bin))
  end

  test "member events encode across lobby/group/party channels" do
    # Group member events carry group_id.
    payload = %{group_id: "g1", user_id: "u1", display_name: "Alice"}

    for event <- ~w(member_joined member_left member_kicked member_promoted member_demoted
                    join_request_approved join_request_rejected) do
      {:ok, bin} = EventCodec.encode("group:x", event, payload)
      decoded = PB.MemberEvent.decode(IO.iodata_to_binary(bin))
      assert %PB.MemberEvent{group_id: "g1", user_id: "u1", display_name: "Alice"} = decoded
    end

    # Group presence events are user_id + is_online only.
    {:ok, bin} = EventCodec.encode("group:x", "member_online", %{user_id: "u1", is_online: true})

    assert %PB.MemberEvent{user_id: "u1", is_online: true, group_id: nil, id: nil} =
             PB.MemberEvent.decode(IO.iodata_to_binary(bin))

    # Lobby presence events carry the user brief plus user_id.
    {:ok, bin} =
      EventCodec.encode("lobby:x", "user_online", %{
        user_id: "u1",
        id: "u1",
        display_name: "Alice",
        is_online: true
      })

    assert %PB.MemberEvent{user_id: "u1", id: "u1", is_online: true} =
             PB.MemberEvent.decode(IO.iodata_to_binary(bin))

    # Party lifecycle.
    {:ok, bin} =
      EventCodec.encode("party:x", "member_left", %{user_id: "u1", display_name: "Alice"})

    assert %PB.MemberEvent{user_id: "u1"} = PB.MemberEvent.decode(IO.iodata_to_binary(bin))

    {:ok, bin} = EventCodec.encode("party:x", "disbanded", %{party_id: "p1"})
    assert %PB.PartyRef{party_id: "p1"} = PB.PartyRef.decode(IO.iodata_to_binary(bin))
  end

  test "username travels on user and brief payloads" do
    {:ok, bin} = EventCodec.encode("user:x", "updated", %{id: "u1", username: "ada"})
    assert %PB.User{username: "ada"} = PB.User.decode(IO.iodata_to_binary(bin))

    {:ok, bin} =
      EventCodec.encode("lobby:x", "user_updated", %{id: "u1", username: "ada"})

    assert %PB.UserBrief{username: "ada"} = PB.UserBrief.decode(IO.iodata_to_binary(bin))
  end

  test "tournament events encode on user channels" do
    payload = %{tournament_id: "t1", slug: "weekly-cup", state: "running"}

    for event <- ~w(tournament_updated tournament_finished) do
      {:ok, bin} = EventCodec.encode("user:x", event, payload)

      assert %PB.TournamentEvent{tournament_id: "t1", slug: "weekly-cup", state: "running"} =
               PB.TournamentEvent.decode(IO.iodata_to_binary(bin))
    end
  end

  test "unmapped events fall back to JSON" do
    assert EventCodec.encode("user:x", "webrtc:answer", %{sdp: "..."}) == :json
    assert EventCodec.encode("user:x", "some_future_event", %{}) == :json
  end

  test "malformed payload falls back to JSON instead of raising" do
    ExUnit.CaptureLog.capture_log(fn ->
      assert EventCodec.encode("user:x", "notification_created", %{inserted_at: :not_a_time}) ==
               :json
    end)
  end

  # ── WebRTC RPC envelope ──────────────────────────────────────────────────

  test "RtcEnvelope call/reply round-trip preserves request id" do
    call = %PB.RtcEnvelope{
      msg:
        {:call_hook,
         %PB.RpcCall{id: 7, plugin: "p", fn: "f", args: {:args_json, Jason.encode!([1, "two"])}}}
    }

    assert %PB.RtcEnvelope{msg: {:call_hook, decoded}} =
             PB.RtcEnvelope.decode(PB.RtcEnvelope.encode(call))

    assert decoded.id == 7
    assert {:args_json, json} = decoded.args
    assert Jason.decode!(json) == [1, "two"]

    reply = %PB.RtcEnvelope{
      msg: {:hook_reply, %PB.RpcReply{id: 7, data: {:data_json, Jason.encode!(%{"ok" => true})}}}
    }

    assert %PB.RtcEnvelope{msg: {:hook_reply, %PB.RpcReply{id: 7}}} =
             PB.RtcEnvelope.decode(PB.RtcEnvelope.encode(reply))
  end

  test "RtcEnvelope raw args/data round-trip (typed hooks)" do
    call = %PB.RtcEnvelope{
      msg:
        {:call_hook,
         %PB.RpcCall{
           id: 9,
           plugin: "example_hook",
           fn: "hello_proto",
           args: {:args_raw, <<1, 2, 3>>}
         }}
    }

    assert %PB.RtcEnvelope{msg: {:call_hook, decoded}} =
             PB.RtcEnvelope.decode(PB.RtcEnvelope.encode(call))

    assert decoded.args == {:args_raw, <<1, 2, 3>>}

    reply = %PB.RtcEnvelope{
      msg: {:hook_reply, %PB.RpcReply{id: 9, data: {:data_raw, <<9, 9>>}}}
    }

    assert %PB.RtcEnvelope{msg: {:hook_reply, %PB.RpcReply{id: 9, data: {:data_raw, <<9, 9>>}}}} =
             PB.RtcEnvelope.decode(PB.RtcEnvelope.encode(reply))
  end

  # ── Helpers ──────────────────────────────────────────────────────────────

  defp join_user_channel(user, format) do
    {:ok, token, _claims} = Guardian.encode_and_sign(user)

    params =
      case format do
        nil -> %{"token" => token}
        f -> %{"token" => token, "format" => f}
      end

    {:ok, socket} = connect(GamendWeb.UserSocket, params)
    {:ok, _, socket} = subscribe_and_join(socket, "user:#{user.id}", %{})
    socket
  end

  defp user_fixture, do: AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
end
