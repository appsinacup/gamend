defmodule GamendWeb.WsFormat do
  @moduledoc """
  How a socket's frames are encoded.
  """

  @all ~w(json protobuf)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end

  @doc "Every value."
  @spec all() :: [String.t()]
  def all, do: @all
end
