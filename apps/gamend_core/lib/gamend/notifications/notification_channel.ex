defmodule Gamend.Notifications.NotificationChannel do
  @moduledoc """
  The channels a notification can be sent on.
  """

  @all ~w(in_app email push)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end

  @doc "Every value."
  @spec all() :: [String.t()]
  def all, do: @all
end
