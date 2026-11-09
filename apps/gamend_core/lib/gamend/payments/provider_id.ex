defmodule Gamend.Payments.ProviderId do
  @moduledoc """
  The payment providers core knows, as stored in `purchases.provider`.
  """

  use Gamend.Names, ~w(stripe apple google steam)
end
