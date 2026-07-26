defmodule GameServerWeb.AdminLive.SettingsTest do
  use GameServerWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias GameServer.Accounts.User
  alias GameServer.AccountsFixtures
  alias GameServer.Repo
  alias GameServer.Settings

  setup %{conn: conn} do
    admin =
      AccountsFixtures.user_fixture()
      |> User.admin_changeset(%{"is_admin" => true})
      |> Repo.update!()

    %{conn: log_in_user(conn, admin)}
  end

  test "lists every declared group and setting", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/admin/settings")

    for {_group, label} <- Settings.groups() do
      # Labels like "Content & plugins" arrive HTML-escaped.
      assert html =~ String.replace(label, "&", "&amp;"), "group #{label} missing from the page"
    end

    assert html =~ "GAMEND_RETENTION_CHAT_MESSAGES_DAYS"
    assert html =~ "GAMEND_LIMITS_MAX_METADATA_SIZE"
    assert html =~ "#{length(Settings.all())}"
  end

  test "masks secrets rather than printing them", %{conn: conn} do
    previous = Application.get_env(:game_server_core, GameServer.Accounts)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:game_server_core, GameServer.Accounts, previous),
        else: Application.delete_env(:game_server_core, GameServer.Accounts)
    end)

    Application.put_env(
      :game_server_core,
      GameServer.Accounts,
      Keyword.put(previous || [], :guardian_secret_key, "super-secret-value")
    )

    {:ok, _view, html} = live(conn, ~p"/admin/settings")

    refute html =~ "super-secret-value"
    assert html =~ "••••••••"
  end

  test "filtering narrows to matching settings", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/settings")

    html = view |> element("input[type=text]") |> render_keyup(%{"value" => "chat"})

    assert html =~ "GAMEND_RETENTION_CHAT_MESSAGES_DAYS"
    refute html =~ "GAMEND_STORAGE_BUCKET"
  end

  test "the group dropdown narrows to one group", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/admin/settings")

    assert html =~ "GAMEND_RETENTION_CHAT_MESSAGES_DAYS"

    filtered = view |> element("form[phx-change=group]") |> render_change(%{"group" => "storage"})

    assert filtered =~ "GAMEND_STORAGE_BUCKET"
    refute filtered =~ "GAMEND_RETENTION_CHAT_MESSAGES_DAYS"

    # Back to everything.
    all = view |> element("form[phx-change=group]") |> render_change(%{"group" => ""})
    assert all =~ "GAMEND_RETENTION_CHAT_MESSAGES_DAYS"
  end

  test "every group is offered in the dropdown", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/admin/settings")

    for {group, _label} <- Settings.groups() do
      assert html =~ ~s(value="#{group}"), "group #{group} missing from the dropdown"
    end
  end

  test "shows which values came from config rather than the default", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/admin/settings")

    assert html =~ "default"
    assert html =~ "config"
  end

  test "no setting escapes the naming convention", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/admin/settings")

    # Every declared variable is derived, so each is GAMEND_ or a plugin root.
    for definition <- Settings.all() do
      assert String.starts_with?(definition.env, "GAMEND_") or
               String.starts_with?(definition.env, "POLYGLOT_"),
             "#{definition.env} does not follow the convention"
    end

    refute html =~ "inherited"
  end
end
