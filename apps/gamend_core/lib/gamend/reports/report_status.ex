defmodule Gamend.Reports.ReportStatus do
  @moduledoc """
  A report's status before anyone answers it. The other statuses come from the kind.
  """

  use Gamend.Names, ~w(open)

  defmacro fixed, do: "fixed"

  defmacro duplicate, do: "duplicate"
end
