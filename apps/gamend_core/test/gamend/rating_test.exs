defmodule Gamend.RatingTest do
  use ExUnit.Case, async: true

  alias Gamend.Rating

  defp rated(rating, deviation \\ 200.0) do
    Rating.new(rating: rating, deviation: deviation)
  end

  describe "new/1" do
    test "an unrated player" do
      assert %Rating{rating: 1500.0, deviation: 350.0, volatility: 0.06} = Rating.new()
    end

    test "a misspelt field raises where it is written" do
      assert_raise ArgumentError, fn -> Rating.new(ratng: 1200) end
    end
  end

  describe "expected/2" do
    test "equal ratings are a coin toss" do
      assert_in_delta Rating.expected(1500, 1500), 0.5, 1.0e-9
    end

    test "200 points ahead wins about three times in four" do
      assert_in_delta Rating.expected(1700, 1500), 0.7597, 1.0e-3
    end

    test "takes ratings as well as numbers" do
      assert_in_delta Rating.expected(rated(1700.0), rated(1500.0)), 0.7597, 1.0e-3
    end
  end

  describe "elo/4" do
    test "an even game moves half of k each way" do
      assert {1516.0, 1484.0} = Rating.elo(1500, 1500, 1.0)
    end

    test "a draw between equals moves nothing" do
      assert {1500.0, 1500.0} = Rating.elo(1500, 1500, 0.5)
    end

    test "an upset pays more than an expected win" do
      {upset, _} = Rating.elo(1300, 1700, 1.0)
      {expected, _} = Rating.elo(1700, 1300, 1.0)
      assert upset - 1300 > expected - 1700
    end

    test "what one gains the other loses, and k scales it" do
      {a, b} = Rating.elo(1612, 1388, 0.0, k: 16)
      assert_in_delta a + b, 3000.0, 1.0e-9
      assert_in_delta a - 1612, -16 * Rating.expected(1612, 1388), 1.0e-9
    end
  end

  describe "glicko2/3" do
    # The worked example in Glickman's "Example of the Glicko-2 system".
    test "matches the published example" do
      player = Rating.new(rating: 1500, deviation: 200, volatility: 0.06)

      games = [
        {rated(1400.0, 30.0), 1.0},
        {rated(1550.0, 100.0), 0.0},
        {rated(1700.0, 300.0), 0.0}
      ]

      after_period = Rating.glicko2(player, games, tau: 0.5)

      assert_in_delta after_period.rating, 1464.06, 0.01
      assert_in_delta after_period.deviation, 151.52, 0.01
      assert_in_delta after_period.volatility, 0.05999, 0.0001
    end

    test "an idle period only grows the deviation" do
      player = rated(1650.0, 100.0)
      idle = Rating.glicko2(player, [])

      assert idle.rating == player.rating
      assert idle.deviation > player.deviation
    end

    test "the deviation never grows past an unrated player's" do
      assert Rating.glicko2(Rating.new(), []).deviation == 350.0
    end

    test "a gap too wide to compute does not raise" do
      winner = Rating.glicko2(rated(90_000.0), [{rated(1.0), 1.0}])
      assert winner.rating >= 90_000.0
    end
  end

  describe "settle/3" do
    test "a duel: the winner rises, the loser falls, both grow surer" do
      [[winner], [loser]] = Rating.settle([[Rating.new()], [Rating.new()]], [1, 2])

      assert winner.rating > 1500.0
      assert loser.rating < 1500.0
      assert winner.deviation < 350.0
      assert loser.deviation < 350.0
    end

    test "equal places are a draw" do
      [[a], [b]] = Rating.settle([[Rating.new()], [Rating.new()]], [1, 1])

      assert_in_delta a.rating, 1500.0, 1.0e-6
      assert_in_delta b.rating, 1500.0, 1.0e-6
    end

    test "teams keep their shape and order" do
      teams = [[rated(1500.0), rated(1600.0)], [rated(1550.0), rated(1450.0)]]

      assert [[a, b], [c, d]] = Rating.settle(teams, [2, 1])

      assert a.rating < 1500.0
      assert b.rating < 1600.0
      assert c.rating > 1550.0
      assert d.rating > 1450.0
    end

    test "a free-for-all ranks by place" do
      players = for _ <- 1..3, do: [Rating.new()]

      [[first], [second], [third]] = Rating.settle(players, [1, 2, 3])

      assert first.rating > second.rating
      assert second.rating > third.rating
      assert_in_delta second.rating, 1500.0, 1.0e-6
    end

    test "elo changes only the rating, split across opponents" do
      players = for _ <- 1..3, do: [Rating.new()]

      [[first], [_], [third]] = Rating.settle(players, [1, 2, 3], algorithm: :elo, k: 32)

      assert_in_delta first.rating, 1516.0, 1.0e-6
      assert_in_delta third.rating, 1484.0, 1.0e-6
      assert first.deviation == 350.0
    end

    test "every team needs a place" do
      assert_raise FunctionClauseError, fn -> Rating.settle([[Rating.new()]], [1, 2]) end
    end
  end

  describe "band/2" do
    test "starts narrow, widens with the wait, stops at the max" do
      assert Rating.band(0) == 100
      assert Rating.band(5_000) == 200.0
      assert Rating.band(600_000) == 1_000
    end

    test "takes its shape from options" do
      assert Rating.band(1_000, base: 10, per_second: 5, max: 12) == 12
    end
  end

  describe "dump/1 and load/1" do
    test "a rating survives JSON" do
      rating = rated(1612.5, 88.25)

      assert rating |> Rating.dump() |> Jason.encode!() |> Jason.decode!() |> Rating.load() ==
               rating
    end

    test "nothing stored is unrated" do
      assert Rating.load(nil) == Rating.new()
      assert Rating.load(%{}) == Rating.new()
    end

    test "a field that is not a number is left at its default" do
      loaded = Rating.load(%{Atom.to_string(:rating) => "high", Atom.to_string(:deviation) => 90})

      assert loaded.rating == 1500.0
      assert loaded.deviation == 90.0
    end
  end
end
