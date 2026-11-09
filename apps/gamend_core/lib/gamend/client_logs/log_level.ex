defmodule Gamend.ClientLogs.LogLevel do
  @moduledoc """
  The levels of a client log.
  """

  use Gamend.Names, ~w(trace debug info warn error)

  defmacro off, do: "off"
end
