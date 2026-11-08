defmodule Gamend.ReadyChecks.CheckStatus do
  @moduledoc """
  The states of a ready check: `ready_checks.status`.
  """

  @all ~w(pending passed failed cancelled)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end

  @doc "Every value."
  @spec all() :: [String.t()]
  def all, do: @all
end
