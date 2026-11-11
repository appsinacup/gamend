defmodule GamendWeb.NudgeRhythm do
  @moduledoc """
  How often a page's next step moves (`gamend.js`, `nudge`): `always`, a 2 s
  beat that never stops, or `rest`, two beats then still until the next
  round. A site's config JSON names it (`"nudge": {"rhythm": "rest"}`);
  `GamendWeb.HostLayouts.nudge/0` writes it on `<html data-nudge-rhythm>`.
  """

  use Gamend.Names, ~w(always rest)
end
