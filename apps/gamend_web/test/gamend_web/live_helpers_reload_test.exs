defmodule GamendWeb.LiveHelpersReloadTest do
  @moduledoc """
  `reload_soon/3`: a burst of "something moved" broadcasts is one reload, not
  one per message (quest progress several times a second, a friend's tabs
  going on- and offline).
  """
  use ExUnit.Case, async: true

  alias GamendWeb.LiveHelpers

  defp socket, do: %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}

  test "a burst schedules one reload, and the next burst another" do
    socket =
      Enum.reduce(1..20, socket(), fn _n, socket ->
        LiveHelpers.reload_soon(socket, :reload, 10)
      end)

    assert_receive :reload, 500
    refute_receive :reload, 50

    socket = LiveHelpers.reloaded(socket, :reload)
    _socket = LiveHelpers.reload_soon(socket, :reload, 10)

    assert_receive :reload, 500
  end

  test "scheduling renders nothing: no assign moves" do
    socket = LiveHelpers.reload_soon(socket(), :reload, 10)

    assert socket.assigns.__changed__ == %{}
    assert_receive :reload, 500
  end

  test "two kinds of reload are scheduled apart" do
    socket()
    |> LiveHelpers.reload_soon({:reload_tab, "friends"}, 10)
    |> LiveHelpers.reload_soon({:reload_tab, "groups"}, 10)

    assert_receive {:reload_tab, "friends"}, 500
    assert_receive {:reload_tab, "groups"}, 500
  end
end
