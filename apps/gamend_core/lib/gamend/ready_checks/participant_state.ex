defmodule Gamend.ReadyChecks.ParticipantState do
  @moduledoc """
  A participant's answer to a ready check.
  """

  @all ~w(pending ready declined timed_out)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end

  @doc "Every value."
  @spec all() :: [String.t()]
  def all, do: @all
end
