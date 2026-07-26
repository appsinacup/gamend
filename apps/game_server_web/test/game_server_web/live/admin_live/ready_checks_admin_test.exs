defmodule GameServerWeb.AdminLive.ReadyChecksAdminTest do
  @moduledoc """
  The admin surfaces for ready checks: the outcome panel on the matchmaking
  page, and the per-member state in the lobby viewer's members modal — which
  only renders after a click, so the page-level render test cannot reach it.
  """
  use GameServerWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias GameServer.Accounts
  alias GameServer.AccountsFixtures
  alias GameServer.Lobbies
  alias GameServer.ReadyChecks

  setup %{conn: conn} do
    # First user in an empty DB may be auto-promoted; create a decoy first.
    _decoy = AccountsFixtures.user_fixture()
    user = AccountsFixtures.user_fixture()
    {:ok, admin} = Accounts.update_user(user, %{is_admin: true})

    host = AccountsFixtures.user_fixture()
    member = AccountsFixtures.user_fixture()

    {:ok, lobby} = Lobbies.create_lobby(%{title: "admin-ready-lobby", host_id: host.id})
    {:ok, _} = Lobbies.join_lobby(member, lobby.id)

    %{conn: log_in_user(conn, admin), host: host, member: member, lobby: lobby}
  end

  describe "/admin/matchmaking" do
    test "lists open checks with their ready counts", ctx do
      {:ok, _} = ReadyChecks.open(ctx.lobby, [ctx.host.id, ctx.member.id], opened_by: ctx.host.id)

      {:ok, _view, html} = live(ctx.conn, ~p"/admin/matchmaking")

      assert html =~ "Ready checks"
      assert html =~ "pending"
      # The host answered by opening it.
      assert html =~ "1/2"
    end

    test "shows why a check failed, not just that it did", ctx do
      {:ok, check} = ReadyChecks.open(ctx.lobby, [ctx.host.id, ctx.member.id])
      {:ok, _} = ReadyChecks.cancel(check)

      {:ok, _view, html} = live(ctx.conn, ~p"/admin/matchmaking")

      assert html =~ "cancelled"
    end

    test "an admin can force-cancel a pending check", ctx do
      {:ok, check} = ReadyChecks.open(ctx.lobby, [ctx.host.id, ctx.member.id])

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/matchmaking")

      view
      |> element("button[phx-click='cancel_ready_check'][phx-value-id='#{check.id}']")
      |> render_click()

      assert ReadyChecks.get_check(check.id).status == "cancelled"
      assert render(view) =~ "Ready check cancelled"
    end
  end

  describe "/admin/lobbies members modal" do
    test "shows each member's ready state and the check summary", ctx do
      {:ok, _} = ReadyChecks.open(ctx.lobby, [ctx.host.id, ctx.member.id], opened_by: ctx.host.id)

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/lobbies")

      html =
        view
        |> element("button[phx-click='view_members'][phx-value-id='#{ctx.lobby.id}']")
        |> render_click()

      assert html =~ "Ready check"
      assert html =~ "1/2"
      assert html =~ "ready"
      assert html =~ "pending"
    end

    test "a lobby with no open check shows a dash rather than implying un-ready", ctx do
      {:ok, view, _html} = live(ctx.conn, ~p"/admin/lobbies")

      html =
        view
        |> element("button[phx-click='view_members'][phx-value-id='#{ctx.lobby.id}']")
        |> render_click()

      refute html =~ "Ready check "
      assert html =~ "—"
    end

    test "an admin can cancel the check from the lobby viewer", ctx do
      {:ok, check} = ReadyChecks.open(ctx.lobby, [ctx.host.id, ctx.member.id])

      {:ok, view, _html} = live(ctx.conn, ~p"/admin/lobbies")

      view
      |> element("button[phx-click='view_members'][phx-value-id='#{ctx.lobby.id}']")
      |> render_click()

      view
      |> element("button[phx-click='cancel_ready_check'][phx-value-id='#{check.id}']")
      |> render_click()

      assert ReadyChecks.get_check(check.id).status == "cancelled"
    end
  end

  describe "/admin dashboard" do
    test "the matchmaking card carries the 24h ready-check outcomes", ctx do
      {:ok, check} = ReadyChecks.open(ctx.lobby, [ctx.host.id, ctx.member.id])
      {:ok, _} = ReadyChecks.cancel(check)

      {:ok, _view, html} = live(ctx.conn, ~p"/admin")

      assert html =~ "Ready checks 24h"
    end
  end
end
