defmodule Gamend.Payments.EntitlementStatus do
  @moduledoc """
  The states of an entitlement.
  """

  use Gamend.Names, ~w(active expired revoked)
end
