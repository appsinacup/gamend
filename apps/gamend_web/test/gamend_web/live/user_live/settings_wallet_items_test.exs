defmodule GamendWeb.UserLive.SettingsWalletItemsTest do
  use GamendWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Gamend.AccountsFixtures
  alias Gamend.Economy
  alias Gamend.Inventory

  test "user sees their own wallet balances and ledger", %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    other = AccountsFixtures.user_fixture()

    {:ok, _} = Economy.grant(user.id, "gold", 120, reason: "quest_reward")
    {:ok, _} = Economy.spend(user.id, "gold", 20, reason: "shop_purchase")
    {:ok, _} = Economy.grant(other.id, "gold", 999, reason: "not_mine")

    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/users/settings")

    lv |> element(~s(button[phx-click="settings_tab"][phx-value-tab="wallet"])) |> render_click()

    rendered = render(lv)
    assert rendered =~ "gold"
    # net balance 100, and both ledger reasons visible
    assert rendered =~ "100"
    assert rendered =~ "quest_reward"
    assert rendered =~ "shop_purchase"
    refute rendered =~ "not_mine"
  end

  test "user sees their own inventory items", %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    other = AccountsFixtures.user_fixture()

    {:ok, _} = Inventory.grant_item(user.id, "health_potion", 5)
    {:ok, _} = Inventory.grant_item(other.id, "secret_sword", 1)

    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/users/settings")

    lv |> element(~s(button[phx-click="settings_tab"][phx-value-tab="items"])) |> render_click()

    rendered = render(lv)
    assert rendered =~ "health_potion"
    refute rendered =~ "secret_sword"
  end

  test "empty wallet and items render friendly states", %{conn: conn} do
    user = AccountsFixtures.user_fixture()

    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/users/settings")

    lv |> element(~s(button[phx-click="settings_tab"][phx-value-tab="wallet"])) |> render_click()
    assert render(lv) =~ "No results"

    lv |> element(~s(button[phx-click="settings_tab"][phx-value-tab="items"])) |> render_click()
    assert render(lv) =~ "No results"
  end
end
