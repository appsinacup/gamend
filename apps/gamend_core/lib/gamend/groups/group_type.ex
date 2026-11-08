defmodule Gamend.Groups.GroupType do
  @moduledoc """
  Who can find and join a group: `groups.type`.
  """

  @all ~w(public private hidden)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end

  @doc "Every value."
  @spec all() :: [String.t()]
  def all, do: @all
end
