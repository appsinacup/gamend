defmodule Gamend.ParamType do
  @moduledoc """
  The type names shown for an argument in the runtime pages.
  """

  use Gamend.Names, ~w(string integer float boolean list map unknown)
end
