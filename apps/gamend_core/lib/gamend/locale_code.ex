defmodule Gamend.LocaleCode do
  @moduledoc """
  A locale spoken in code: the default language.
  """

  @all ~w(en)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end
end
