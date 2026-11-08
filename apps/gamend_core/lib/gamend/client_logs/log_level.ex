defmodule Gamend.ClientLogs.LogLevel do
  @moduledoc """
  The levels of a client log.
  """

  @all ~w(trace debug info warn error)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end

  defmacro off, do: "off"

  @doc "Every value."
  @spec all() :: [String.t()]
  def all, do: @all
end
