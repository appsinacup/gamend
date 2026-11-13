defmodule GamendWeb.UserChannelMatchmakingTest do
  use ExUnit.Case, async: false

  import Phoenix.ChannelTest

  alias Gamend.Accounts.Online
  alias Gamend.AccountsFixtures
  alias Gamend.Matchmaking
  alias Gamend.Matchmaking.Worker
  alias GamendWeb.Auth.Guardian

  @endpoint GamendWeb.Endpoint

  setup tags do
    Gamend.DataCase.setup_sandbox(tags)
    :ok
  end

  defp join_user_channel(user) do
    {:ok, token, _claims} = Guardian.encode_and_sign(user)
    {:ok, socket} = connect(GamendWeb.UserSocket, %{"token" => token})
    {:ok, _, socket} = subscribe_and_join(socket, "user:#{user.id}", %{})
    # drain the on-join profile push
    assert_push "updated", _user_payload
    socket
  end

  defp user_fixture, do: AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()

  test "matched players receive match_found on their user channel" do
    alice = user_fixture()
    bob = user_fixture()

    _alice_socket = join_user_channel(alice)
    _bob_socket = join_user_channel(bob)

    {:ok, _} = Matchmaking.join(alice, %{"mode" => "duel"}, 2, 2)
    {:ok, _} = Matchmaking.join(bob, %{"mode" => "duel"}, 2, 2)

    assert Worker.sweep() == 1

    assert_push "match_found", %{lobby_id: lobby_id, match_params: %{"mode" => "duel"}}
    assert is_binary(lobby_id)
  end

  test "matchmaking:join is no longer a channel push (moved to HTTP)" do
    socket = join_user_channel(user_fixture())

    ref = push(socket, "matchmaking:join", %{"match_params" => %{"mode" => "duel"}})
    assert_reply ref, :error, %{error: "unknown_event"}

    ref = push(socket, "matchmaking:cancel", %{})
    assert_reply ref, :error, %{error: "unknown_event"}
  end

  test "socket disconnect cancels the user's queued tickets" do
    user = user_fixture()
    socket = join_user_channel(user)

    {:ok, _} = Matchmaking.join(user, %{"mode" => "duel"})
    assert Matchmaking.current_ticket(user.id) != nil

    Process.unlink(socket.channel_pid)
    close(socket)

    assert Matchmaking.current_ticket(user.id) == nil
  end

  # A page change closes the old page's socket before the next one opens
  # (`Online.watch/2`), and a reload or a reconnect does the same.
  test "a socket back within the moment after the last one closed keeps the queue" do
    user = user_fixture()
    old_page = spawn(fn -> Process.sleep(:infinity) end)
    new_page = spawn(fn -> Process.sleep(:infinity) end)
    {:ok, _} = Online.connected(old_page, user.id, "page")
    {:ok, _} = Matchmaking.join(user, %{"mode" => "duel"})

    # Its recheck waits a moment (inline in tests), while the next page opens.
    closing = Task.async(fn -> Online.disconnected(user.id, old_page) end)
    Process.sleep(200)
    {:ok, _} = Online.connected(new_page, user.id, "page")
    Task.await(closing, 10_000)

    assert Matchmaking.current_ticket(user.id) != nil
    assert Gamend.Accounts.get_user(user.id).is_online

    Process.exit(old_page, :kill)
    Process.exit(new_page, :kill)
  end
end
