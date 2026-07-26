defmodule GameServerWeb.ChannelUpdatesTest do
  @moduledoc """
  Dedupe and debounce for outbound channel state updates. Drives a bare
  Phoenix.Channel so the behaviour is exercised through real push/flush,
  not a mock.
  """
  use ExUnit.Case
  import Phoenix.ChannelTest

  alias GameServerWeb.ChannelUpdates

  @endpoint GameServerWeb.Endpoint

  defmodule TestChannel do
    use Phoenix.Channel

    def join("cu:test", _params, socket), do: {:ok, socket}

    # Test driver: forward calls into ChannelUpdates and keep the socket.
    def handle_in("push", %{"key" => key, "payload" => payload}, socket) do
      {:noreply, ChannelUpdates.push(socket, "updated", key, payload)}
    end

    def handle_info({:channel_updates_flush, _}, socket),
      do: {:noreply, ChannelUpdates.flush(socket)}
  end

  setup tags do
    GameServer.DataCase.setup_sandbox(tags)

    prev = Application.get_env(:game_server_web, GameServerWeb.Realtime)

    on_exit(fn ->
      if prev,
        do: Application.put_env(:game_server_web, GameServerWeb.Realtime, prev),
        else: Application.delete_env(:game_server_web, GameServerWeb.Realtime)
    end)

    {:ok, _, socket} =
      socket(GameServerWeb.UserSocket, "cu", %{})
      |> subscribe_and_join(TestChannel, "cu:test", %{})

    %{socket: socket}
  end

  defp set_debounce(ms),
    do: Application.put_env(:game_server_web, GameServerWeb.Realtime, debounce_ms: ms)

  describe "with debounce off (default)" do
    setup do
      set_debounce(0)
      :ok
    end

    test "pushes each distinct payload immediately", %{socket: socket} do
      push(socket, "push", %{"key" => "a", "payload" => %{"n" => 1}})
      assert_push "updated", %{"n" => 1}

      push(socket, "push", %{"key" => "a", "payload" => %{"n" => 2}})
      assert_push "updated", %{"n" => 2}
    end

    test "drops a payload identical to the last one", %{socket: socket} do
      push(socket, "push", %{"key" => "a", "payload" => %{"n" => 1}})
      assert_push "updated", %{"n" => 1}

      push(socket, "push", %{"key" => "a", "payload" => %{"n" => 1}})
      refute_push "updated", _, 50
    end

    test "different keys do not suppress each other", %{socket: socket} do
      push(socket, "push", %{"key" => "a", "payload" => %{"n" => 1}})
      assert_push "updated", %{"n" => 1}

      push(socket, "push", %{"key" => "b", "payload" => %{"n" => 1}})
      assert_push "updated", %{"n" => 1}
    end
  end

  describe "with debounce on" do
    setup do
      set_debounce(80)
      :ok
    end

    test "holds updates, then pushes only the latest per key", %{socket: socket} do
      push(socket, "push", %{"key" => "a", "payload" => %{"n" => 1}})
      push(socket, "push", %{"key" => "a", "payload" => %{"n" => 2}})
      push(socket, "push", %{"key" => "a", "payload" => %{"n" => 3}})

      # nothing yet — the window has not elapsed
      refute_push "updated", _, 20

      # one message, carrying the final state
      assert_push "updated", %{"n" => 3}, 200
      refute_push "updated", _, 50
    end

    test "coalesces per key, so two objects yield two messages", %{socket: socket} do
      push(socket, "push", %{"key" => "a", "payload" => %{"n" => 1}})
      push(socket, "push", %{"key" => "b", "payload" => %{"n" => 1}})
      push(socket, "push", %{"key" => "a", "payload" => %{"n" => 2}})

      assert_push "updated", first, 200
      assert_push "updated", second, 200
      # a -> 2 and b -> 1, in deterministic key order
      assert Enum.sort([first["n"], second["n"]]) == [1, 2]
    end

    test "a no-op update inside the window is not queued", %{socket: socket} do
      push(socket, "push", %{"key" => "a", "payload" => %{"n" => 1}})
      # same value again: nothing new to send
      push(socket, "push", %{"key" => "a", "payload" => %{"n" => 1}})

      assert_push "updated", %{"n" => 1}, 200
      refute_push "updated", _, 50
    end
  end
end
