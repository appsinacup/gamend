defmodule Gamend.Bans.BanScope do
  @moduledoc """
  Where a chat ban applies.
  """

  @all ~w(global lobby group party)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end

  @doc "Every value."
  @spec all() :: [String.t()]
  def all, do: @all
end
