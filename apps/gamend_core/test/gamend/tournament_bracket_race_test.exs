defmodule Gamend.TournamentBracketRaceTest do
  @moduledoc """
  The two semi-finals of a bracket resolving at the same instant.

  Each resolves under its own match's lock and writes its winner into the
  final, then checks the final for a bye. A resolve that decided from the
  final as it read it, before the other semi's commit, saw the other side
  empty and that semi resolved, and gave its own winner the final as a bye,
  eliminating a winner who was already seated.

  Postgres only shows it; see `Gamend.RaceCase`.
  """

  use Gamend.RaceCase

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Tournaments
  alias Gamend.Tournaments.Tournament

  @brackets 20

  setup do
    tournaments = unboxed(fn -> for _ <- 1..@brackets, do: drawn_bracket_of_four() end)
    user_ids = Enum.flat_map(tournaments, fn {_tournament, user_ids} -> user_ids end)
    tournament_ids = Enum.map(tournaments, fn {tournament, _} -> tournament.id end)

    cleanup(fn ->
      Repo.delete_all(from t in Tournament, where: t.id in ^tournament_ids)
      Repo.delete_all(from u in User, where: u.id in ^user_ids)
    end)

    %{tournaments: Enum.map(tournaments, &elem(&1, 0))}
  end

  test "both semi-final winners meet in the final", %{tournaments: tournaments} do
    semis = Enum.flat_map(tournaments, &matches_in_round(&1, 1))

    results =
      semis
      |> Enum.map(fn semi -> fn -> Tournaments.resolve_match(semi.id, semi.a_entry_id) end end)
      |> race()

    assert Enum.all?(results, &match?({:ok, _}, &1)), "a resolve failed: #{inspect(results)}"

    for tournament <- tournaments do
      [final] = matches_in_round(tournament, 2)

      assert final.a_entry_id && final.b_entry_id,
             "a semi-final winner is missing from the final: #{inspect(final)}"

      assert is_nil(final.resolved_at), "the final was settled as a bye: #{inspect(final)}"
    end
  end

  defp matches_in_round(tournament, round) do
    unboxed(fn -> Tournaments.list_matches(tournament.id) end)
    |> Enum.filter(&(&1.round == round))
  end

  defp drawn_bracket_of_four do
    {:ok, tournament} =
      Tournaments.create_tournament(%{
        slug: "race-cup-#{System.unique_integer([:positive])}",
        title: "Race Cup",
        starts_at: DateTime.add(DateTime.utc_now(:second), 3600),
        round_window_sec: 600,
        bracket_size: 4
      })

    users = for _ <- 1..4, do: AccountsFixtures.unconfirmed_user_fixture()
    Enum.each(users, fn user -> {:ok, _} = Tournaments.join_tournament(user, tournament) end)

    {:ok, tournament} =
      Tournaments.update_tournament(tournament, %{starts_at: DateTime.utc_now(:second)})

    {Tournaments.advance_lifecycle(tournament), Enum.map(users, & &1.id)}
  end
end
