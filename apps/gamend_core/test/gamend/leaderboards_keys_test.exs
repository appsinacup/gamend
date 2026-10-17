defmodule Gamend.LeaderboardsKeysTest do
  @moduledoc """
  A board holding several rankings (`key`), read one key at a time or across
  keys, and a hidden board: ranked and readable, listed nowhere public.
  """
  use Gamend.DataCase, async: false

  alias Gamend.AccountsFixtures
  alias Gamend.Leaderboards

  defp board(attrs \\ %{}) do
    {:ok, board} =
      %{
        slug: "keys_#{System.unique_integer([:positive])}",
        title: "Keys",
        sort_order: :desc,
        operator: :best
      }
      |> Map.merge(attrs)
      |> Leaderboards.create_leaderboard()

    board
  end

  defp submit(board, user, score, game, lang) do
    {:ok, record} =
      Leaderboards.submit_score(
        board.id,
        user.id,
        score,
        %{"game" => game, "lang" => lang},
        key: "#{game}|#{lang}"
      )

    record
  end

  describe "keys" do
    test "a player has a best per key, each ranked on its own" do
      board = board()
      ana = AccountsFixtures.user_fixture()
      bo = AccountsFixtures.user_fixture()

      submit(board, ana, 10, "match", "es_es")
      submit(board, ana, 30, "match", "fr")
      submit(board, bo, 20, "match", "es_es")
      # `:best` per key: a lower score leaves the key's best alone.
      submit(board, ana, 5, "match", "es_es")

      es = Leaderboards.list_records(board.id, key: "match|es_es")
      assert Enum.map(es, &{&1.user_id, &1.score, &1.rank}) == [{bo.id, 20, 1}, {ana.id, 10, 2}]

      assert [%{score: 30, rank: 1}] = Leaderboards.list_records(board.id, key: "match|fr")
      assert Leaderboards.count_records(board.id, key: "match|es_es") == 2

      assert {:ok, %{score: 10, rank: 2}} =
               Leaderboards.get_user_record(board.id, ana.id, key: "match|es_es")

      assert {:error, :not_found} = Leaderboards.get_user_record(board.id, ana.id)

      around = Leaderboards.list_records_around_user(board.id, ana.id, key: "match|es_es")
      assert Enum.map(around, & &1.score) == [20, 10]
    end

    test "the default key is the board as it always was" do
      board = board()
      user = AccountsFixtures.user_fixture()
      {:ok, record} = Leaderboards.submit_score(board.id, user.id, 7)

      assert record.key == ""
      assert [%{score: 7, rank: 1}] = Leaderboards.list_records(board.id)
      assert {:ok, %{score: 7}} = Leaderboards.get_user_record(board.id, user.id)
    end

    test "across keys: every row, or each player's best once" do
      board = board()
      ana = AccountsFixtures.user_fixture()
      bo = AccountsFixtures.user_fixture()

      submit(board, ana, 10, "match", "es_es")
      submit(board, ana, 30, "match", "fr")
      submit(board, bo, 20, "match", "es_es")
      submit(board, bo, 50, "hangman", "es_es")

      assert Leaderboards.count_records(board.id, key: :all) == 4

      best =
        Leaderboards.list_records(board.id,
          key: :all,
          meta: %{"game" => "match"},
          best_per_user: true
        )

      assert Enum.map(best, &{&1.user_id, &1.score, &1.rank}) == [{ana.id, 30, 1}, {bo.id, 20, 2}]

      assert Leaderboards.count_records(board.id,
               key: :all,
               meta: %{"game" => "match"},
               best_per_user: true
             ) == 2

      # Several fields at once.
      assert [%{score: 50}] =
               Leaderboards.list_records(board.id,
                 key: :all,
                 meta: %{"game" => "hangman", "lang" => "es_es"}
               )
    end

    test "label records take a key too" do
      board = board()
      {:ok, _} = Leaderboards.submit_label_score(board.id, "Spanish", 3, %{}, key: "a")
      {:ok, _} = Leaderboards.submit_label_score(board.id, "Spanish", 9, %{}, key: "b")

      assert %{score: 3} = Leaderboards.get_label_record(board.id, "Spanish", "a")
      assert %{score: 9} = Leaderboards.get_label_record(board.id, "Spanish", "b")
      assert Leaderboards.get_label_record(board.id, "Spanish") == nil
    end
  end

  describe "hidden boards" do
    test "ranked and readable, but in no public listing" do
      hidden = board(%{hidden: true})
      shown = board()
      user = AccountsFixtures.user_fixture()
      {:ok, _} = Leaderboards.submit_score(hidden.id, user.id, 4)

      listed = Enum.map(Leaderboards.list_leaderboards(page_size: 100), & &1.id)
      assert shown.id in listed
      refute hidden.id in listed

      all =
        Enum.map(Leaderboards.list_leaderboards(page_size: 100, include_hidden: true), & &1.id)

      assert hidden.id in all

      groups = Enum.map(Leaderboards.list_leaderboard_groups(page_size: 100), & &1.slug)
      refute hidden.slug in groups
      assert shown.slug in groups

      assert Leaderboards.count_leaderboard_groups(include_hidden: true) ==
               Leaderboards.count_leaderboard_groups() + 1

      assert Leaderboards.get_leaderboard(hidden.slug).id == hidden.id
      assert [%{score: 4}] = Leaderboards.list_records(hidden.id)
    end
  end
end
