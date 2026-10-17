defmodule Gamend.Analytics.Explore do
  @moduledoc """
  Reading the event rows (`analytics_events`) one question at a time: one
  event, a group of them or all, over a range of UTC days, in one segment
  (`Gamend.Analytics.Segment`), narrowed by any of the events' dimensions
  (`lang = ro`, `mode = daily`) or to one account. The admin Analytics
  pages' Explore and People tabs are built on it.

  A filter is a map (`filter/1` fills the defaults):

      %{names: ["web.game.finished"] | :all, from: ~D[…], to: ~D[…],
        segment: :all, where: %{"lang" => "ro"}, user_id: nil}

  A `where` value of `"none"` matches the events without that field, the
  way a breakdown names them.

  Rows are an account's only (a visitor's event is a counter), so every
  number here is about accounts. `counter_series/4` reads the counters,
  where everyone is, for the same event.
  """

  import Ecto.Query

  alias Gamend.Analytics
  alias Gamend.Analytics.ActivityDay
  alias Gamend.Analytics.Event
  alias Gamend.Analytics.Segment
  alias Gamend.Repo

  @type filter :: %{
          names: [String.t()] | :all,
          from: Date.t(),
          to: Date.t(),
          segment: Segment.t(),
          where: %{String.t() => String.t()},
          user_id: String.t() | nil
        }

  @doc """
  A filter from options: `names:` (default `:all`), `to:` (default today),
  `from:` or `days:` (default 30, ending on `to`), `segment:`, `where:`,
  `user_id:`.
  """
  @spec filter(keyword()) :: filter()
  def filter(opts \\ []) do
    to = Keyword.get(opts, :to, Date.utc_today())
    from = Keyword.get(opts, :from) || Date.add(to, -(Keyword.get(opts, :days, 30) - 1))

    %{
      names: Keyword.get(opts, :names, :all),
      from: from,
      to: to,
      segment: Keyword.get(opts, :segment, :all),
      where: Keyword.get(opts, :where, %{}),
      user_id: Keyword.get(opts, :user_id)
    }
  end

  @doc "Every day of the filter's range: `[%{day, events, people}]`, oldest first."
  @spec series(filter()) :: [%{day: Date.t(), events: integer(), people: integer()}]
  def series(filter) do
    by_day =
      filter
      |> base()
      |> group_by([e], fragment("date(?)", e.inserted_at))
      |> select(
        [e],
        {fragment("date(?)", e.inserted_at), count(e.id), count(e.user_id, :distinct)}
      )
      |> Repo.all()
      |> Map.new(fn {day, events, people} -> {to_date(day), {events, people}} end)

    for day <- days(filter) do
      {events, people} = Map.get(by_day, day, {0, 0})
      %{day: day, events: events, people: people}
    end
  end

  @doc "The filter's events and distinct people."
  @spec totals(filter()) :: %{events: integer(), people: integer()}
  def totals(filter) do
    {events, people} =
      filter
      |> base()
      |> select([e], {count(e.id), count(e.user_id, :distinct)})
      |> Repo.one()

    %{events: events, people: people}
  end

  @doc """
  The filter's events by the values of one dimension, most people first:
  `[%{value, events, people, measures: %{m => avg}, rates: %{label => r}}]`.
  A row without the field is `"none"`. Options: `measures:` (field names to
  average), `rates:` (`{numerator, denominator, label}`: the sum of one
  over the sum of the other, a score over its questions).
  """
  @spec breakdown(filter(), String.t(), keyword()) :: [map()]
  def breakdown(filter, dim, opts \\ []) when is_binary(dim) do
    measures = Keyword.get(opts, :measures, [])
    rates = Keyword.get(opts, :rates, [])
    sums = Enum.uniq(measures ++ Enum.flat_map(rates, fn {n, d, _} -> [n, d] end))

    # `->>` with a CAST: the same SQL on Postgres (jsonb) and SQLite (JSON
    # text). Grouped by the selected column's name, not the expression
    # again, or Postgres binds `dim` twice and will not group by it.
    counts =
      filter
      |> base()
      |> group_by(selected_as(:dim_value))
      |> select([e], %{
        value: selected_as(fragment("? ->> CAST(? AS TEXT)", e.dims, ^dim), :dim_value),
        events: count(e.id),
        people: count(e.user_id, :distinct)
      })
      |> Repo.all()

    sums_by_field = Map.new(sums, &{&1, field_sums(filter, dim, &1)})

    counts
    |> Enum.map(fn row ->
      value = value_name(row.value)

      measure_values =
        Map.new(measures, fn m ->
          {sum, n} = sums_by_field |> Map.fetch!(m) |> Map.get(value, {0.0, 0})
          {m, if(n > 0, do: sum / n)}
        end)

      rate_values =
        Map.new(rates, fn {num, den, label} ->
          {num_sum, _} = sums_by_field |> Map.fetch!(num) |> Map.get(value, {0.0, 0})
          {den_sum, _} = sums_by_field |> Map.fetch!(den) |> Map.get(value, {0.0, 0})
          {label, if(den_sum > 0, do: num_sum / den_sum)}
        end)

      %{
        value: value,
        events: row.events,
        people: row.people,
        measures: measure_values,
        rates: rate_values
      }
    end)
    |> Enum.sort_by(&{-&1.people, -&1.events, &1.value})
  end

  # `%{dim value => {sum, how many had the field}}` of one numeric field.
  defp field_sums(filter, dim, field) do
    filter
    |> base()
    |> group_by(selected_as(:dim_value))
    |> select([e], %{
      value: selected_as(fragment("? ->> CAST(? AS TEXT)", e.dims, ^dim), :dim_value),
      sum: sum(type(fragment("? ->> CAST(? AS TEXT)", e.dims, ^field), :float)),
      n: count(fragment("? ->> CAST(? AS TEXT)", e.dims, ^field))
    })
    |> Repo.all()
    |> Map.new(fn row -> {value_name(row.value), {to_float(row.sum), row.n}} end)
  end

  @doc """
  The filter's whole-range averages and rates, as `breakdown/3` computes
  them per value: `%{measures: %{m => avg}, rates: %{label => r}}`.
  """
  @spec measures(filter(), keyword()) :: %{measures: map(), rates: map()}
  def measures(filter, opts \\ []) do
    measures = Keyword.get(opts, :measures, [])
    rates = Keyword.get(opts, :rates, [])
    sums = Enum.uniq(measures ++ Enum.flat_map(rates, fn {n, d, _} -> [n, d] end))

    totals =
      Map.new(sums, fn field ->
        {sum, n} =
          filter
          |> base()
          |> select([e], {
            sum(type(fragment("? ->> CAST(? AS TEXT)", e.dims, ^field), :float)),
            count(fragment("? ->> CAST(? AS TEXT)", e.dims, ^field))
          })
          |> Repo.one()

        {field, {to_float(sum), n}}
      end)

    %{
      measures:
        Map.new(measures, fn m ->
          {sum, n} = Map.fetch!(totals, m)
          {m, if(n > 0, do: sum / n)}
        end),
      rates:
        Map.new(rates, fn {num, den, label} ->
          {num_sum, _} = Map.fetch!(totals, num)
          {den_sum, _} = Map.fetch!(totals, den)
          {label, if(den_sum > 0, do: num_sum / den_sum)}
        end)
    }
  end

  @doc """
  One page of the filter's rows, newest first, each with its account
  (`user`, nil once the account is deleted): `%{rows, total}`. Options:
  `page:` (from 1), `page_size:` (default 50).
  """
  @spec rows(filter(), keyword()) :: %{rows: [Event.t()], total: non_neg_integer()}
  def rows(filter, opts \\ []) do
    query = base(filter)

    rows =
      query
      |> order_by([e], desc: e.inserted_at, desc: e.id)
      |> Gamend.Query.page(
        page: Keyword.get(opts, :page, 1),
        page_size: Keyword.get(opts, :page_size, 50)
      )
      |> preload(:user)
      |> Repo.all()

    %{rows: rows, total: Repo.aggregate(query, :count, :id)}
  end

  @doc """
  The event names with a row in the last `days` days ending on `to`, by how
  many rows, most first: `[{name, events}]`.
  """
  @spec names(pos_integer(), Date.t()) :: [{String.t(), non_neg_integer()}]
  def names(days \\ 90, to \\ Date.utc_today()) do
    filter(days: days, to: to)
    |> base()
    |> group_by([e], e.name)
    |> select([e], {e.name, count(e.id)})
    |> Repo.all()
    |> Enum.sort_by(fn {name, n} -> {-n, name} end)
  end

  @doc """
  The daily counter behind an event, everyone included, for the filter's
  days: the bare name with no `where`, `name.dim:value` with one, nil with
  more (no counter holds two dimensions at once) or with several names.
  """
  @spec counter_series(filter()) :: [%{day: Date.t(), count: integer()}] | nil
  def counter_series(%{names: [name]} = filter) do
    key =
      case Map.to_list(filter.where) do
        [] -> name
        [{dim, value}] -> "#{name}.#{dim}:#{value}"
        _ -> nil
      end

    if key && is_nil(filter.user_id) && filter.segment == :all do
      by_day =
        key
        |> Analytics.counts(Date.diff(filter.to, filter.from) + 1, filter.to)
        |> Map.get(key, %{})

      for day <- days(filter), do: %{day: day, count: Map.get(by_day, day, 0)}
    end
  end

  def counter_series(_filter), do: nil

  # ── one account ──────────────────────────────────────────────────────────

  @doc """
  What one account has done: `%{first_day, last_day, days_active,
  days_active_30, events, by_name}` — its activity days (all of them, and
  in the last 30), its event rows, and those by name (`[%{name, events,
  last_at}]`, most first).
  """
  @spec person(String.t(), Date.t()) :: map()
  def person(user_id, today \\ Date.utc_today()) when is_binary(user_id) do
    month = Date.add(today, -29)

    {first, last, total, recent} =
      from(a in ActivityDay,
        where: a.user_id == ^user_id,
        select: {
          min(a.day),
          max(a.day),
          count(a.day),
          filter(count(a.day), a.day >= ^month)
        }
      )
      |> Repo.one()

    by_name =
      from(e in Event,
        where: e.user_id == ^user_id,
        group_by: e.name,
        select: %{name: e.name, events: count(e.id), last_at: max(e.inserted_at)}
      )
      |> Repo.all()
      |> Enum.sort_by(&{-&1.events, &1.name})

    %{
      first_day: first && to_date(first),
      last_day: last && to_date(last),
      days_active: total,
      days_active_30: recent,
      events: Enum.sum_by(by_name, & &1.events),
      by_name: by_name
    }
  end

  @doc "The days `user_id` was seen in `from..to`, as a set of dates."
  @spec active_days(String.t(), Date.t(), Date.t()) :: MapSet.t(Date.t())
  def active_days(user_id, %Date{} = from, %Date{} = to) when is_binary(user_id) do
    from(a in ActivityDay,
      where: a.user_id == ^user_id and a.day >= ^from and a.day <= ^to,
      select: a.day
    )
    |> Repo.all()
    |> MapSet.new(&to_date/1)
  end

  # ── the query ───────────────────────────────────────────────────────────

  defp base(filter) do
    start = DateTime.new!(filter.from, ~T[00:00:00], "Etc/UTC")
    stop = DateTime.new!(Date.add(filter.to, 1), ~T[00:00:00], "Etc/UTC")

    from(e in Event, where: e.inserted_at >= ^start and e.inserted_at < ^stop)
    |> where_names(filter.names)
    |> where_user(filter.user_id)
    |> where_dims(filter.where)
    |> Segment.restrict(filter.segment)
  end

  defp where_names(query, :all), do: query
  defp where_names(query, [name]), do: where(query, [e], e.name == ^name)
  defp where_names(query, names) when is_list(names), do: where(query, [e], e.name in ^names)

  defp where_user(query, nil), do: query
  defp where_user(query, user_id), do: where(query, [e], e.user_id == ^user_id)

  defp where_dims(query, where) do
    Enum.reduce(where, query, fn
      {dim, "none"}, query ->
        where(query, [e], is_nil(fragment("? ->> CAST(? AS TEXT)", e.dims, ^dim)))

      {dim, value}, query ->
        where(query, [e], fragment("? ->> CAST(? AS TEXT)", e.dims, ^dim) == ^value)
    end)
  end

  defp days(filter) do
    Enum.map(0..Date.diff(filter.to, filter.from)//1, &Date.add(filter.from, &1))
  end

  defp value_name(nil), do: "none"
  defp value_name(value), do: to_string(value)

  defp to_float(nil), do: 0.0
  defp to_float(%Decimal{} = d), do: Decimal.to_float(d)
  defp to_float(n) when is_number(n), do: n / 1

  # `date(...)` comes back as a Date on Postgres and as "YYYY-MM-DD" on SQLite.
  defp to_date(%Date{} = date), do: date
  defp to_date(text) when is_binary(text), do: Date.from_iso8601!(text)
end
