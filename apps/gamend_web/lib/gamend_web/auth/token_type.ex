defmodule GamendWeb.Auth.TokenType do
  @moduledoc """
  A JWT's `typ` claim.
  """

  use Gamend.Names, ~w(access refresh)
end
