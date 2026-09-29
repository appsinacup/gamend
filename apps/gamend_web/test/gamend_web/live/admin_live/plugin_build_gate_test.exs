defmodule GamendWeb.AdminLive.PluginBuildGateTest do
  @moduledoc """
  The admin Config page offers a "Build bundle" control. With `mix` on the
  PATH it shells out to it; an image built from the Dockerfile's `release`
  target ships no `mix`, and builds in-process with the Elixir compiler the
  release carries instead. The page says which it will do.
  """
  # Manipulates PATH, which is process-global.
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Repo

  defp admin_conn(conn) do
    user = AccountsFixtures.user_fixture()

    {:ok, user} =
      user
      |> User.admin_changeset(%{"is_admin" => true})
      |> Repo.update()

    log_in_user(conn, user)
  end

  # System.find_executable/1 resolves a bare name through PATH, so emptying it
  # stands in for a release image with no mix on it.
  defp without_mix_on_path(fun) do
    original = System.get_env("PATH")

    try do
      System.put_env("PATH", "")
      fun.()
    after
      System.put_env("PATH", original || "")
    end
  end

  test "without mix, says it builds in-process instead of refusing", %{conn: conn} do
    conn = admin_conn(conn)

    without_mix_on_path(fn ->
      {:ok, lv, _html} = live(conn, ~p"/admin/config")

      assert has_element?(lv, "#plugins-build-mode", "BUILD: in-process")
      assert has_element?(lv, "#plugins-build-in-process")
      refute render(lv) =~ "cannot build bundles"
    end)
  end

  test "with mix, says it builds with mix", %{conn: conn} do
    {:ok, lv, _html} = live(admin_conn(conn), ~p"/admin/config")

    assert has_element?(lv, "#plugins-build-mode", "BUILD: mix")
    refute has_element?(lv, "#plugins-build-in-process")
  end

  test "submitting the form without mix builds instead of refusing", %{conn: conn} do
    conn = admin_conn(conn)

    without_mix_on_path(fn ->
      {:ok, lv, _html} = live(conn, ~p"/admin/config")

      render =
        lv
        |> element("#plugins-build-form")
        |> render_submit(%{"plugin_build" => %{"name" => "anything"}})

      refute render =~ "cannot build plugin bundles"
    end)
  end
end
