defmodule Gamend.ClientLogs.BuildKind do
  @moduledoc """
  The kind of build a client log came from.
  """

  use Gamend.Names, ~w(debug release)
end
