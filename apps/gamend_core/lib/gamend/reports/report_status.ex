defmodule Gamend.Reports.ReportStatus do
  @moduledoc """
  A report's status before anyone answers it. The other statuses come from the kind.
  """

  use Gamend.Names, ~w(open)

  defmacro fixed, do: "fixed"

  defmacro duplicate, do: "duplicate"

  @doc """
  Never stored: what a filing answers when the report's kind took it
  elsewhere (`c:Gamend.Reports.Kind.take/1`), so no row exists.
  """
  defmacro taken, do: "taken"
end
