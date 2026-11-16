defmodule GamendWeb.SocketFormatVisibilityTest do
  @moduledoc """
  The server must be able to answer "is this client on protobuf or JSON".

  It could not before. `ws_format` was assigned on connect and read by
  `ChannelPush`, and that was the whole of its life — nothing logged it, the
  connection tracker did not carry it, and the admin pages could not show it.

  That matters because of one silent failure: a client asking for protobuf on a
  **v1** socket gets JSON instead, with no error on either side. Everything
  keeps working — just uncompressed, with every binary decoder on the client
  idle — so without this there is no way to tell the two apart from the server.
  """
  use ExUnit.Case, async: false

  import Phoenix.ChannelTest

  alias Gamend.AccountsFixtures
  alias GamendWeb.Auth.Guardian
  alias GamendWeb.ConnectionTracker

  @endpoint GamendWeb.Endpoint

  setup tags do
    Gamend.DataCase.setup_sandbox(tags)
    :ok
  end

  defp user_fixture, do: AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()

  defp connect_with(format) do
    user = user_fixture()
    {:ok, token, _claims} = Guardian.encode_and_sign(user)

    params =
      case format do
        nil -> %{"token" => token}
        f -> %{"token" => token, "format" => f}
      end

    {:ok, socket} = connect(GamendWeb.UserSocket, params)
    {user, socket}
  end

  describe "the assign" do
    test "a protobuf request is honoured on a binary-capable socket" do
      {_user, socket} = connect_with("protobuf")

      assert socket.assigns.ws_format == "protobuf"
    end

    test "no request means JSON" do
      {_user, socket} = connect_with(nil)

      assert socket.assigns.ws_format == "json"
    end
  end

  describe "the connection tracker" do
    test "carries the resolved format, not the requested one" do
      {user, _socket} = connect_with("protobuf")

      meta =
        ConnectionTracker.all_registered()
        |> Map.get(:ws_socket, [])
        |> Enum.find_value(fn {_pid, meta} ->
          if Map.get(meta, :user_id) == user.id, do: meta
        end)

      assert meta, "the socket did not register with the tracker"

      assert meta.format == "protobuf",
             "the admin Connections page reads this; without it the wire format is invisible"
    end

    test "a JSON socket is recorded as json rather than left blank" do
      # Absent and "json" would render the same in the UI, but only one of them
      # means "we know".
      {user, _socket} = connect_with(nil)

      meta =
        ConnectionTracker.all_registered()
        |> Map.get(:ws_socket, [])
        |> Enum.find_value(fn {_pid, meta} ->
          if Map.get(meta, :user_id) == user.id, do: meta
        end)

      assert meta.format == "json"
    end
  end
end
