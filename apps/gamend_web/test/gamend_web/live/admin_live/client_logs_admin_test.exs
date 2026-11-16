defmodule GamendWeb.AdminLive.ClientLogsAdminTest do
  @moduledoc """
  The client half of `/admin/logs`: the session list, its filters, and the
  drill-down that links a client run back to the server's own history of it.
  """
  use GamendWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest

  alias Gamend.AccountsFixtures
  alias Gamend.ClientLogs
  alias Gamend.SettingsHelpers

  setup %{conn: conn} do
    SettingsHelpers.put(:gamend_core, ClientLogs, :enabled, true)
    on_exit(fn -> SettingsHelpers.delete(:gamend_core, ClientLogs, :enabled) end)

    user = AccountsFixtures.user_fixture()
    {:ok, admin} = Gamend.Accounts.update_user(user, %{is_admin: true})

    %{conn: log_in_user(conn, admin), admin: admin}
  end

  defp session_id, do: "sess-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

  defp ingest(sid, entries, session_extra \\ %{}) do
    payload = %{
      "session" =>
        Map.merge(
          %{"client_session_id" => sid, "platform" => "android", "app_version" => "1.4.2"},
          session_extra
        ),
      "entries" => entries
    }

    {result, _log} = with_log(fn -> ClientLogs.ingest(payload) end)
    result
  end

  defp entry(seq, opts \\ []) do
    %{
      "seq" => seq,
      "level" => Keyword.get(opts, :level, "info"),
      "category" => "game",
      "message" => Keyword.get(opts, :message, "entry #{seq}"),
      "lobby_id" => Keyword.get(opts, :lobby_id, "")
    }
  end

  test "lists a session with its counts", %{conn: conn} do
    sid = session_id()
    assert {:ok, _} = ingest(sid, [entry(1), entry(2, level: "error")])

    {:ok, view, _html} = live(conn, ~p"/admin/logs")
    html = view |> element("button", "Client sessions") |> render_click()

    assert html =~ String.slice(sid, 0, 12)
    assert html =~ "android"
    assert html =~ "1.4.2"
    # A session that errored is flagged, and says so.
    assert html =~ "flagged"
  end

  test "filters sessions to the ones that errored", %{conn: conn} do
    quiet = session_id()
    noisy = session_id()

    assert {:ok, _} = ingest(quiet, [entry(1)])
    assert {:ok, _} = ingest(noisy, [entry(1, level: "error")])

    {:ok, view, _html} = live(conn, ~p"/admin/logs")
    view |> element("button", "Client sessions") |> render_click()

    html =
      view
      |> form("#session-filters", %{"errors_only" => "true"})
      |> render_change()

    assert html =~ String.slice(noisy, 0, 12)
    refute html =~ String.slice(quiet, 0, 12)
  end

  test "a lobby id deep link opens the client tab filtered to that run", %{conn: conn} do
    sid = session_id()
    other = session_id()

    assert {:ok, _} = ingest(sid, [entry(1, lobby_id: "lob-deep")])
    assert {:ok, _} = ingest(other, [entry(1)])

    # This is the route the lobby-side history links to.
    {:ok, _view, html} = live(conn, ~p"/admin/logs?lobby_id=lob-deep")

    assert html =~ String.slice(sid, 0, 12)
    refute html =~ String.slice(other, 0, 12)
  end

  test "opening a session shows its lobbies as links back to server history", %{conn: conn} do
    sid = session_id()
    assert {:ok, _} = ingest(sid, [entry(1, lobby_id: "lob-77")])

    {:ok, view, _html} = live(conn, ~p"/admin/logs")
    view |> element("button", "Client sessions") |> render_click()

    html = view |> element("tr[phx-value-id='#{sid}']") |> render_click()

    assert html =~ sid
    assert html =~ "lob-77"
    assert html =~ "/admin/results?lobby_id=lob-77"
    # The page hands over the search that works in the host's log store.
    assert html =~ "session=#{sid}"
  end

  test "flagging a session from the page sticks", %{conn: conn} do
    sid = session_id()
    assert {:ok, _} = ingest(sid, [entry(1)])
    refute ClientLogs.get_session(sid).flagged

    {:ok, view, _html} = live(conn, ~p"/admin/logs")
    view |> element("button", "Client sessions") |> render_click()
    view |> element("tr[phx-value-id='#{sid}']") |> render_click()
    view |> element("button", "Flag") |> render_click()

    assert ClientLogs.get_session(sid).flagged
  end

  test "says so when collection is disabled instead of showing an empty list", %{conn: conn} do
    SettingsHelpers.delete(:gamend_core, ClientLogs, :enabled)

    {:ok, view, _html} = live(conn, ~p"/admin/logs")
    html = view |> element("button", "Client sessions") |> render_click()

    assert html =~ "Client log collection is off"
  end

  test "warns when the server's Logger level is discarding what clients send", %{conn: conn} do
    # Collection asks for info; this env runs Logger at :warning. That
    # combination silently drops everything below warn, and the page's job is
    # to say so rather than look quiet.
    assert Logger.compare_levels(Logger.level(), :info) == :gt

    {:ok, _view, html} = live(conn, ~p"/admin/logs")

    assert html =~ "Client entries are being discarded"
  end
end
