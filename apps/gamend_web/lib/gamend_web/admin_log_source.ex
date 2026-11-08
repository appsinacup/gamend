defmodule GamendWeb.AdminLogSource do
  @moduledoc """
  Which logs the admin logs page shows.
  """

  @all ~w(server client)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end

  @doc "Every value."
  @spec all() :: [String.t()]
  def all, do: @all
end
