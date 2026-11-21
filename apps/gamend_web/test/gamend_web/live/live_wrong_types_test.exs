defmodule GamendWeb.LiveWrongTypesTest do
  @moduledoc """
  Every core LiveView, sent each of its events with wrong and odd params,
  stays up (`GamendWeb.Testing.WrongTypes.live_tests/1`). The settings
  page's events are its tabs'. The pages that need a row or a visitor are
  `WrongTypes.core_pages/0`'s.
  """
  use GamendWeb.ConnCase, async: false
  require GamendWeb.Testing.WrongTypes, as: WrongTypes

  WrongTypes.live_tests(
    extra_events: %{
      GamendWeb.UserLive.Settings => [
        GamendWeb.UserLive.Settings.AccountTab,
        GamendWeb.UserLive.Settings.ApiTokensTab,
        GamendWeb.UserLive.Settings.DataTab,
        GamendWeb.UserLive.Settings.DevicesTab,
        GamendWeb.UserLive.Settings.FriendsTab,
        GamendWeb.UserLive.Settings.GroupsTab,
        GamendWeb.UserLive.Settings.ItemsTab,
        GamendWeb.UserLive.Settings.NotificationsTab,
        GamendWeb.UserLive.Settings.PaymentsTab,
        GamendWeb.UserLive.Settings.WalletTab
      ]
    }
  )
end
