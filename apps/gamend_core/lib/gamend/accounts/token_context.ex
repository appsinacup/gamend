defmodule Gamend.Accounts.TokenContext do
  @moduledoc """
  The `user_tokens.context` values that name what a token is for.
  """

  use Gamend.Names, ~w(session login confirm confirm_code)
end
