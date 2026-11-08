defmodule Gamend.ReadyChecks.CheckReason do
  @moduledoc """
  Why a ready check ended without passing.
  """

  @all ~w(timeout declined reset cancelled)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end
end
