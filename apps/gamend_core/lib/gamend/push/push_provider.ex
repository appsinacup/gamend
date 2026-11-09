defmodule Gamend.Push.PushProvider do
  @moduledoc """
  Who delivers a push token's notifications.
  """

  use Gamend.Names, ~w(fcm apns)
end
