defmodule GamendWeb.ChannelEvents do
  @moduledoc """
  Handling every channel shares: an event it does not recognise, and a member
  whose presence or profile changed.

  Seven channels each answered an unknown event with the same reply and a debug
  line differing only in its label, and five carried a private copy of the
  `truncate_event/1` that bounds that line. Lobby and party pushed member
  presence identically, and lobby, party and group pushed a member's updated
  profile identically — apart from the wire event names, which are part of each
  channel's documented contract and so are passed in rather than unified.

  The channel callbacks still exist in each channel (a `handle_info/2` clause
  cannot be shared without a macro that would fight the catch-all clauses for
  ordering); they delegate here, the final `handle_info/2` through
  `other_info/2`.
  """

  require Logger

  alias Gamend.Accounts
  alias Gamend.Accounts.User
  alias GamendWeb.ChannelPush
  alias GamendWeb.ChannelUpdates
  alias GamendWeb.Serializers

  @doc """
  A member's brief profile as this socket may see it: a spectator watches the
  lobby from outside it, so gets the public one.
  """
  @spec member_brief(Phoenix.Socket.t(), User.t()) :: map()
  def member_brief(%{assigns: %{spectator: true}}, %User{} = user),
    do: Serializers.public_brief(user)

  def member_brief(_socket, %User{} = user), do: User.serialize_brief(user)

  @doc """
  Replies to an event the channel does not handle.

  Replying rather than crashing matters: a crashed channel takes every broadcast
  it carried with it, and a client cannot tell a dead channel from a quiet one.
  `context` names assigns to include in the debug line, as `[label: assign_key]`.

  Logged at debug, with the name bounded by `truncate/1`. A frame allows a
  128 KB event name and the channels rate-limit their known events only, so a
  warning-level line carrying the name let one socket write unbounded,
  attacker-chosen text into the rotating log and the admin buffer.
  """
  @spec unknown(term(), Phoenix.Socket.t(), keyword(atom())) ::
          {:reply, {:error, map()}, Phoenix.Socket.t()}
  def unknown(event, socket, context \\ []) do
    Logger.debug(fn ->
      details =
        Enum.map_join(context, "", fn {label, key} ->
          " #{label}=#{socket.assigns[key] || "nil"}"
        end)

      "#{channel_name(socket)}: unknown event=#{truncate(event)}#{details}"
    end)

    {:reply, {:error, %{error: "unknown_event"}}, socket}
  end

  @doc """
  The `handle_info/2` every channel ends with: flushes the coalesced updates
  `GamendWeb.ChannelUpdates` scheduled, and ignores anything else -- a channel
  subscribes to broad topics and is sent messages meant for other listeners.

      @impl true
      def handle_info(msg, socket), do: {:noreply, ChannelEvents.other_info(msg, socket)}
  """
  @spec other_info(term(), Phoenix.Socket.t()) :: Phoenix.Socket.t()
  def other_info({:channel_updates_flush, _}, socket), do: ChannelUpdates.flush(socket)
  def other_info(_msg, socket), do: socket

  @doc "An event name bounded for a log line: a client picks the name, and may pick a long one."
  @spec truncate(term()) :: String.t()
  def truncate(event) when is_binary(event), do: binary_part(event, 0, min(byte_size(event), 64))
  def truncate(event), do: inspect(event)

  @doc """
  Pushes a member coming online or going offline, with their brief profile.

  `wire_event` is the channel's own name for it (`"user_online"` on a lobby,
  `"member_online"` on a party).
  """
  @spec push_presence(
          Phoenix.Socket.t(),
          :member_online | :member_offline,
          Ecto.UUID.t(),
          String.t()
        ) ::
          Phoenix.Socket.t()
  def push_presence(socket, event, user_id, wire_event) do
    payload =
      case Accounts.get_user(user_id) do
        %User{} = user ->
          socket |> member_brief(user) |> Map.put(:user_id, user_id)

        nil ->
          %{user_id: user_id, display_name: "", is_online: event == :member_online}
      end

    ChannelPush.push_event(socket, wire_event, payload)
    socket
  end

  @doc """
  Pushes a member's updated profile, deduplicated by `ChannelUpdates`. Nothing
  is pushed for a user who no longer exists.
  """
  @spec push_member_updated(Phoenix.Socket.t(), Ecto.UUID.t(), String.t()) :: Phoenix.Socket.t()
  def push_member_updated(socket, user_id, wire_event) do
    case Accounts.get_user(user_id) do
      %User{} = user ->
        payload = socket |> member_brief(user) |> Map.put(:user_id, user_id)
        ChannelUpdates.push(socket, wire_event, user_id, payload)

      nil ->
        socket
    end
  end

  defp channel_name(%{channel: channel}) when is_atom(channel) and not is_nil(channel),
    do: channel |> Module.split() |> List.last()

  defp channel_name(_socket), do: "Channel"
end
