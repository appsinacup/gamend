defmodule GamendWeb.NavSize do
  @moduledoc """
  What the navigation is from a window width on, in a host's fixed table
  (`"navigation"`'s `"sizes"`, `HostLayoutNavigation.nav_sizes/1`): `bar`
  the links in the top bar (its own stages still fit by measure, then its
  menu), `rail` the sidebar collapsed with no way to open it, `sidebar` the
  sidebar open or collapsed as the reader leaves it (open by default).
  Below `md` a sidebar mode is the phone's tab bar.
  """

  use Gamend.Names, ~w(bar rail sidebar)
end
