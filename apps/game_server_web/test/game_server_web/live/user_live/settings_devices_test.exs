defmodule GameServerWeb.UserLive.SettingsDevicesTest do
  use GameServerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias GameServer.AccountsFixtures
  alias GameServer.Push

  defp open_devices_tab(conn, user) do
    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/users/settings")

    lv
    |> element(~s(button[phx-click="settings_tab"][phx-value-tab="devices"]))
    |> render_click()

    lv
  end

  test "user sees only their own registered devices", %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    other = AccountsFixtures.user_fixture()

    {:ok, mine} =
      Push.register_token(user.id, %{"token" => "settings-mine", "platform" => "android"})

    {:ok, disabled} =
      Push.register_token(user.id, %{"token" => "settings-dead", "platform" => "ios"})

    :ok = Push.disable_token(disabled.token)

    {:ok, _} =
      Push.register_token(other.id, %{"token" => "settings-other", "platform" => "web"})

    lv = open_devices_tab(conn, user)
    rendered = render(lv)

    assert rendered =~ "user-device-#{mine.id}"
    assert rendered =~ "user-device-#{disabled.id}"
    assert rendered =~ "android"
    assert rendered =~ "Active"
    assert rendered =~ "Inactive"
    refute rendered =~ "settings-other"
  end

  test "user with no devices sees the empty state", %{conn: conn} do
    user = AccountsFixtures.user_fixture()

    lv = open_devices_tab(conn, user)
    assert render(lv) =~ "No devices registered."
  end

  test "user can remove a device", %{conn: conn} do
    user = AccountsFixtures.user_fixture()

    {:ok, token} =
      Push.register_token(user.id, %{"token" => "settings-remove", "platform" => "android"})

    lv = open_devices_tab(conn, user)

    lv
    |> element(~s(button[phx-click="device_remove"][phx-value-id="#{token.id}"]))
    |> render_click()

    assert Push.count_tokens(user.id) == 0
    assert render(lv) =~ "No devices registered."
  end
end
