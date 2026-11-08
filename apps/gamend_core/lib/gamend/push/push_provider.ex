defmodule Gamend.Push.PushProvider do
  @moduledoc """
  Who delivers a push token's notifications.
  """

  @all ~w(fcm apns)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end

  @doc "Every value."
  @spec all() :: [String.t()]
  def all, do: @all
end
