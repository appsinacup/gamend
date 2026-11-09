defmodule GamendWeb.NavAuth do
  @moduledoc """
  Who a navigation entry is shown to.
  """

  use Gamend.Names, ~w(any admin authenticated unauthenticated)
end
