defmodule GamendWeb.UserLive.SettingsApiTokensTest do
  use GamendWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Gamend.Accounts.ApiTokens
  alias Gamend.AccountsFixtures

  defp open_tab(conn, user) do
    {:ok, lv, _html} =
      conn
      |> log_in_user(user)
      |> live(~p"/users/settings")

    lv
    |> element(~s(button[phx-click="settings_tab"][phx-value-tab="api_tokens"]))
    |> render_click()

    lv
  end

  test "creating a token shows it once, and it works", %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    lv = open_tab(conn, user)

    lv
    |> form("#api-token-form", api_token: %{name: "release script", expires_in_days: "30"})
    |> render_submit()

    token =
      lv
      |> element("#api-token-value")
      |> render()
      |> then(&Regex.run(~r/gamend_pat_[\w-]+/, &1))
      |> hd()

    assert {:ok, verified, row} = ApiTokens.verify(token)
    assert verified.id == user.id
    assert row.name == "release script"
    assert has_element?(lv, "#user-api-token-#{row.id}")

    # Dismissed, it is gone from the page for good; the list keeps only a hint.
    lv |> element(~s(button[phx-click="api_token_dismiss"])) |> render_click()
    refute render(lv) =~ token
    assert render(lv) =~ "gamend_pat_" <> row.hint
  end

  test "revoking a token stops it", %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    {:ok, token, row} = ApiTokens.create(user, %{"name" => "old"})
    lv = open_tab(conn, user)

    lv
    |> element(~s(button[phx-click="api_token_revoke"][phx-value-id="#{row.id}"]))
    |> render_click()

    refute has_element?(lv, "#user-api-token-#{row.id}")
    assert ApiTokens.verify(token) == :error
  end

  test "lists only the user's own tokens", %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    {:ok, _, mine} = ApiTokens.create(user, %{"name" => "mine"})
    {:ok, _, theirs} = ApiTokens.create(AccountsFixtures.user_fixture(), %{"name" => "theirs"})

    lv = open_tab(conn, user)

    assert has_element?(lv, "#user-api-token-#{mine.id}")
    refute has_element?(lv, "#user-api-token-#{theirs.id}")
  end

  test "a missing name is refused on the form", %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    lv = open_tab(conn, user)

    html =
      lv
      |> form("#api-token-form", api_token: %{name: "", expires_in_days: "90"})
      |> render_submit()

    assert html =~ "can&#39;t be blank" or html =~ "can't be blank"
    assert ApiTokens.count(user.id) == 0
  end
end
