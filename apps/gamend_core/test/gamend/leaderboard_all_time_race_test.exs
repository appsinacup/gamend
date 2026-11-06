defmodule Gamend.LeaderboardAllTimeRaceTest do
  @moduledoc """
  A season row edited while its owner's all-time row is being kept.

  An edited or deleted season row reads its owner's all-time row again from
  the seasons. That was a read, a delete and an insert with no transaction
  or lock: two edits at once both deleted and both inserted, and the second
  raised on the unique index; a submit that raised the all-time row between
  the read and the write was deleted, and the older best put back. It now
  runs under the slug's all-time lock with the owner's row locked first.

  Each owner's all-time row must end as their best season row, and nothing
  may raise. Postgres only shows it; see `Gamend.RaceCase`.
  """

  use Gamend.RaceCase

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Leaderboards
  alias Gamend.Leaderboards.Leaderboard
  alias Gamend.Leaderboards.Record

  @owners 15

  setup do
    slug = "all-time-race-#{System.unique_integer([:positive])}"

    {season, records} =
      unboxed(fn ->
        {:ok, season} =
          Leaderboards.create_leaderboard(%{
            slug: slug,
            title: "All-time race",
            operator: :best,
            sort_order: :desc,
            starts_at: DateTime.add(DateTime.utc_now(:second), -3600)
          })

        records =
          for _ <- 1..@owners do
            user = AccountsFixtures.unconfirmed_user_fixture()
            {:ok, record} = Leaderboards.submit_score(season.id, user.id, 100)
            record
          end

        # The all-time board is made the first time it is read.
        _ = Leaderboards.list_records(season.id, all_time: true)
        {season, records}
      end)

    user_ids = Enum.map(records, & &1.user_id)

    cleanup(fn ->
      Repo.delete_all(from l in Leaderboard, where: l.slug in ^[slug, slug <> "__all_time"])
      Repo.delete_all(from u in User, where: u.id in ^user_ids)
    end)

    %{season: season, records: records, slug: slug}
  end

  test "two edits of one season row keep one all-time row, and neither raises", ctx do
    results =
      ctx.records
      |> Enum.flat_map(fn record ->
        [
          fn -> Leaderboards.update_record(record, %{score: 60}) end,
          fn -> Leaderboards.update_record(record, %{score: 60}) end
        ]
      end)
      |> race()

    refute Enum.any?(results, &match?({:raised, _}, &1)), "an edit raised: #{inspect(results)}"
    assert_all_time_follows_the_season(ctx)
  end

  test "an edit racing a submit leaves the all-time row at the season's best", ctx do
    results =
      ctx.records
      |> Enum.flat_map(fn record ->
        [
          fn -> Leaderboards.update_record(record, %{score: 40}) end,
          fn -> Leaderboards.submit_score(ctx.season.id, record.user_id, 150) end
        ]
      end)
      |> race()

    refute Enum.any?(results, &match?({:raised, _}, &1)), "a write raised: #{inspect(results)}"
    assert_all_time_follows_the_season(ctx)
  end

  defp assert_all_time_follows_the_season(ctx) do
    rows =
      unboxed(fn ->
        from(r in Record,
          join: l in Leaderboard,
          on: l.id == r.leaderboard_id,
          where: l.slug in ^[ctx.slug, ctx.slug <> "__all_time"],
          select: {l.slug, r.user_id, r.score}
        )
        |> Repo.all()
      end)

    season = for {slug, user_id, score} <- rows, slug == ctx.slug, into: %{}, do: {user_id, score}

    all_time =
      rows
      |> Enum.filter(fn {slug, _, _} -> slug != ctx.slug end)
      |> Enum.group_by(fn {_, user_id, _} -> user_id end, fn {_, _, score} -> score end)

    for record <- ctx.records do
      assert Map.get(all_time, record.user_id) == [season[record.user_id]],
             "all time #{inspect(all_time[record.user_id])}, season #{season[record.user_id]}"
    end
  end
end
