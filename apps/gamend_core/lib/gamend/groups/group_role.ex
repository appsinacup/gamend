defmodule Gamend.Groups.GroupRole do
  @moduledoc """
  A member's role in a group: `group_members.role`.
  """

  @all ~w(admin member)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end

  @doc "Every value."
  @spec all() :: [String.t()]
  def all, do: @all
end
