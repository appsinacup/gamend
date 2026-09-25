defmodule GamendWeb.ConfigurablePagesTest do
  @moduledoc """
  The pages that follow the new `auth.*` settings: deleting an account with a
  grace period, API token lifetimes under a cap, and the admin controls for a
  scheduled deletion and a locked password.
  """
  # Settings are global Application config.
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gamend.Accounts
  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Repo
  alias Gamend.SettingsHelpers

  defp put_setting(key, value) do
    SettingsHelpers.put(:gamend_core, Accounts, key, value)
    on_exit(fn -> SettingsHelpers.delete(:gamend_core, Accounts, key) end)
  end

  defp admin do
    {:ok, admin} =
      AccountsFixtures.user_fixture()
      |> User.admin_changeset(%{"is_admin" => true})
      |> Repo.update()

    admin
  end

  test "deleting your account with a grace period schedules it", %{conn: conn} do
    put_setting(:deletion_grace_days, 14)
    user = AccountsFixtures.user_fixture()

    conn = log_in_user(conn, user)
    {:ok, lv, _html} = live(conn, ~p"/users/settings")

    assert lv |> element("#delete-account-button") |> render() =~ "deleted in 14 days"

    {:ok, conn} =
      lv
      |> element("#delete-account-button")
      |> render_click()
      |> follow_redirect(conn, "/")

    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "will be deleted in 14 days"
    assert Accounts.deletion_scheduled?(Repo.get!(User, user.id))
  end

  test "under a cap, the API token form offers only lifetimes within it", %{conn: conn} do
    put_setting(:api_token_max_days, 60)
    user = AccountsFixtures.user_fixture()

    {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/users/settings")

    lv
    |> element(~s(button[phx-click="settings_tab"][phx-value-tab="api_tokens"]))
    |> render_click()

    options = lv |> element("#api-token-form select") |> render()

    assert options =~ ~s(value="30")
    assert options =~ ~s(value="60")
    refute options =~ ~s(value="never")
    refute options =~ ~s(value="90")
    assert options =~ ~r/<option[^>]*selected[^>]*value="60"|<option[^>]*value="60"[^>]*selected/
  end

  describe "admin users page" do
    test "shows a scheduled deletion and keeps the account", %{conn: conn} do
      put_setting(:deletion_grace_days, 14)
      player = AccountsFixtures.user_fixture()
      {:ok, {:scheduled, _, _}} = Accounts.request_deletion(player)

      {:ok, lv, html} = conn |> log_in_user(admin()) |> live(~p"/admin/users")
      assert html =~ "Deleting"

      render_click(lv, "edit_user", %{"id" => player.id})
      assert has_element?(lv, "#admin-user-deletion-scheduled")

      lv |> element("#admin-keep-account") |> render_click()

      refute has_element?(lv, "#admin-user-deletion-scheduled")
      refute Accounts.deletion_scheduled?(Repo.get!(User, player.id))
    end

    test "shows a locked password and unlocks it", %{conn: conn} do
      put_setting(:lockout_attempts, 1)
      player = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()

      assert {:error, {:locked, _}} =
               Accounts.authenticate_by_password(player.email, "wrong password!")

      {:ok, lv, _html} = conn |> log_in_user(admin()) |> live(~p"/admin/users")
      render_click(lv, "edit_user", %{"id" => player.id})
      assert has_element?(lv, "#admin-user-login-locked")

      lv |> element("#admin-unlock-login") |> render_click()

      refute has_element?(lv, "#admin-user-login-locked")

      assert {:ok, _} =
               Accounts.authenticate_by_password(
                 player.email,
                 AccountsFixtures.valid_user_password()
               )
    end
  end
end
