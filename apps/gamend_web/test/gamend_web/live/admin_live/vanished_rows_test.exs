defmodule GamendWeb.AdminLive.VanishedRowsTest do
  @moduledoc """
  A console row can name a record deleted after the page drew it (by another
  admin, its player or a sweep). Acting on it answers with a flash and leaves
  the page up, where a `get_*!` crashed it into a remount.
  """
  use GamendWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Repo
  alias GamendWeb.AdminLive.Shared

  @pages [
    {"/admin/groups", ~w(edit_group view_members)},
    {"/admin/leaderboards",
     ~w(edit_leaderboard new_season_from delete_leaderboard view_records edit_record delete_record)},
    {"/admin/parties", ~w(edit_party view_members)},
    {"/admin/sessions", ~w(delete_session)},
    {"/admin/users", ~w(edit_user cancel_user_deletion unlock_login delete_user)},
    {"/admin/lobbies", ~w(view_members edit_lobby delete_lobby)}
  ]

  setup %{conn: conn} do
    {:ok, admin} =
      AccountsFixtures.user_fixture()
      |> User.admin_changeset(%{"is_admin" => true})
      |> Repo.update()

    %{conn: log_in_user(conn, admin)}
  end

  # One mount a page: the flash is cleared after each event, so every event
  # has to put it there again.
  for {path, events} <- @pages do
    test "#{path}: #{Enum.join(events, ", ")} on a deleted row flash that it is gone", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, unquote(path))

      for event <- unquote(events) do
        html = render_hook(view, event, %{"id" => Ecto.UUID.generate()})
        assert html =~ Shared.gone_message(), "#{event} did not say the row is gone"

        render_hook(view, "lv:clear-flash", %{"key" => "error"})
        refute render(view) =~ Shared.gone_message()
      end
    end
  end

  test "kicking a player who is gone from the live lobbies page flashes and stays up", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, ~p"/admin/lobbies/live")

    html =
      render_hook(view, "kick", %{
        "lobby_id" => Ecto.UUID.generate(),
        "target_id" => Ecto.UUID.generate()
      })

    assert html =~ "Failed"
    assert Process.alive?(view.pid)
  end

  for path <- ~w(/admin/lobbies /admin/users /admin/sessions /admin/leaderboards) do
    test "#{path} bulk delete counts a row already gone as deleted", %{conn: conn} do
      {:ok, view, _html} = live(conn, unquote(path))

      render_hook(view, "toggle_select", %{"id" => Ecto.UUID.generate()})
      html = render_hook(view, "bulk_delete", %{})

      refute html =~ "failed"
    end
  end
end
