defmodule Gamend.Analytics.TimeSpent do
  @moduledoc """
  How long accounts spend in the game, worked out from what is already
  stored: nothing is collected for it.

  Every row an account leaves is a moment it was there: its analytics
  events (`analytics_events`, an account's only), the start of each play
  (`results.started_at`) and each thing that happened in one
  (`result_events`, `started_at + elapsed_ms`). Sorted per account, the
  time from one moment to the next is time spent when it is at most
  `idle_seconds` (default 5 minutes); a longer gap is the account away, and
  counts nothing. A declared span (`spans`: a test started and finished,
  with nothing stored in between) counts up to `span_seconds` (default 2
  hours) from its start to its end.

  Each gap is filed under where the account was at its start: the AREA of
  the earlier moment, and its DETAIL where there is one:

    * a play's moment: the area `results` (default `"plays"`), the detail
      the play's `kind` (a game);
    * an event named in `dim`'s list: the value of that field (`"section"`
      of a page view), passed through `areas`;
    * any other event: its catalogue group (`Gamend.Analytics.Catalog`),
      passed through `areas`.

  So the numbers are a floor: the time after an account's last moment of a
  visit (reading the last page, the end of a round) is not counted, and a
  visitor with no account leaves no rows, so is in none of it. Days are
  UTC days, as DAU is. The host says how its rows read in its catalogue's
  `overview/0`, under `time` (`Catalog.overview/0`).
  """

  import Ecto.Query

  alias Gamend.Analytics.Catalog
  alias Gamend.Analytics.Event
  alias Gamend.Analytics.Segment
  alias Gamend.Repo
  alias Gamend.Repo.AdvisoryLock
  alias Gamend.Results.Event, as: ResultEvent
  alias Gamend.Results.Result

  # A play resumed later than this after its start is read from where it
  # was started only: the window's plays are found by their start.
  @play_lookback_days 7

  # Minutes per account-day, the distribution's steps: `{label, up to}`.
  @buckets [
    {"under 1 min", 60},
    {"1-5 min", 300},
    {"5-15 min", 900},
    {"15-30 min", 1_800},
    {"30-60 min", 3_600},
    {"1-2 h", 7_200},
    {"2 h or more", nil}
  ]

  @typedoc "One account on one UTC day: seconds in all and per `{area, detail}`."
  @type account_day :: %{
          day: Date.t(),
          user_id: String.t(),
          seconds: float(),
          by: %{{String.t(), String.t() | nil} => float()}
        }

  @doc """
  Every account with time on a UTC day in `from..to` (inclusive), one
  `t:account_day/0` each. Options: `segment:` (`Gamend.Analytics.segments/0`).
  """
  @spec account_days(Date.t(), Date.t(), keyword()) :: [account_day()]
  def account_days(%Date{} = from, %Date{} = to, opts \\ []) do
    config = Catalog.overview().time
    segment = Keyword.get(opts, :segment, :all)
    start = DateTime.new!(from, ~T[00:00:00], "Etc/UTC")
    stop = DateTime.new!(Date.add(to, 1), ~T[00:00:00], "Etc/UTC")
    # A span's start may fall before the window; its end inside it counts.
    reach = DateTime.add(start, -max(config.idle_seconds, config.span_seconds), :second)

    marks = marks(reach, stop, config, segment)
    {marks_sql, params} = Repo.to_sql(:all, marks)

    sql = """
    WITH m AS (#{marks_sql}),
    g AS (
      SELECT user_id, t, src, name,
        LAG(t) OVER w AS pt, LAG(src) OVER w AS psrc,
        LAG(name) OVER w AS pname, LAG(dim) OVER w AS pdim
      FROM m
      WINDOW w AS (PARTITION BY user_id ORDER BY t)
    )
    SELECT #{day_number("t")} AS day, user_id, psrc, pname, pdim, SUM(t - pt) AS seconds
    FROM g
    WHERE pt IS NOT NULL
      AND t >= #{DateTime.to_unix(start)} AND t < #{DateTime.to_unix(stop)}
      AND (t - pt <= #{config.idle_seconds}#{span_condition(config)})
    GROUP BY 1, user_id, psrc, pname, pdim
    """

    Repo.query!(sql, params, timeout: :infinity).rows
    |> Enum.group_by(fn [day, user_id | _] -> {day, user_id} end)
    |> Enum.map(fn {{day, user_id}, rows} ->
      by =
        Enum.reduce(rows, %{}, fn [_day, _user, src, name, dim, seconds], acc ->
          Map.update(
            acc,
            place(src, name, dim, config),
            to_float(seconds),
            &(&1 + to_float(seconds))
          )
        end)

      %{
        day: Date.add(~D[1970-01-01], to_int(day)),
        user_id: user_id,
        seconds: by |> Map.values() |> Enum.sum(),
        by: by
      }
    end)
    |> Enum.sort_by(&{&1.day, &1.user_id}, &<=/2)
  end

  @doc """
  The time spent over the last `days` UTC days ending on `today` (today
  partial), for the admin Analytics Time tab:

    * `seconds`, `people` (accounts with any time), `account_days`,
      `per_day_avg` / `per_day_median` (seconds per account on a day it
      came), `per_person` (seconds per account over the window);
    * `series`: per day `%{day, people, seconds, avg, median}`;
    * `buckets`: account-days by how long, `%{label, count}`;
    * `areas`: `%{id, label, people, account_days, seconds, avg, share}`,
      `avg` per account-day that used the area, most time first;
    * `details`: the same per `{area, detail}` where there is a detail.

  Options: `segment:`.
  """
  @spec report(pos_integer(), Date.t(), keyword()) :: map()
  def report(days, %Date{} = today \\ Date.utc_today(), opts \\ [])
      when is_integer(days) and days > 0 do
    from = Date.add(today, -(days - 1))
    rows = account_days(from, today, opts)
    config = Catalog.overview().time
    totals = Enum.map(rows, & &1.seconds)
    total = Enum.sum(totals)
    people = rows |> Enum.uniq_by(& &1.user_id) |> length()
    by_day = Enum.group_by(rows, & &1.day)

    %{
      from: from,
      to: today,
      idle_seconds: config.idle_seconds,
      seconds: total,
      people: people,
      account_days: length(rows),
      per_day_avg: average(totals),
      per_day_median: median(totals),
      per_person: if(people > 0, do: total / people),
      series:
        for day <- Date.range(from, today) do
          day_totals = by_day |> Map.get(day, []) |> Enum.map(& &1.seconds)

          %{
            day: day,
            people: length(day_totals),
            seconds: Enum.sum(day_totals),
            avg: average(day_totals),
            median: median(day_totals)
          }
        end,
      buckets: buckets(totals),
      areas: areas(rows, total, config),
      details: details(rows, total, config)
    }
  end

  # ── marks ───────────────────────────────────────────────────────────────

  # One row per moment: `user_id`, `t` (Unix seconds, a float), `src`
  # (`e` an event, `r` a play), `name` (the event's, or the play's kind),
  # `dim` (the declared field of a declared event, else NULL).
  defp marks(reach, stop, config, segment) do
    {dim_key, dim_names} = config.dim

    events =
      from(e in Event,
        where: not is_nil(e.user_id) and e.inserted_at >= ^reach and e.inserted_at < ^stop
      )
      |> event_marks(dim_key, dim_names)
      |> Segment.restrict(segment)

    play_from = DateTime.add(reach, -@play_lookback_days, :day)

    starts =
      from(r in Result,
        where: not is_nil(r.user_id) and r.started_at >= ^reach and r.started_at < ^stop
      )
      |> play_marks(nil)
      |> Segment.restrict(segment)

    steps =
      from(r in Result,
        join: ev in ResultEvent,
        on: ev.result_id == r.id,
        where: not is_nil(r.user_id) and r.started_at >= ^play_from and r.started_at < ^stop
      )
      |> play_marks(:elapsed)
      |> Segment.restrict(segment)

    events |> union_all(^starts) |> union_all(^steps)
  end

  # Ecto takes a fragment's SQL only as a literal, so each dialect's
  # query is written out: Unix seconds of a timestamp.
  defp event_marks(query, dim_key, dim_names) do
    if postgres?() do
      select(query, [e], %{
        user_id: selected_as(e.user_id, :user_id),
        t:
          selected_as(
            fragment("CAST(EXTRACT(EPOCH FROM ?) AS DOUBLE PRECISION)", e.inserted_at),
            :t
          ),
        src: selected_as(fragment("'e'"), :src),
        name: selected_as(e.name, :name),
        dim:
          selected_as(
            fragment(
              "CASE WHEN ? THEN ? ->> CAST(? AS TEXT) END",
              e.name in ^dim_names,
              e.dims,
              ^dim_key
            ),
            :dim
          )
      })
    else
      select(query, [e], %{
        user_id: selected_as(e.user_id, :user_id),
        t: selected_as(fragment("(julianday(?) - 2440587.5) * 86400.0", e.inserted_at), :t),
        src: selected_as(fragment("'e'"), :src),
        name: selected_as(e.name, :name),
        dim:
          selected_as(
            fragment(
              "CASE WHEN ? THEN ? ->> CAST(? AS TEXT) END",
              e.name in ^dim_names,
              e.dims,
              ^dim_key
            ),
            :dim
          )
      })
    end
  end

  defp play_marks(query, nil) do
    if postgres?() do
      select(query, [r], %{
        user_id: selected_as(r.user_id, :user_id),
        t:
          selected_as(
            fragment("CAST(EXTRACT(EPOCH FROM ?) AS DOUBLE PRECISION)", r.started_at),
            :t
          ),
        src: selected_as(fragment("'r'"), :src),
        name: selected_as(r.kind, :name),
        dim: selected_as(fragment("CAST(NULL AS TEXT)"), :dim)
      })
    else
      select(query, [r], %{
        user_id: selected_as(r.user_id, :user_id),
        t: selected_as(fragment("(julianday(?) - 2440587.5) * 86400.0", r.started_at), :t),
        src: selected_as(fragment("'r'"), :src),
        name: selected_as(r.kind, :name),
        dim: selected_as(fragment("CAST(NULL AS TEXT)"), :dim)
      })
    end
  end

  defp play_marks(query, :elapsed) do
    if postgres?() do
      select(query, [r, ev], %{
        user_id: selected_as(r.user_id, :user_id),
        t:
          selected_as(
            fragment(
              "CAST(EXTRACT(EPOCH FROM ?) AS DOUBLE PRECISION) + ? / 1000.0",
              r.started_at,
              ev.elapsed_ms
            ),
            :t
          ),
        src: selected_as(fragment("'r'"), :src),
        name: selected_as(r.kind, :name),
        dim: selected_as(fragment("CAST(NULL AS TEXT)"), :dim)
      })
    else
      select(query, [r, ev], %{
        user_id: selected_as(r.user_id, :user_id),
        t:
          selected_as(
            fragment(
              "(julianday(?) - 2440587.5) * 86400.0 + ? / 1000.0",
              r.started_at,
              ev.elapsed_ms
            ),
            :t
          ),
        src: selected_as(fragment("'r'"), :src),
        name: selected_as(r.kind, :name),
        dim: selected_as(fragment("CAST(NULL AS TEXT)"), :dim)
      })
    end
  end

  # Days since 1970 of a Unix-seconds column.
  defp day_number(column) do
    if postgres?(),
      do: "CAST(FLOOR(#{column} / 86400) AS INTEGER)",
      else: "CAST(#{column} / 86400 AS INTEGER)"
  end

  # A span's end counts its time from its start. Names are the host's own
  # code (`Catalog.overview/0` checks them), written into the SQL.
  defp span_condition(%{spans: []}), do: ""

  defp span_condition(%{spans: spans, span_seconds: cap}) do
    pairs =
      Enum.map_join(spans, " OR ", fn {first, last} ->
        "(psrc = 'e' AND pname = '#{first}' AND src = 'e' AND name = '#{last}')"
      end)

    " OR ((#{pairs}) AND t - pt <= #{cap})"
  end

  # ── filing ──────────────────────────────────────────────────────────────

  defp place("r", kind, _dim, config), do: {config.results, kind}

  defp place(_event, name, dim, config) do
    raw = if is_binary(dim) and dim != "", do: dim, else: Catalog.event(name).group
    {Map.get(config.areas, raw, raw), nil}
  end

  defp areas(rows, total, config) do
    rows
    |> Enum.flat_map(fn row ->
      row.by
      |> Enum.group_by(fn {{area, _detail}, _s} -> area end, fn {_place, s} -> s end)
      |> Enum.map(fn {area, seconds} -> {area, row.user_id, Enum.sum(seconds)} end)
    end)
    |> summarise(total, fn area -> %{id: area, label: label(area, config)} end)
  end

  defp details(rows, total, config) do
    rows
    |> Enum.flat_map(fn row ->
      for {{area, detail}, seconds} <- row.by,
          not is_nil(detail),
          do: {{area, detail}, row.user_id, seconds}
    end)
    |> summarise(total, fn {area, detail} ->
      %{id: detail, area: area, label: detail, area_label: label(area, config)}
    end)
  end

  # `[{key, user_id, seconds}]`, one per account-day, into one row per key.
  defp summarise(entries, total, head) do
    entries
    |> Enum.group_by(&elem(&1, 0))
    |> Enum.map(fn {key, list} ->
      seconds = Enum.sum_by(list, &elem(&1, 2))

      key
      |> head.()
      |> Map.merge(%{
        people: list |> Enum.uniq_by(&elem(&1, 1)) |> length(),
        account_days: length(list),
        seconds: seconds,
        avg: seconds / length(list),
        share: if(total > 0, do: seconds / total)
      })
    end)
    |> Enum.sort_by(&{-&1.seconds, &1.label})
  end

  defp label(area, config) do
    Map.get(config.labels, area) ||
      case Enum.find(Catalog.groups(), &(&1.id == area)) do
        %{label: label} -> label
        nil -> area
      end
  end

  defp buckets(totals) do
    {counts, _floor} =
      Enum.map_reduce(@buckets, 0, fn {label, upto}, floor ->
        n = Enum.count(totals, &(&1 >= floor and (is_nil(upto) or &1 < upto)))
        {%{label: label, count: n}, upto}
      end)

    counts
  end

  defp average([]), do: nil
  defp average(list), do: Enum.sum(list) / length(list)

  defp median([]), do: nil

  defp median(list) do
    sorted = Enum.sort(list)
    n = length(sorted)
    mid = div(n, 2)

    if rem(n, 2) == 1,
      do: Enum.at(sorted, mid),
      else: (Enum.at(sorted, mid - 1) + Enum.at(sorted, mid)) / 2
  end

  defp postgres?, do: AdvisoryLock.postgres?()

  defp to_float(nil), do: 0.0
  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(n) when is_number(n), do: n * 1.0

  defp to_int(%Decimal{} = d), do: Decimal.to_integer(d)
  defp to_int(n) when is_integer(n), do: n
  defp to_int(f) when is_float(f), do: trunc(f)
end
