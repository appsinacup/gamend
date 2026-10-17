defmodule Gamend.RealtimeTest do
  # A plugin's own realtime event (`Gamend.Realtime.push_to_user/3`): only an
  # event the plugin declared is pushed; anything else is refused and said
  # in the log, so a client never gets an event nothing documents.
  use Gamend.DataCase, async: false

  import ExUnit.CaptureLog

  alias Gamend.Realtime

  test "an undeclared event is refused and logged, nothing pushed" do
    user_id = Ecto.UUID.generate()
    Phoenix.PubSub.subscribe(Gamend.PubSub, "user:#{user_id}")

    log =
      capture_log(fn ->
        assert Realtime.push_to_user(user_id, "never_declared_event", %{a: 1}) ==
                 {:error, :undeclared_event}
      end)

    assert log =~ "never_declared_event"
    refute_receive {:plugin_event, _, _}, 50
  end
end
