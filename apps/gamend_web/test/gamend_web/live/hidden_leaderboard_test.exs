defmodule GamendWeb.HiddenLeaderboardTest do
  @moduledoc """
  A hidden board (`Leaderboard.hidden`) is shown by the host's own pages: the
  public leaderboards page neither lists it nor opens it.
  """
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gamend.Leaderboards

  test "the leaderboards page leaves a hidden board out and will not open it", %{conn: conn} do
    {:ok, board} =
      Leaderboards.create_leaderboard(%{
        slug: "hidden_#{System.unique_integer([:positive])}",
        title: "Hidden board",
        hidden: true
      })

    {:ok, _view, html} = live(conn, ~p"/leaderboards")
    refute html =~ board.slug

    assert {:error, {:live_redirect, %{to: "/leaderboards"}}} =
             live(conn, ~p"/leaderboards/#{board.slug}")

    assert {:error, {:live_redirect, %{to: "/leaderboards"}}} =
             live(conn, ~p"/leaderboards/#{board.slug}/#{board.id}")
  end
end
