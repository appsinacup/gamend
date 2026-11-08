defmodule GamendWeb.NavAuth do
  @moduledoc """
  Who a navigation entry is shown to.
  """

  @all ~w(any admin authenticated unauthenticated)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end
end
