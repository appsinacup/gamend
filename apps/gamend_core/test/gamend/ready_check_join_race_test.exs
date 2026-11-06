defmodule Gamend.ReadyCheckJoinRaceTest do
  @moduledoc """
  A player joining a lobby while its last pending member answers ready.

  The join put the newcomer on the lobby's open check only after the seat
  had committed, with no lock: the answer could pass the check in between,
  without the member who had just joined, and the late insert then put them,
  pending, into a check that had already passed. The newcomer now goes on the
  board in the seat's own transaction, under the check's lock.

  Each lobby must end one of two ways: the check passed before the join (the
  newcomer is not on it), or the join came first (the newcomer is on it,
  pending, and it has not passed). The answers are staggered across lobbies
  so some land inside the old window. Postgres only shows it; see
  `Gamend.RaceCase`.
  """

  use Gamend.RaceCase

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Lobbies
  alias Gamend.Lobbies.Lobby
  alias Gamend.ReadyChecks
  alias Gamend.ReadyChecks.Check

  @lobbies 15

  setup do
    rooms = unboxed(fn -> for _ <- 1..@lobbies, do: room() end)

    user_ids =
      Enum.flat_map(rooms, fn %{host: h, last: l, joiner: j} -> [h.id, l.id, j.id] end)

    lobby_ids = Enum.map(rooms, & &1.lobby.id)

    cleanup(fn ->
      Repo.update_all(from(u in User, where: u.id in ^user_ids), set: [lobby_id: nil])
      Repo.delete_all(from l in Lobby, where: l.id in ^lobby_ids)
      Repo.delete_all(from u in User, where: u.id in ^user_ids)
    end)

    %{rooms: rooms}
  end

  test "a check passes only over the members it had when it passed", %{rooms: rooms} do
    results =
      rooms
      |> Enum.with_index()
      |> Enum.flat_map(fn {%{lobby: lobby, last: last, joiner: joiner}, i} ->
        [
          fn -> Lobbies.join_lobby(joiner, lobby.id) end,
          fn ->
            Process.sleep(rem(i, 10))
            ReadyChecks.respond(last, true)
          end
        ]
      end)
      |> race()

    refute Enum.any?(results, &match?({:raised, _}, &1)), "a racer raised: #{inspect(results)}"

    for {%{lobby: lobby, joiner: joiner}, [joined, answered]} <-
          Enum.zip(rooms, Enum.chunk_every(results, 2)) do
      assert {:ok, _} = joined
      assert {:ok, _} = answered

      check =
        unboxed(fn ->
          Check
          |> where([c], c.lobby_id == ^lobby.id)
          |> Repo.one()
          |> Repo.preload(:participants)
        end)

      on_board = Enum.find(check.participants, &(&1.user_id == joiner.id))
      states = Enum.map(check.participants, & &1.state)

      case check.status do
        "passed" ->
          assert on_board == nil,
                 "a passed check holds a member who never answered: #{inspect(states)}"

        "pending" ->
          assert %{state: "pending"} = on_board
      end
    end
  end

  defp room do
    [host, last, joiner] = for _ <- 1..3, do: AccountsFixtures.unconfirmed_user_fixture()

    {:ok, lobby} =
      Lobbies.create_lobby(%{
        title: "ready-race-#{System.unique_integer([:positive])}",
        host_id: host.id,
        max_users: 4
      })

    {:ok, _} = Lobbies.join_lobby(last, lobby.id)
    {:ok, _} = ReadyChecks.open(lobby, [host.id, last.id], opened_by: host.id, timeout_ms: nil)

    %{lobby: lobby, host: host, last: last, joiner: joiner}
  end
end
