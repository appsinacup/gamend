defmodule GamendWeb.AdminLive.ThemeTest do
  # Swaps the theme file, which every page reads.
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Content
  alias Gamend.Repo
  alias Gamend.SettingsHelpers
  alias Gamend.Theme.JSONConfig

  setup %{conn: conn} do
    admin =
      AccountsFixtures.user_fixture()
      |> User.admin_changeset(%{"is_admin" => true})
      |> Repo.update!()

    previous = SettingsHelpers.get(:gamend_core, Gamend.ContentSettings, :theme_config)

    on_exit(fn ->
      if previous,
        do: SettingsHelpers.put(:gamend_core, Gamend.ContentSettings, :theme_config, previous),
        else: SettingsHelpers.delete(:gamend_core, Gamend.ContentSettings, :theme_config)

      JSONConfig.reload()
      Content.reload()
    end)

    %{conn: log_in_user(conn, admin)}
  end

  defp use_theme(value) do
    SettingsHelpers.put(:gamend_core, Gamend.ContentSettings, :theme_config, value)
    JSONConfig.reload()
    Content.reload()
  end

  test "renders what a configured theme resolved to", %{conn: conn} do
    path = Path.join(System.tmp_dir!(), "theme_test_#{System.unique_integer([:positive])}.json")
    on_exit(fn -> File.rm_rf(path) end)

    File.write!(
      path,
      Jason.encode!(%{
        "title" => "Test Theme",
        "logo" => "/theme/test-logo.png",
        "banner" => "/theme/test-banner.png",
        "navigation" => %{
          "primary_links" => [
            %{"label" => "Social", "items" => [%{"label" => "Status", "href" => "/status"}]}
          ],
          "account_links" => [%{"label" => "Billing", "href" => "/billing"}]
        }
      })
    )

    use_theme(path)

    {:ok, view, html} = live(conn, ~p"/admin/theme")

    assert has_element?(view, "#theme-source", "Configured")
    assert has_element?(view, "#theme-source", path)
    assert has_element?(view, "#theme-raw-json", "Test Theme")
    assert has_element?(view, "img[src='/theme/test-logo.png']")
    assert html =~ "Primary Nav"
    assert html =~ "Social"
    assert has_element?(view, "#main-navbar a[href='/status']")
    assert has_element?(view, "#main-navbar a[href='/billing']")
  end

  test "says so when no theme is configured", %{conn: conn} do
    SettingsHelpers.delete(:gamend_core, Gamend.ContentSettings, :theme_config)
    JSONConfig.reload()
    Content.reload()

    {:ok, view, _html} = live(conn, ~p"/admin/theme")

    assert has_element?(view, "#theme-source", "Default")
    assert has_element?(view, "#theme-source", "<unset>")
  end

  test "a blank setting counts as unset", %{conn: conn} do
    use_theme("")

    {:ok, view, _html} = live(conn, ~p"/admin/theme")

    assert has_element?(view, "#theme-source", "Default")
  end
end
