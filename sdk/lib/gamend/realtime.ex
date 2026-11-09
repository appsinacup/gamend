defmodule Gamend.Realtime do
  @moduledoc ~S"""
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


  **Note:** This is an SDK stub. Calling these functions will raise an error.
  The actual implementation runs on the Gamend.
  """

  @doc ~S"""
    Pushes `event` with `payload` to one user's socket.
    
    Returns `:ok`, or `{:error, :undeclared_event}` when the plugin has not
    declared the event name.
    
  """
  @spec push_to_user(Ecto.UUID.t(), String.t(), map()) :: :ok | {:error, :undeclared_event}
  def push_to_user(_user_id, _event, _payload \\ %{}) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if reason = Application.get_env(:gamend_sdk, :stub_error), do: {:error, reason}, else: :ok

      _ ->
        raise "Gamend.Realtime.push_to_user/3 is a stub - only available at runtime on Gamend"
    end
  end
end
