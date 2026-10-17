defmodule Gamend.Repo.VanishedRowTest do
  @moduledoc """
  The helpers a context uses when the row it read may be deleted before it
  writes: `Gamend.Repo.rescue_stale/2` and `Gamend.Repo.lock_rows/2`.
  """
  use Gamend.DataCase

  import Ecto.Query, only: [from: 2]

  alias Gamend.Lobbies
  alias Gamend.Lobbies.Lobby
  alias Gamend.Repo
  alias Gamend.Repo.AdvisoryLock

  defp rename(lobby, title), do: lobby |> Ecto.Changeset.change(title: title) |> Repo.update()

  test "writing a row deleted since it was read answers the given reason" do
    {:ok, lobby} = Lobbies.create_lobby(%{title: "gone", hostless: true})
    Repo.delete!(lobby)

    assert Repo.rescue_stale(:gone, fn -> rename(lobby, "late") end) == {:error, :gone}
    assert Repo.rescue_stale(:gone, fn -> Repo.delete(lobby) end) == {:error, :gone}
  end

  test "a live row's write passes through, and any other raise still raises" do
    {:ok, lobby} = Lobbies.create_lobby(%{title: "here", hostless: true})

    assert {:ok, %Lobby{title: "renamed"}} =
             Repo.rescue_stale(:gone, fn -> rename(lobby, "renamed") end)

    assert_raise RuntimeError, fn -> Repo.rescue_stale(:gone, fn -> raise "boom" end) end
  end

  test "a locked read runs on either adapter" do
    {:ok, lobby} = Lobbies.create_lobby(%{title: "locked", hostless: true})
    query = from(l in Lobby, where: l.id == ^lobby.id)

    for mode <- [:update, :share] do
      assert {:ok, [%Lobby{id: id}]} =
               Repo.transaction(fn -> Repo.all(Repo.lock_rows(query, mode)) end)

      assert id == lobby.id
    end
  end

  test "rows are locked on Postgres and the query is left alone on SQLite" do
    query = from(l in Lobby, where: l.hostless)

    if AdvisoryLock.postgres?() do
      assert inspect(Repo.lock_rows(query, :update)) =~ "FOR UPDATE"
      assert inspect(Repo.lock_rows(query, :share)) =~ "FOR SHARE"
    else
      assert Repo.lock_rows(query, :update) == query
      assert Repo.lock_rows(query, :share) == query
    end
  end
end
