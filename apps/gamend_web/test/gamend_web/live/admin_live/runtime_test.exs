defmodule GamendWeb.AdminLive.RuntimeTest do
  @moduledoc """
  The runtime page's chrome. A `:for` comprehension whose pattern does not
  match silently yields nothing rather than raising, so the tab bar can vanish
  from a green compile — these assert it is actually rendered.
  """
  use GamendWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Repo

  setup %{conn: conn} do
    admin =
      AccountsFixtures.user_fixture()
      |> User.admin_changeset(%{"is_admin" => true})
      |> Repo.update!()

    %{conn: log_in_user(conn, admin)}
  end

  @tabs ~w(hooks proto channels events notifications model jobs locks migrations)

  test "every tab is linked from the tab bar", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/admin/runtime")

    for tab <- @tabs do
      assert html =~ "/admin/runtime?tab=#{tab}", "tab #{tab} missing from the tab bar"
    end
  end

  test "each tab renders its own table", %{conn: conn} do
    for tab <- @tabs do
      {:ok, _view, html} = live(conn, ~p"/admin/runtime?tab=#{tab}")
      assert html =~ "Runtime introspection"
      assert html =~ "<table", "tab #{tab} rendered no table"
    end
  end

  test "faceted tabs render a filter, unfaceted ones do not", %{conn: conn} do
    for tab <- ~w(hooks proto events notifications model migrations) do
      {:ok, _view, html} = live(conn, ~p"/admin/runtime?tab=#{tab}")
      assert html =~ ~s(id="facet-#{tab}"), "tab #{tab} should have a facet filter"
    end

    for tab <- ~w(channels jobs locks) do
      {:ok, _view, html} = live(conn, ~p"/admin/runtime?tab=#{tab}")
      refute html =~ ~s(id="facet-#{tab}"), "tab #{tab} should not have a facet filter"
    end
  end

  test "the facet filter partitions the rows", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/runtime?tab=hooks")

    # The search placeholder carries the row count, so this reads the filter's
    # effect without depending on which hooks land on page one. Asserting a
    # partition rather than "fewer rows" holds in test too, where no plugins
    # are loaded and every hook is therefore unimplemented.
    count = fn html ->
      Regex.run(~r/Search (\d+) entries/, html) |> Enum.at(1) |> String.to_integer()
    end

    change = fn value ->
      view |> element("#facet-hooks") |> render_change(%{"value" => value}) |> count.()
    end

    all = count.(render(view))
    assert change.("implemented") + change.("not implemented") == all
    assert change.("all") == all
  end

  test "an unknown tab falls back to hooks rather than crashing", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/admin/runtime?tab=nonsense")
    assert html =~ "Hook"
  end
end
