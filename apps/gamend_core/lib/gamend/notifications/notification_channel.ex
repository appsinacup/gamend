defmodule Gamend.Notifications.NotificationChannel do
  @moduledoc """
  The channels a notification can be sent on.
  """

  use Gamend.Names, ~w(in_app email push)
end
