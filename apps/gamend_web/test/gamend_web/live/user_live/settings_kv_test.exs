defmodule GamendWeb.UserLive.SettingsKVTest do
  use GamendWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Gamend.AccountsFixtures
  alias Gamend.KV

  test "user sees only their own kv entries, and filters them by key", %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    other = AccountsFixtures.user_fixture()

    {:ok, own} = KV.put("my-kv:own", %{v: 1}, %{"m" => "a"}, user_id: user.id)
    {:ok, aaa} = KV.put("filter:key:aaa", %{v: 1}, %{"m" => "a"}, user_id: user.id)
    {:ok, _} = KV.put("my-kv:other", %{v: 2}, %{"m" => "b"}, user_id: other.id)
    {:ok, _} = KV.put("my-kv:global", %{v: 3}, %{"m" => "g"})

    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/users/settings")

    # Switch to data tab
    lv |> element(~s(button[phx-click="settings_tab"][phx-value-tab="data"])) |> render_click()

    rendered = render(lv)
    assert rendered =~ "my-kv:own"
    refute rendered =~ "my-kv:other"
    refute rendered =~ "my-kv:global"

    _ = render_change(lv, :kv_filters_change, %{"filters" => %{"key" => ":aaa"}})
    assert has_element?(lv, "#user-kv-#{aaa.id}")
    refute has_element?(lv, "#user-kv-#{own.id}")
  end
end
