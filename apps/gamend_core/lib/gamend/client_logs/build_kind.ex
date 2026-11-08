defmodule Gamend.ClientLogs.BuildKind do
  @moduledoc """
  The kind of build a client log came from.
  """

  @all ~w(debug release)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end

  @doc "Every value."
  @spec all() :: [String.t()]
  def all, do: @all
end
