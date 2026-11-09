defmodule Gamend.ReadyChecks.CheckStatus do
  @moduledoc """
  The states of a ready check: `ready_checks.status`.
  """

  use Gamend.Names, ~w(pending passed failed cancelled)
end
