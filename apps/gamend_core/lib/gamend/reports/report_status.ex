defmodule Gamend.Reports.ReportStatus do
  @moduledoc """
  A report's status before anyone answers it. The other statuses come from the kind.
  """

  @all ~w(open)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end

  defmacro fixed, do: "fixed"

  defmacro duplicate, do: "duplicate"
end
