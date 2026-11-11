defmodule GamendWeb.NudgeMove do
  @moduledoc """
  What the `nudge` class does to a page's next step (`app.css`, `nudge`): a
  chevron bouncing beside it (`pointer`), a ring out of its edge, a hop or a
  light across it. A site's config JSON names one, or `pointer` with one of
  the others (`"nudge": {"move": "pointer ring"}`); `GamendWeb.HostLayouts.nudge/0`
  writes it on `<html data-nudge>`.
  """

  use Gamend.Names, ~w(pointer ring hop shine)
end
