defmodule Gamend.Realtime do
  @moduledoc """
  Pushing game-defined realtime events to a player's socket.

  Core's own events (`updated`, `notification`, `member_joined`, …) are fixed
  and documented in `GamendWeb.RealtimeEvents`. This is the escape hatch a
  plugin uses for events core knows nothing about — a quest counter, a boss
  spawn — without needing its own channel:

      Gamend.Realtime.push_to_user(user.id, "quest_progress", %{id: 7, step: 2})

  Delivery rides the user's existing `user:<id>` channel, so the client needs
  no new subscription. The payload is JSON; protobuf mapping is reserved for
  core events, whose schemas ship with the clients.

  The event name must be declared by the plugin's `realtime_events/0` callback
  (see `Gamend.Hooks.Declarations`), for the same reason notification codes
  are checked: an undeclared event reaches clients that have no idea it exists,
  and never appears in the admin runtime page.
  """

  alias Gamend.Hooks.Declarations

  require Logger

  @doc """
  Pushes `event` with `payload` to one user's socket.

  Returns `:ok`, or `{:error, :undeclared_event}` when the plugin has not
  declared the event name.
  """
  @spec push_to_user(Ecto.UUID.t(), String.t(), map()) :: :ok | {:error, :undeclared_event}
  def push_to_user(user_id, event, payload \\ %{})
      when is_binary(user_id) and is_binary(event) and is_map(payload) do
    if Map.has_key?(Declarations.realtime_events(), event) do
      topic = "user:#{user_id}"

      Gamend.Broadcast.publish(
        topic,
        {:plugin_event, event, payload}
      )

      :ok
    else
      Logger.warning(
        "realtime push of undeclared event #{inspect(event)}; " <>
          "add it to the plugin's realtime_events/0"
      )

      {:error, :undeclared_event}
    end
  end
end
