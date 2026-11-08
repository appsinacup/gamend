defmodule GamendWeb.ApiSegment do
  @moduledoc """
  The first segments of an API route's path.
  """

  @all ~w(api v1 users log_in register)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end
end
