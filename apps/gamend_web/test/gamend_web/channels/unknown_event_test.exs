defmodule GamendWeb.UnknownEventTest do
  @moduledoc """
  Every channel answers an event it does not recognise, and stays up.

  A reply of `{:stop, :normal, {:error, ...}}` would mean one unrecognised push
  and the channel is gone. That is silent from the client side: a stopped channel looks exactly like a quiet one, so the broadcasts it
  carried simply never arrive again. On `lobby:` those broadcasts are the
  player's word data, so the next game start waits out its timeout with nothing
  to show for it.

  `Process.alive?(channel_pid)` is the assertion that matters here; the reply is
  the easy half.
  """
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Phoenix.ChannelTest

  alias Gamend.AccountsFixtures
  alias Gamend.Groups
  alias Gamend.Lobbies
  alias Gamend.Parties
  alias Gamend.Signaling
  alias GamendWeb.Auth.Guardian
  alias GamendWeb.UserSocket

  @endpoint GamendWeb.Endpoint

  setup tags do
    Gamend.DataCase.setup_sandbox(tags)
    :ok
  end

  defp user, do: AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()

  defp join_as(user, topic) do
    {:ok, token, _claims} = Guardian.encode_and_sign(user)
    {:ok, socket} = connect(UserSocket, %{"token" => token})
    {:ok, _reply, joined} = subscribe_and_join(socket, topic, %{})
    joined
  end

  ## Pushes something no channel handles, and checks the channel survived it.
  ## Twice on purpose: the second reply can only arrive from a process the first
  ## one did not kill.
  defp assert_survives_unknown_event(socket, label) do
    capture_log(fn ->
      ref = push(socket, "not_an_event_any_channel_knows", %{})
      assert_reply ref, :error, %{error: "unknown_event"}, 1000

      assert Process.alive?(socket.channel_pid),
             "#{label} stopped itself over an unrecognised event"

      second = push(socket, "still_not_an_event", %{"payload" => "ignored"})
      assert_reply second, :error, %{error: "unknown_event"}, 1000
      assert Process.alive?(socket.channel_pid), "#{label} did not survive a second one"
    end)
  end

  test "user channel" do
    me = user()
    assert_survives_unknown_event(join_as(me, "user:#{me.id}"), "UserChannel")
  end

  test "lobby channel" do
    host = user()
    {:ok, lobby} = Lobbies.create_lobby(%{title: "unknown-event", host_id: host.id})
    assert_survives_unknown_event(join_as(host, "lobby:#{lobby.id}"), "LobbyChannel")
  end

  test "lobbies channel" do
    assert_survives_unknown_event(join_as(user(), "lobbies"), "LobbiesChannel")
  end

  test "party channel" do
    leader = user()
    {:ok, party} = Parties.create_party(leader, %{})
    assert_survives_unknown_event(join_as(leader, "party:#{party.id}"), "PartyChannel")
  end

  test "group channel" do
    owner = user()

    {:ok, group} =
      Groups.create_group(owner.id, %{
        "title" => "unknown-event-#{System.unique_integer([:positive])}",
        "type" => "public"
      })

    assert_survives_unknown_event(join_as(owner, "group:#{group.id}"), "GroupChannel")
  end

  test "groups channel" do
    assert_survives_unknown_event(join_as(user(), "groups"), "GroupsChannel")
  end

  test "signaling channel" do
    host = user()
    {:ok, lobby} = Lobbies.create_lobby(%{"title" => "unknown-event", "host_id" => host.id})

    {:ok, lobby} =
      Signaling.configure(lobby, enabled: true, topology: :mesh, reconnect_timeout: 0)

    assert_survives_unknown_event(join_as(host, "signaling:#{lobby.id}"), "SignalingChannel")
  end
end
