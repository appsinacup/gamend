defmodule Gamend.Reports.ReportSource do
  @moduledoc """
  Where a report was filed from: core's report page (`web`), the API
  (`api`), or the host's own code (`host`), for a kind no form of core's
  files (`c:Gamend.Reports.Kind.sources/0`): an in-game survey, a form on a
  page of the host's.
  """

  use Gamend.Names, ~w(web api host)
end
