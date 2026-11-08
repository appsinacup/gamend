defmodule Gamend.Reports.ReportSource do
  @moduledoc """
  Where a report was filed from.
  """

  @all ~w(web)

  for name <- @all do
    defmacro unquote(String.to_atom(name))(), do: unquote(name)
  end
end
