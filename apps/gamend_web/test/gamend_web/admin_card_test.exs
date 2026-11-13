defmodule GamendWeb.AdminCardTest do
  @moduledoc """
  What a host's `GamendWeb.AdminCard` modules add to `/admin`: their cards.
  """
  use GamendWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Repo
  alias GamendWeb.AdminCard

  defmodule CardsOnly do
    @behaviour GamendWeb.AdminCard

    @impl true
    def cards do
      [
        %{
          title: "Builds",
          path: "/admin/builds",
          icon: "hero-cube",
          color: "violet",
          value: 2,
          lines: ["Running or queued"]
        }
      ]
    end
  end

  defmodule Broken do
    @behaviour GamendWeb.AdminCard

    @impl true
    def cards, do: raise("no table yet")
  end

  setup do
    previous = Application.get_env(:gamend_web, :admin_cards)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:gamend_web, :admin_cards, previous),
        else: Application.delete_env(:gamend_web, :admin_cards)
    end)
  end

  defp load(modules) do
    Application.put_env(:gamend_web, :admin_cards, modules)
    AdminCard.load()
  end

  test "a module's cards come back as it wrote them" do
    assert [card] = load([CardsOnly])

    assert card.lines == ["Running or queued"]
  end

  test "a module that raises is logged and left out; the others still draw" do
    log =
      capture_log(fn ->
        assert [%{title: "Builds"}] = load([Broken, CardsOnly])
      end)

    assert log =~ "no table yet"
  end

  test "no modules, nothing added" do
    assert load([]) == []
  end

  defp dashboard(conn, modules) do
    Application.put_env(:gamend_web, :admin_cards, modules)

    # The dashboard caches its figures, a host's cards among them, for half a minute.
    Gamend.Cache.invalidate({:admin_dashboard_stats})
    on_exit(fn -> Gamend.Cache.invalidate({:admin_dashboard_stats}) end)

    admin = AccountsFixtures.user_fixture()
    {:ok, admin} = admin |> User.admin_changeset(%{"is_admin" => true}) |> Repo.update()

    {:ok, view, _html} = conn |> log_in_user(admin) |> live(~p"/admin")
    render_async(view, 30_000)
    view
  end

  test "a host's cards sit in a section of their own, after core's", %{conn: conn} do
    view = dashboard(conn, [CardsOnly])

    assert has_element?(view, "#admin-cards > section:last-child h2", "This site")
    assert has_element?(view, ~s|#admin-cards > section:last-child a[href="/admin/builds"]|)
  end

  test "with no host cards there is no section for them", %{conn: conn} do
    view = dashboard(conn, [])

    assert has_element?(view, "#admin-cards h2", "Players")
    refute has_element?(view, "#admin-cards h2", "This site")
  end
end
