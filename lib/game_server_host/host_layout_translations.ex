defmodule GameServerHost.HostLayoutTranslations do
  @moduledoc false

  use Gettext, backend: GameServerHost.Gettext

  def messages do
    [
      gettext_noop("Leaderboards"),
      gettext_noop("Quests"),
      gettext_noop("Groups"),
      gettext_noop("Loading..."),
      gettext_noop("Dismiss"),
      gettext_noop("Log in"),
      gettext_noop("Register"),
      gettext_noop("Account"),
      gettext_noop("Notifications"),
      gettext_noop("Chat"),
      gettext_noop("Admin"),
      gettext_noop("Log out")
    ]
  end
end
