defmodule GamendWeb.CheckboxValue do
  @moduledoc """
  The value a checkbox posts when ticked.
  """

  @all ~w(on)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end
end
