defmodule Gamend.Groups.GroupInviteStatus do
  @moduledoc """
  The states of an invitation to a group.
  """

  @all ~w(pending accepted declined cancelled)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end

  @doc "Every value."
  @spec all() :: [String.t()]
  def all, do: @all
end
