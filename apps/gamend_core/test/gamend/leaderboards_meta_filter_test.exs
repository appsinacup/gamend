defmodule Gamend.LeaderboardsMetaFilterTest do
  @moduledoc """
  `list_records/2`'s `:meta` option, which is how a board that mixes languages
  shows one of them.

  The SQL is adapter-specific (`->>` on Postgres, `json_extract` on SQLite),
  so this exercises whichever the suite runs on. Ranks must come out of the
  FILTERED set: "the Spanish board" means first among Spanish, not 57th.
  """
  use Gamend.DataCase, async: false

  alias Gamend.AccountsFixtures
  alias Gamend.Leaderboards

  setup do
    {:ok, board} =
      Leaderboards.create_leaderboard(%{
        slug: "test_a1_#{System.unique_integer([:positive])}",
        title: "A1",
        sort_order: :desc,
        operator: :best
      })

    submit = fn score, lang ->
      user = AccountsFixtures.user_fixture()
      {:ok, _} = Leaderboards.submit_score(board.id, user.id, score, %{"target_lang" => lang})
      user
    end

    # Interleaved on purpose: a filter that merely paginated the global order
    # would pass with the languages in blocks.
    submit.(100, "es_es")
    submit.(95, "fr")
    submit.(90, "es_es")
    submit.(85, "fr")
    submit.(80, "es_es")

    %{board: board}
  end

  test "it keeps only the language asked for", %{board: board} do
    records = Leaderboards.list_records(board.id, meta: %{"target_lang" => "es_es"})

    assert length(records) == 3
    assert Enum.map(records, & &1.score) == [100, 90, 80]
    assert Enum.all?(records, &(&1.metadata["target_lang"] == "es_es"))
  end

  test "ranks are within the filter, not the whole board", %{board: board} do
    records = Leaderboards.list_records(board.id, meta: %{"target_lang" => "fr"})

    assert Enum.map(records, &{&1.score, &1.rank}) == [{95, 1}, {85, 2}]
  end

  test "it paginates within the filter", %{board: board} do
    page =
      Leaderboards.list_records(board.id,
        meta: %{"target_lang" => "es_es"},
        page: 2,
        page_size: 2
      )

    assert Enum.map(page, &{&1.score, &1.rank}) == [{80, 3}]
  end

  test "count_records/2 counts the filtered set", %{board: board} do
    assert Leaderboards.count_records(board.id, meta: %{"target_lang" => "es_es"}) == 3
    assert Leaderboards.count_records(board.id, meta: %{"target_lang" => "fr"}) == 2
    assert Leaderboards.count_records(board.id) == 5
  end

  test "a language nobody has played answers nothing", %{board: board} do
    assert Leaderboards.list_records(board.id, meta: %{"target_lang" => "ja"}) == []
    assert Leaderboards.count_records(board.id, meta: %{"target_lang" => "ja"}) == 0
  end

  test "no filter is still the whole board, off the cached path", %{board: board} do
    for bad <- [nil, %{"target_lang" => ""}, "nonsense"] do
      assert length(Leaderboards.list_records(board.id, meta: bad)) == 5
    end
  end
end
