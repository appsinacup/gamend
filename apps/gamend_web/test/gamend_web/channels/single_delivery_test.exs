defmodule GamendWeb.SingleDeliveryTest do
  @moduledoc """
  One PubSub broadcast, one push.

  `Phoenix.Channel.Server` subscribes a channel process to its own topic on
  the endpoint's PubSub (`Gamend.PubSub`) right after `join/3` returns, so a
  channel that also subscribed to that same topic inside `join/3` would be
  registered twice (`Phoenix.PubSub` is a duplicate registry) and run every
  `handle_info` twice: a client would see `state_changed` (and `updated`,
  `user_joined`, …) arrive twice per event.

  Each test broadcasts once on the channel's own topic — the same
  `Phoenix.PubSub.broadcast/3` the core `broadcast_*` helpers use — and
  refutes a second push.
  """
  use ExUnit.Case
  import Phoenix.ChannelTest

  alias Gamend.AccountsFixtures
  alias Gamend.Chat
  alias Gamend.Groups
  alias Gamend.KV
  alias Gamend.Lobbies
  alias Gamend.Parties
  alias GamendWeb.Auth.Guardian

  setup tags do
    Gamend.DataCase.setup_sandbox(tags)
    :ok
  end

  @endpoint GamendWeb.Endpoint

  # A second delivery would reach the channel's mailbox in the same broadcast
  # as the first, before the call that made it returns: once the channel has
  # answered a call, every push it owes has been sent. One that stopped after
  # its push (a group channel hearing its own member leave) sends no more.
  defp refute_second(socket, event) do
    settle(socket.channel_pid)
    refute_push ^event, _, 0
  end

  defp settle(pid) do
    _ = :sys.get_state(pid)
  catch
    :exit, _ -> :ok
  end

  defp user, do: AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()

  defp join_as(user, topic) do
    {:ok, token, _} = Guardian.encode_and_sign(user)
    {:ok, socket} = connect(GamendWeb.UserSocket, %{"token" => token})
    {:ok, _, socket} = subscribe_and_join(socket, topic, %{})
    socket
  end

  test "lobby: a state transition is pushed once" do
    host = user()
    {:ok, lobby} = Lobbies.create_lobby(%{title: "once", host_id: host.id})
    socket = join_as(host, "lobby:#{lobby.id}")
    assert_push "updated", _

    {:ok, _} = Lobbies.transition_state(lobby, "starting")

    assert_push "state_changed", %{to: "starting"}
    refute_second(socket, "state_changed")
  end

  test "lobby: a spectator gets each event once too" do
    host = user()
    spectator = user()
    {:ok, lobby} = Lobbies.create_lobby(%{title: "once-spectated", host_id: host.id})
    socket = join_as(spectator, "lobby:#{lobby.id}")
    assert_push "updated", _

    {:ok, _} = Lobbies.transition_state(lobby, "starting")

    assert_push "state_changed", %{to: "starting"}
    refute_second(socket, "state_changed")
  end

  test "party: a broadcast on the party topic is pushed once" do
    leader = user()
    {:ok, party} = Parties.create_party(leader, %{})
    socket = join_as(leader, "party:#{party.id}")
    assert_push "updated", _, 500

    Phoenix.PubSub.broadcast(Gamend.PubSub, "party:#{party.id}", {:party_disbanded, party.id})

    assert_push "disbanded", %{party_id: _}
    refute_second(socket, "disbanded")
  end

  test "group: a broadcast on the group topic is pushed once" do
    owner = user()

    {:ok, group} =
      Groups.create_group(owner.id, %{
        "title" => "once-#{System.unique_integer([:positive])}",
        "type" => "public"
      })

    socket = join_as(owner, "group:#{group.id}")

    Phoenix.PubSub.broadcast(
      Gamend.PubSub,
      "group:#{group.id}",
      {:member_left, group.id, owner.id}
    )

    assert_push "member_left", %{group_id: _}
    refute_second(socket, "member_left")
  end

  test "lobbies feed: a broadcast is pushed once" do
    socket = join_as(user(), "lobbies")
    lobby_id = Ecto.UUID.generate()

    Phoenix.PubSub.broadcast(Gamend.PubSub, "lobbies", {:lobby_deleted, lobby_id})

    assert_push "lobby_deleted", %{id: ^lobby_id}
    refute_second(socket, "lobby_deleted")
  end

  test "groups feed: a broadcast is pushed once" do
    socket = join_as(user(), "groups")
    group_id = Ecto.UUID.generate()

    Phoenix.PubSub.broadcast(Gamend.PubSub, "groups", {:group_deleted, group_id})

    assert_push "group_deleted", %{id: ^group_id}
    refute_second(socket, "group_deleted")
  end

  # The user channel was never part of the original bug, but it is the one
  # channel that subscribes to a whole set of extra topics in `after_join`
  # (notifications, tournaments, matchmaking, economy, inventory). Any of those
  # colliding with `"user:<id>"` would double every event on it.
  test "user: a broadcast on the user topic is pushed once" do
    player = user()
    socket = join_as(player, "user:#{player.id}")

    Phoenix.PubSub.broadcast(
      Gamend.PubSub,
      "user:#{player.id}",
      {:wallet_updated, %{currency: "coins", balance: 5, delta: 5}}
    )

    assert_push "wallet_updated", %{balance: 5}
    refute_second(socket, "wallet_updated")
  end

  # Chat is the one topic these channels DO subscribe to explicitly, which makes
  # it the place a second subscription could come back unnoticed: it is a
  # different topic from the channel's own, so nothing else would complain.
  test "lobby chat: a message is pushed once" do
    host = user()
    {:ok, lobby} = Lobbies.create_lobby(%{title: "chat-once", host_id: host.id})
    socket = join_as(host, "lobby:#{lobby.id}")
    assert_push "updated", _

    {:ok, _} =
      Chat.send_message(%{user: host}, %{
        "chat_type" => "lobby",
        "chat_ref_id" => lobby.id,
        "content" => "ahoy"
      })

    assert_push "chat_message_created", %{content: "ahoy"}
    refute_second(socket, "chat_message_created")
  end

  # A client that asks for the same key twice — two panels, a retry after a
  # wobble — must not be registered twice. The Godot SDK keeps its own set of
  # subscribed keys, but delivery counts are the server's business.
  test "kv: subscribing to the same key twice still delivers once" do
    player = user()
    socket = join_as(player, "user:#{player.id}")

    ref = push(socket, "kv:subscribe", %{"key" => "single_delivery", "user_id" => player.id})
    assert_reply ref, :ok, _

    ref = push(socket, "kv:subscribe", %{"key" => "single_delivery", "user_id" => player.id})
    assert_reply ref, :ok, _

    {:ok, _} = KV.put("single_delivery", %{"n" => 1}, %{}, user_id: player.id)

    assert_push "kv_updated", %{key: "single_delivery"}
    refute_second(socket, "kv_updated")
  end
end
