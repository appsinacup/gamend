defmodule Gamend.Accounts.TokenContext do
  @moduledoc """
  The `user_tokens.context` values that name what a token is for.
  """

  @all ~w(session login confirm confirm_code)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end
end
