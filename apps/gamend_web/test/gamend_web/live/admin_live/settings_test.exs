defmodule GamendWeb.AdminLive.SettingsTest do
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Repo
  alias Gamend.Settings

  setup %{conn: conn} do
    admin =
      AccountsFixtures.user_fixture()
      |> User.admin_changeset(%{"is_admin" => true})
      |> Repo.update!()

    %{conn: log_in_user(conn, admin), admin: admin}
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
    previous = Application.get_env(:gamend_core, Gamend.Accounts)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:gamend_core, Gamend.Accounts, previous),
        else: Application.delete_env(:gamend_core, Gamend.Accounts)
    end)

    Application.put_env(
      :gamend_core,
      Gamend.Accounts,
      Keyword.put(previous || [], :guardian_secret_key, "super-secret-value")
    )

    {:ok, _view, html} = live(conn, ~p"/admin/settings")

    refute html =~ "super-secret-value"
    assert html =~ "••••••••"
  end

  describe "the .env download" do
    setup do
      previous = Application.get_env(:gamend_core, Gamend.Accounts)

      on_exit(fn ->
        if previous,
          do: Application.put_env(:gamend_core, Gamend.Accounts, previous),
          else: Application.delete_env(:gamend_core, Gamend.Accounts)
      end)

      Application.put_env(
        :gamend_core,
        Gamend.Accounts,
        Keyword.put(previous || [], :guardian_secret_key, "super-secret-value")
      )

      :ok
    end

    test "the page links to it", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/settings")

      assert has_element?(view, ~s(#settings-export[href="/admin/settings/export"]))
    end

    test "an admin gets real values, uncached", %{conn: conn} do
      conn = get(conn, ~p"/admin/settings/export")

      assert response(conn, 200) =~ "=super-secret-value\n"
      assert [disposition] = get_resp_header(conn, "content-disposition")
      assert disposition =~ "attachment"
      assert get_resp_header(conn, "cache-control") == ["private, no-store"]
    end

    test "an admin who signed in long ago signs in again, back to the page", %{admin: admin} do
      long_ago = DateTime.add(DateTime.utc_now(:second), -1, :day)
      conn = build_conn() |> log_in_user(admin, token_authenticated_at: long_ago)

      conn = get(conn, ~p"/admin/settings/export")

      assert redirected_to(conn) == ~p"/users/log_in"
      assert get_session(conn, :user_return_to) == ~p"/admin/settings"
      refute response(conn, 302) =~ "super-secret-value"
    end

    test "nobody else does" do
      player = log_in_user(build_conn(), AccountsFixtures.user_fixture())

      for conn <- [build_conn(), player] do
        conn = get(conn, ~p"/admin/settings/export")

        assert conn.status == 302
        refute response(conn, 302) =~ "super-secret-value"
      end
    end
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

    # Every declared variable is derived from its own root, so the check needs
    # no list of known hosts — naming one would only assert that that host is
    # installed, and would miss any other plugin's settings entirely.
    for definition <- Settings.all() do
      assert String.starts_with?(definition.env, definition.root <> "_"),
             "#{definition.env} does not follow the #{definition.root}_ convention"
    end

    refute html =~ "inherited"
  end
end
