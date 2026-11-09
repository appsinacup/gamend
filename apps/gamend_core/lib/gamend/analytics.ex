defmodule Gamend.Analytics do
  @moduledoc """
  The one place aggregate numbers come from. Four families:

  * **Activity & retention** — DAU / WAU / MAU, new users per day, strict
    D1 / D7 / D30 cohort retention, payer conversion. Derived from
    `user_activity_days` (one row per user per UTC day seen, written by
    `record_activity/2` from the `last_seen_at` touches in `Gamend.Accounts`),
    `users.inserted_at` for cohorts and `purchases` for payers.
  * **Snapshot** — `snapshot/0`: every context's live counters (players,
    lobbies, parties, quests, signaling, matchmaking, tournaments) composed
    once and cached, so the public stats page, the admin index and the
    `/api/v1/stats` endpoint show the same numbers instead of each calling
    six modules.
  * **Economy flow** — `economy_flow/2`: coins granted and spent per day per
    ledger `reason`, straight from `ledger_entries`.
  * **Daily counters** — `count/3` + `counts/2`: named per-day counters for
    events that have no table of their own (a level finished, a start blocked
    by empty hearts). The game picks the keys; the engine sums them.
    `families/3` reads them back grouped: a base key with its dimensions.
  * **Events** — `track/3`: one call that counts (the name, and the name per
    dimension) AND, for an account, keeps the row — who, when, every field —
    in `analytics_events`. A visitor's event is counted only. The counters answer "how many" forever; the rows
    answer what a sum cannot: how many distinct people did a thing
    (`feature_summary/1`: DAU / WAU / MAU, first-timers and D1 / D7 / D30
    per feature), in what order, with what else. Writes are gathered by
    `Gamend.Analytics.Buffer` and landed in batches.

  Days are UTC, like every other period boundary on the server. "D7" means
  *seen on the 7th day after the registration day*, not "seen at any point in
  the first week" — the classic strict definition, so numbers compare with
  the ones stores and ad networks report.

  Reads are cheap enough for a dashboard on a small database; the composed
  views (`snapshot/0`, `dashboard_stats/0`) cache for a minute or a few.
  Nothing here is exposed to players except through the operator-gated
  public stats page.
  """

  import Ecto.Query

  require Gamend.Placeholder, as: Placeholder
  require Logger

  alias Gamend.Accounts
  alias Gamend.Accounts.User
  alias Gamend.Analytics.ActivityDay
  alias Gamend.Analytics.Buffer
  alias Gamend.Analytics.Catalog
  alias Gamend.Analytics.DailyCount
  alias Gamend.Analytics.Event
  alias Gamend.Analytics.Segment
  alias Gamend.Cache
  alias Gamend.Economy.LedgerEntry
  alias Gamend.Payments.Entitlement
  alias Gamend.Payments.Purchase
  alias Gamend.Repo
  alias Gamend.Repo.AdvisoryLock

  require Gamend.Payments.EntitlementStatus, as: EntitlementStatus
  require Gamend.Payments.PaymentEnvironment, as: PaymentEnvironment
  require Gamend.Payments.PurchaseStatus, as: PurchaseStatus

  @none Placeholder.none()

  @stats_cache_ttl_ms :timer.minutes(5)
  @snapshot_cache_ttl_ms :timer.minutes(1)
  # A user's "already recorded today" marker. Longer than a day so it survives
  # into tomorrow, when the day comparison (not the TTL) triggers the next row.
  @seen_cache_ttl_ms :timer.hours(30)
  # The dashboard's daily table.
  @series_days 30
  # Cohorts considered for the headline D1/D7/D30 rates.
  @cohort_window_days 60
  @horizons [1, 7, 30]
  # The weekly cohorts: how many sign-up weeks, and the weeks after each.
  @cohort_week_count 8
  @cohort_week_horizons [1, 2, 3, 4]
  # How many of the last 30 days an account was seen on (`active_days/2`).
  @active_day_buckets [
    {1, 1, "1 day"},
    {2, 2, "2 days"},
    {3, 4, "3–4 days"},
    {5, 9, "5–9 days"},
    {10, 30, "10+ days"}
  ]

  @type rate :: float() | nil

  # -- snapshot ------------------------------------------------------------------

  @doc """
  Every context's live counters in one map, cached for a minute:

      %{
        players: %{players_online, players_total, players_offline, players_in_lobbies, players_in_parties},
        activity: %{dau, wau, mau, new_users_1d, new_users_7d, new_users_30d},
        lobbies: %{lobbies_total, by_state, spectators},
        parties: %{parties_active, players_in_parties},
        quests: %{quests_total, completed, claimed},
        signaling: %{rooms_enabled, rooms_active, peers_connected},
        matchmaking: %{queued, queues},
        tournaments: %{tournaments, entries, matches}
      }

  Everything in it is safe to show publicly (the stats page is opt-in via
  `:public_stats`); `matchmaking` is the already-public subset. Consumers
  read this rather than calling the contexts, so the same number cannot
  drift between two pages.
  """
  @spec snapshot() :: map()
  def snapshot do
    Cache.cached({:analytics, :snapshot}, [ttl: @snapshot_cache_ttl_ms], fn ->
      today = Date.utc_today()
      mm = Gamend.Matchmaking.stats()

      %{
        players: Accounts.player_stats(),
        activity: %{
          dau: dau(today),
          wau: wau(today),
          mau: mau(today),
          new_users_1d: new_users(today, today),
          new_users_7d: new_users(Date.add(today, -6), today),
          new_users_30d: new_users(Date.add(today, -29), today)
        },
        lobbies: Gamend.Lobbies.stats(),
        parties: Gamend.Parties.stats(),
        quests: Gamend.Quests.stats(),
        signaling: Gamend.Signaling.stats(),
        matchmaking: Map.take(mm, [:queued, :queues]),
        tournaments: Gamend.Tournaments.stats()
      }
    end)
  end

  @doc "Accounts created on any UTC day in `from..to` (inclusive)."
  @spec new_users(Date.t(), Date.t()) :: non_neg_integer()
  def new_users(%Date{} = from, %Date{} = to) do
    start = start_of_day(from)
    stop = start_of_day(Date.add(to, 1))

    Repo.one(
      from u in User,
        where: u.inserted_at >= ^start and u.inserted_at < ^stop,
        select: count(u.id)
    ) || 0
  end

  # -- daily counters --------------------------------------------------------------

  @doc """
  Adds `n` to the counter `key` for the UTC day of `now`. Gathered by
  `Gamend.Analytics.Buffer` and written as one upsert per `(key, day)` at the
  next flush (within `flush_ms`, 10 s); written through at once where the
  buffer is off (tests) or not running. Cheap enough for any path.

  Keys are dotted, game-owned strings up to #{DailyCount.key_max()} chars;
  put a dimension after a colon (`"level.started.lang:ja"`) so `counts/2`
  can pull a whole family by prefix and `families/3` can group it. Never
  raises; a bad key is dropped with a warning.
  """
  @spec count(String.t(), pos_integer(), DateTime.t()) :: :ok
  def count(key, n \\ 1, now \\ DateTime.utc_now())

  def count(key, n, %DateTime{} = now)
      when is_binary(key) and key != "" and byte_size(key) <= 128 and is_integer(n) and n > 0 do
    day = DateTime.to_date(now)

    if Buffer.buffered?(),
      do: Buffer.bump(key, n, day),
      else: write_count(key, n, day)
  end

  def count(key, n, now) do
    Logger.warning("analytics: daily count dropped: #{inspect({key, n, now})}")
    :ok
  end

  @doc false
  # The upsert behind `count/3`: one atomic increment of `(key, day)`.
  # `Gamend.Analytics.Buffer` calls it at flush time.
  @spec write_count(String.t(), pos_integer(), Date.t()) :: :ok
  def write_count(key, n, %Date{} = day) do
    on_conflict = from(c in DailyCount, update: [inc: [count: ^n]])

    _ =
      %DailyCount{}
      |> DailyCount.changeset(%{day: day, key: key, count: n})
      |> Repo.insert(on_conflict: on_conflict, conflict_target: [:day, :key])

    :ok
  rescue
    Ecto.ConstraintError ->
      :ok

    # Same contract as `insert_day/2`, for the same reason: this rides along
    # with a level end or a purchase, and a counter is never worth the write
    # it rides on. SQLite raises `Database busy` on a contended write.
    error ->
      Logger.warning("analytics: daily count #{key} failed: #{Exception.message(error)}")
      :ok
  end

  @doc "Writes everything `Gamend.Analytics.Buffer` has gathered, now, in the caller's process."
  @spec flush() :: {non_neg_integer(), non_neg_integer()}
  def flush, do: Buffer.flush()

  @doc """
  Per-day values of one counter or a prefix family over the last `days` days
  ending on `today`, as `%{key => %{Date => count}}`. `key` may end in `*` to
  match a prefix (`"level.started.lang:*"`).
  """
  @spec counts(String.t(), pos_integer(), Date.t()) :: %{String.t() => %{Date.t() => integer()}}
  def counts(key, days \\ 7, today \\ Date.utc_today())
      when is_binary(key) and is_integer(days) and days > 0 do
    first = Date.add(today, -(days - 1))
    base = from(c in DailyCount, where: c.day >= ^first and c.day <= ^today)

    query =
      case String.split_at(key, -1) do
        {prefix, "*"} ->
          pattern = Repo.escape_like(prefix) <> "%"
          from(c in base, where: fragment("? LIKE ? ESCAPE '\\'", c.key, ^pattern))

        _ ->
          from(c in base, where: c.key == ^key)
      end

    query
    |> select([c], {c.key, c.day, c.count})
    |> Repo.all()
    |> Enum.group_by(fn {k, _, _} -> k end, fn {_, day, n} -> {to_date(day), n} end)
    |> Map.new(fn {k, pairs} -> {k, Map.new(pairs)} end)
  end

  @doc "Totals of `counts/3` per key over the window, largest first."
  @spec count_totals(String.t(), pos_integer(), Date.t()) :: [{String.t(), integer()}]
  def count_totals(key, days \\ 7, today \\ Date.utc_today()) do
    key
    |> counts(days, today)
    |> Enum.map(fn {k, by_day} -> {k, by_day |> Map.values() |> Enum.sum()} end)
    |> Enum.sort_by(fn {_, n} -> -n end)
  end

  # -- events ------------------------------------------------------------------------

  @name_max 64
  @dim_key_max 32
  @dim_value_max 64
  # Cohorts for the per-feature D1 / D7 / D30, and how far back "first seen"
  # looks: a player whose first event of a feature is older than this reads
  # as new to it.
  @feature_window_days 60

  @doc """
  Records that something happened: `name` is counted for the day (`count/3`),
  once more per DIMENSION (`name.lang:ro`), and, when it has a user, the
  whole event — `dims`, `user_id`, the moment — is kept as a row in
  `analytics_events`. One call, so a counter and its event can never
  disagree.

  An event with no user (a visitor, a webhook) is counted and never kept: a
  row is there to say WHO, and a visitor has no id to say it with. On a site
  crawlers read, they were nearly every row.

  `name` is dotted `[a-z0-9_]`, up to #{@name_max} chars (`"web.game.finished"`).
  `dims` is a map of the event's fields, atom or string keys of `[a-z0-9_]`:

    * a string, atom or boolean value is a **dimension**: a closed set the
      caller owns (a language code, a game, `practice | daily`), counted as
      its own key, so keep free text out of it;
    * an integer or float is a **measure** (a score, seconds): kept in the
      row, never counted;
    * `nil` is dropped.

  Options: `user_id:` (nil for a visitor: counted only; nulled on the kept
  row when the account is deleted), `at:` (default now). Buffered like `count/3`. Never raises: a bad
  name or field is dropped with a warning, the rest is kept.

      Analytics.track("web.game.finished",
        %{game: "hangman", lang: "ro", mode: :daily, score: 7, total: 10},
        user_id: user_id)
  """
  @spec track(String.t(), map(), keyword()) :: :ok
  def track(name, dims \\ %{}, opts \\ [])

  def track(name, dims, opts) when is_binary(name) and is_map(dims) and is_list(opts) do
    at = Keyword.get(opts, :at, DateTime.utc_now())
    user_id = Keyword.get(opts, :user_id)

    cond do
      not valid_name?(name) ->
        Logger.warning("analytics: event #{inspect(name)} dropped: a dotted [a-z0-9_] name")

      not (is_nil(user_id) or is_binary(user_id)) ->
        Logger.warning("analytics: event #{name} dropped: user_id #{inspect(user_id)}")

      not match?(%DateTime{}, at) ->
        Logger.warning("analytics: event #{name} dropped: at #{inspect(at)}")

      true ->
        {dimensions, fields} = split_dims(name, dims)
        count(name, 1, at)
        Enum.each(dimensions, fn {k, v} -> count("#{name}.#{k}:#{v}", 1, at) end)

        if user_id, do: keep_row(name, fields, user_id, at)
    end

    :ok
  end

  def track(name, dims, opts) do
    Logger.warning("analytics: event dropped: #{inspect({name, dims, opts})}")
    :ok
  end

  defp keep_row(name, fields, user_id, at) do
    row = %{
      id: Gamend.UUIDv7.generate(),
      name: name,
      dims: fields,
      user_id: user_id,
      inserted_at: DateTime.truncate(at, :second)
    }

    if Buffer.buffered?(), do: Buffer.event(row), else: write_events([row])
  end

  defp valid_name?(name),
    do: byte_size(name) <= @name_max and Regex.match?(~r/\A[a-z0-9_]+(\.[a-z0-9_]+)*\z/, name)

  # `{dimensions, fields}`: the string-valued pairs to count, and every kept
  # pair (string keys) for the row.
  defp split_dims(name, dims) do
    Enum.reduce(dims, {[], %{}}, fn {key, value}, {dimensions, fields} = acc ->
      key = to_string(key)

      cond do
        byte_size(key) > @dim_key_max or not Regex.match?(~r/\A[a-z0-9_]+\z/, key) ->
          Logger.warning("analytics: event #{name}: field #{inspect(key)} dropped")
          acc

        is_nil(value) ->
          acc

        is_binary(value) ->
          value = truncate(value, @dim_value_max)
          {[{key, value} | dimensions], Map.put(fields, key, value)}

        is_atom(value) ->
          value = Atom.to_string(value)
          {[{key, value} | dimensions], Map.put(fields, key, value)}

        is_number(value) ->
          {dimensions, Map.put(fields, key, value)}

        true ->
          Logger.warning("analytics: event #{name}: field #{key} = #{inspect(value)} dropped")
          acc
      end
    end)
  end

  defp truncate(string, max) when byte_size(string) <= max, do: string

  defp truncate(string, max) do
    string
    |> String.graphemes()
    |> Enum.reduce_while("", fn g, acc ->
      if byte_size(acc) + byte_size(g) <= max, do: {:cont, acc <> g}, else: {:halt, acc}
    end)
  end

  @doc false
  # The insert behind `track/3`, one `insert_all` for a batch of rows.
  # `Gamend.Analytics.Buffer` calls it at flush time; `:error` keeps the
  # rows buffered for the next one.
  @spec write_events([map()]) :: :ok | :error
  def write_events([]), do: :ok

  def write_events(rows) when is_list(rows) do
    _ = Repo.insert_all(Event, rows)
    :ok
  rescue
    error ->
      # A row naming an account deleted since it was tracked (a guest merged
      # into the account it signed in to, an account deleted) fails the
      # whole batch on the foreign key, and a refused batch stays buffered,
      # so every later event queued behind it. Such a row is kept with no
      # person, as `on_delete: :nilify_all` does to rows already written.
      case gone_users(rows) do
        [] ->
          Logger.warning(
            "analytics: #{length(rows)} events not written: #{Exception.message(error)}"
          )

          :error

        gone ->
          Logger.info("analytics: events of #{length(gone)} deleted accounts kept without them")

          rows
          |> Enum.map(fn row -> if row.user_id in gone, do: %{row | user_id: nil}, else: row end)
          |> write_events()
      end
  end

  # The batch's user ids with no account left. None when the lookup fails
  # too (the database is down): the batch then waits for the next flush.
  defp gone_users(rows) do
    ids = rows |> Enum.map(& &1.user_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    if ids == [] do
      []
    else
      ids -- Repo.all(from(u in User, where: u.id in ^ids, select: u.id))
    end
  rescue
    _ -> []
  end

  @doc """
  The counters of the last `days` days grouped by family, largest first:
  `[%{key, total, by_day, dims}]`, where `key` is the bare counter
  (`"web.game.finished"`), `by_day` its `%{Date => n}`, and `dims` every
  dimension written under it — `%{"lang" => [{"ro", 120}, {"es", 80}]}` from
  the keys `web.game.finished.lang:ro` and `…lang:es` — each list largest
  first. `prefix` as in `counts/3` (`"web.*"`, or one key).
  """
  @spec families(String.t(), pos_integer(), Date.t()) :: [map()]
  def families(prefix \\ "*", days \\ 7, today \\ Date.utc_today()) do
    prefix
    |> counts(days, today)
    |> Enum.reduce(%{}, fn {key, by_day}, acc ->
      total = by_day |> Map.values() |> Enum.sum()

      case split_key(key) do
        {base, nil, nil} ->
          Map.update(
            acc,
            base,
            family(base, total, by_day),
            &%{&1 | total: total, by_day: by_day}
          )

        {base, dim, value} ->
          acc
          |> Map.put_new(base, family(base, 0, %{}))
          |> update_in([base, :dims, Access.key(dim, [])], &[{value, total} | &1])
      end
    end)
    |> Map.values()
    |> Enum.map(fn fam ->
      %{fam | dims: Map.new(fam.dims, fn {d, vs} -> {d, Enum.sort_by(vs, &(-elem(&1, 1)))} end)}
    end)
    |> Enum.sort_by(&{-&1.total, &1.key})
  end

  defp family(key, total, by_day), do: %{key: key, total: total, by_day: by_day, dims: %{}}

  # `web.game.finished.lang:ro` -> {"web.game.finished", "lang", "ro"};
  # `web.game.finished` -> {"web.game.finished", nil, nil}.
  defp split_key(key) do
    case :binary.match(key, ":") do
      {pos, 1} ->
        <<head::binary-size(^pos), ":", value::binary>> = key

        case head |> String.split(".") |> Enum.split(-1) do
          {[_ | _] = base, [dim]} -> {Enum.join(base, "."), dim, value}
          _ -> {key, nil, nil}
        end

      :nomatch ->
        {key, nil, nil}
    end
  end

  @doc """
  Every event name of the last #{@feature_window_days} days as a feature,
  with what `summary/1` says of the whole site: `[%{name, dau, wau, mau,
  stickiness, events_7d, new_7d, new_30d, d1, d7, d30}]`, largest MAU first.

  Active = at least one event of that name that day (only an account's
  events are kept as rows). "New" = first event of the name in the window (a
  player back after #{@feature_window_days} quiet days reads as new). D1 / D7
  / D30 are pooled over the first-day cohorts old enough to have reached the
  horizon, as `summary/1` pools sign-up cohorts.

  Options: `segment:` (`segments/0`, default `:all`).
  """
  @spec feature_summary(Date.t(), keyword()) :: [map()]
  def feature_summary(today \\ Date.utc_today(), opts \\ []) do
    segment = Keyword.get(opts, :segment, :all)
    first = Date.add(today, -(@feature_window_days - 1))
    stop = start_of_day(Date.add(today, 1))
    week_start = start_of_day(Date.add(today, -6))

    events_7d =
      from(e in Event,
        where: e.inserted_at >= ^week_start and e.inserted_at < ^stop,
        group_by: e.name,
        select: {e.name, count(e.id)}
      )
      |> in_segment(segment)
      |> Repo.all()
      |> Map.new()

    people = feature_people(first, today, segment)

    events_7d
    |> Map.keys()
    |> MapSet.new()
    |> MapSet.union(MapSet.new(Map.keys(people)))
    |> Enum.map(fn name ->
      feature_row(name, Map.get(people, name), Map.get(events_7d, name, 0))
    end)
    |> Enum.sort_by(&{-&1.mau, -&1.events_7d, &1.name})
  end

  # Per event name, counted by the database: each person's first and last
  # day with it in the window, so active / new are counts over people, and
  # whether they were seen again on their first day + 1 / 7 / 30. Reading
  # every (name, day, person) into the app instead took 14 s at a million
  # players.
  defp feature_people(first, today, segment) do
    presence =
      from(e in Event,
        where: not is_nil(e.user_id),
        where: e.inserted_at >= ^start_of_day(first),
        where: e.inserted_at < ^start_of_day(Date.add(today, 1)),
        distinct: true,
        select: %{
          name: selected_as(e.name, :name),
          user_id: selected_as(e.user_id, :user_id),
          day: selected_as(fragment("date(?)", e.inserted_at), :day)
        }
      )
      |> in_segment(segment)

    {presence_sql, params} = Repo.to_sql(:all, presence)

    since = fn column, day ->
      "SUM(CASE WHEN #{column} >= #{date_literal(day)} THEN 1 ELSE 0 END)"
    end

    reached = fn n ->
      "SUM(CASE WHEN first <= #{date_literal(Date.add(today, -n))} THEN 1 ELSE 0 END)"
    end

    back = fn n -> "MAX(CASE WHEN day = #{plus_days("first", n)} THEN 1 ELSE 0 END)" end

    # One row per (name, person, day), each beside the person's first day
    # with the name; then one per (name, person); then one per name.
    sql = """
    WITH p AS (#{presence_sql}),
    w AS (SELECT name, user_id, day, MIN(day) OVER (PARTITION BY name, user_id) AS first FROM p),
    f AS (
      SELECT name, user_id, MIN(first) AS first, MAX(day) AS last,
        #{back.(1)} AS k1, #{back.(7)} AS k7, #{back.(30)} AS k30
      FROM w GROUP BY name, user_id
    )
    SELECT name,
      #{since.("last", today)}, #{since.("last", Date.add(today, -6))},
      #{since.("last", Date.add(today, -29))},
      #{since.("first", Date.add(today, -6))}, #{since.("first", Date.add(today, -29))},
      #{reached.(1)}, SUM(k1), #{reached.(7)}, SUM(k7), #{reached.(30)}, SUM(k30)
    FROM f
    GROUP BY name
    """

    Repo.query!(sql, params, timeout: :infinity).rows
    |> Map.new(fn [name | counts] ->
      [dau, wau, mau, new_7d, new_30d, d1n, d1k, d7n, d7k, d30n, d30k] =
        Enum.map(counts, &to_int/1)

      {name,
       %{
         dau: dau,
         wau: wau,
         mau: mau,
         new_7d: new_7d,
         new_30d: new_30d,
         d1: ratio(d1k, d1n),
         d7: ratio(d7k, d7n),
         d30: ratio(d30k, d30n)
       }}
    end)
  end

  # Dates the code made, never input, so they are written into the SQL.
  defp date_literal(%Date{} = day) do
    if postgres?(), do: "DATE '#{Date.to_iso8601(day)}'", else: "'#{Date.to_iso8601(day)}'"
  end

  defp plus_days(column, n) do
    if postgres?(), do: "(#{column} + #{n})", else: "date(#{column}, '+#{n} days')"
  end

  @no_people %{dau: 0, wau: 0, mau: 0, new_7d: 0, new_30d: 0, d1: nil, d7: nil, d30: nil}

  defp feature_row(name, people, events_7d) do
    people = people || @no_people

    people
    |> Map.merge(%{name: name, events_7d: events_7d, stickiness: ratio(people.dau, people.mau)})
  end

  @doc """
  One feature broken down by one of its dimensions over the last `days`
  days: `[%{value, people, events}]`, people = distinct signed-in users,
  largest first; a row without the dimension is `"none"`. The dimensions a
  feature has are the keys of its family's `dims` (`families/3`). Options:
  `segment:` (`segments/0`).

      people_by_dimension("web.game.started", "game")
      #=> [%{value: "hangman", people: 41, events: 212}, …]
  """
  @spec people_by_dimension(String.t(), String.t(), pos_integer(), Date.t(), keyword()) ::
          [map()]
  def people_by_dimension(name, dim, days \\ 30, today \\ Date.utc_today(), opts \\ [])
      when is_binary(name) and is_binary(dim) and is_integer(days) and days > 0 do
    start = start_of_day(Date.add(today, -(days - 1)))
    stop = start_of_day(Date.add(today, 1))

    # `->>` with a CAST: the same SQL on Postgres (jsonb) and SQLite (JSON
    # text), and the cast tells Postgres which `->>` is meant. Grouped by the
    # selected column's name, not the expression again: written twice it
    # binds `dim` twice ($1 and $5), and Postgres will not take the two for
    # the same expression (`grouping_error`).
    from(e in Event,
      where: e.name == ^name and e.inserted_at >= ^start and e.inserted_at < ^stop,
      group_by: selected_as(:dim_value),
      select: %{
        value: selected_as(fragment("? ->> CAST(? AS TEXT)", e.dims, ^dim), :dim_value),
        people: count(e.user_id, :distinct),
        events: count(e.id)
      }
    )
    |> in_segment(Keyword.get(opts, :segment, :all))
    |> Repo.all()
    |> Enum.map(fn row ->
      %{row | value: if(is_nil(row.value), do: @none, else: to_string(row.value))}
    end)
    |> Enum.sort_by(&{-&1.people, -&1.events, &1.value})
  end

  @doc "The last `limit` events, newest first."
  @spec recent_events(pos_integer()) :: [Event.t()]
  def recent_events(limit \\ 50) when is_integer(limit) and limit > 0 do
    Repo.all(from e in Event, order_by: [desc: e.inserted_at, desc: e.id], limit: ^limit)
  end

  # -- economy flow ----------------------------------------------------------------

  @doc """
  Currency granted and spent per UTC day per ledger `reason` over the last
  `days` days: `[%{day, currency, reason, granted, spent, entries}]`, newest
  first. `granted`/`spent` are positive integers (spent is the absolute
  value of negative deltas). Options: `:currency` to filter.
  """
  @spec economy_flow(pos_integer(), keyword()) :: [map()]
  def economy_flow(days \\ 7, opts \\ []) when is_integer(days) and days > 0 do
    today = Keyword.get(opts, :today, Date.utc_today())
    start = start_of_day(Date.add(today, -(days - 1)))
    stop = start_of_day(Date.add(today, 1))
    currency = Keyword.get(opts, :currency)

    base =
      from(e in LedgerEntry,
        where: e.inserted_at >= ^start and e.inserted_at < ^stop,
        group_by: [fragment("date(?)", e.inserted_at), e.currency, e.reason],
        select: %{
          day: fragment("date(?)", e.inserted_at),
          currency: e.currency,
          reason: e.reason,
          granted: sum(fragment("CASE WHEN ? > 0 THEN ? ELSE 0 END", e.delta, e.delta)),
          spent: sum(fragment("CASE WHEN ? < 0 THEN -? ELSE 0 END", e.delta, e.delta)),
          entries: count(e.id)
        }
      )

    query = if currency, do: from(e in base, where: e.currency == ^currency), else: base

    query
    |> Repo.all()
    |> Enum.map(fn row ->
      %{row | day: to_date(row.day), granted: to_int(row.granted), spent: to_int(row.spent)}
    end)
    |> Enum.sort_by(fn r -> {Date.to_iso8601(r.day), r.currency, r.reason} end, :desc)
  end

  @doc """
  `economy_flow/2` collapsed over the window: one row per `{currency,
  reason}` with `granted`, `spent`, `net`, sorted by absolute net.
  """
  @spec economy_totals(pos_integer(), keyword()) :: [map()]
  def economy_totals(days \\ 7, opts \\ []) do
    days
    |> economy_flow(opts)
    |> Enum.group_by(&{&1.currency, &1.reason})
    |> Enum.map(fn {{currency, reason}, rows} ->
      granted = Enum.sum_by(rows, & &1.granted)
      spent = Enum.sum_by(rows, & &1.spent)

      %{
        currency: currency,
        reason: reason,
        granted: granted,
        spent: spent,
        net: granted - spent,
        entries: Enum.sum_by(rows, & &1.entries)
      }
    end)
    |> Enum.sort_by(&{&1.currency, -abs(&1.net)})
  end

  # -- recording ---------------------------------------------------------------

  @doc """
  Records that `user_id` was seen on the UTC day of `now`. Idempotent; the
  common case (already recorded today) is a single cache read. Never raises —
  a missing user (deleted mid-request) is a silent no-op, like the
  `last_seen_at` touch this rides along with.
  """
  @spec record_activity(Ecto.UUID.t(), DateTime.t()) :: :ok
  def record_activity(user_id, now \\ DateTime.utc_now())

  def record_activity(user_id, %DateTime{} = now) when is_binary(user_id) do
    day = DateTime.to_date(now)
    key = seen_key(user_id)

    case Cache.get!(key) do
      ^day ->
        :ok

      _ ->
        # Only mark the day as handled once it is: a row landed, or it never
        # can (the user is gone). A transient DB failure must not sit in the
        # cache for 30 hours suppressing the retry that would record the day.
        case insert_day(user_id, day) do
          {:error, :unavailable} -> :ok
          _ -> _ = Cache.put(key, day, ttl: @seen_cache_ttl_ms)
        end

        :ok
    end
  end

  def record_activity(_user_id, _now), do: :ok

  defp insert_day(user_id, day) do
    %ActivityDay{}
    |> ActivityDay.changeset(%{user_id: user_id, day: day})
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:user_id, :day])
  rescue
    # A user deleted between the touch and this insert. Postgres names the
    # violated constraint and the changeset turns it into `{:error, _}`;
    # SQLite reports it anonymously, which Ecto can only raise.
    Ecto.ConstraintError ->
      {:error, :constraint}

    # Anything the driver or the pool raises: SQLite answering a contended
    # write with `Database busy`, a checkout timeout, a disconnect. A day
    # marker rides along with a `last_seen_at` touch on the login path and is
    # never worth the request it rides on — see `record_activity/2`, which
    # promises it never raises. Drop the row, keep the login.
    error ->
      Logger.warning("analytics: activity day insert failed: #{Exception.message(error)}")
      {:error, :unavailable}
  end

  defp seen_key(user_id), do: {:analytics, :seen_day, user_id}

  # -- segments ------------------------------------------------------------------

  @doc "Every segment the people numbers split by (`Gamend.Analytics.Segment`)."
  @spec segments() :: [Segment.t()]
  def segments, do: Segment.all()

  @doc "A segment from a request parameter; anything unknown is `:all`."
  @spec segment(term()) :: Segment.t()
  def segment(param), do: Segment.parse(param)

  defp in_segment(query, segment), do: Segment.restrict(query, segment)

  # -- active users --------------------------------------------------------------

  @doc """
  Distinct users seen on any day in `from..to` (inclusive, UTC dates).
  Options: `segment:` (`segments/0`).
  """
  @spec active_users(Date.t(), Date.t(), keyword()) :: non_neg_integer()
  def active_users(%Date{} = from, %Date{} = to, opts \\ []) do
    from(a in ActivityDay,
      where: a.day >= ^from and a.day <= ^to,
      select: count(a.user_id, :distinct)
    )
    |> in_segment(Keyword.get(opts, :segment, :all))
    |> Repo.one() || 0
  end

  @doc "Daily active users on `day` (default: today, UTC)."
  @spec dau(Date.t(), keyword()) :: non_neg_integer()
  def dau(day \\ Date.utc_today(), opts \\ []), do: active_users(day, day, opts)

  @doc "Weekly active users: distinct users seen in the 7 days ending on `day`."
  @spec wau(Date.t(), keyword()) :: non_neg_integer()
  def wau(day \\ Date.utc_today(), opts \\ []), do: active_users(Date.add(day, -6), day, opts)

  @doc "Monthly active users: distinct users seen in the 30 days ending on `day`."
  @spec mau(Date.t(), keyword()) :: non_neg_integer()
  def mau(day \\ Date.utc_today(), opts \\ []), do: active_users(Date.add(day, -29), day, opts)

  # -- cohorts -------------------------------------------------------------------

  @doc """
  One row per UTC day for the last `days` days ending on `today`, oldest
  first: `%{day, active, new_active, returning, wau, mau, stickiness,
  new_users, d1, d7, d30}`. `new_active` are the accounts made that day and
  seen on it, `returning` the rest of `active`. `wau` / `mau` are the
  distinct users of the 7 / 30 days ending on that day, and `stickiness` is
  `active ÷ mau` of that day. A retention rate is `nil` when the cohort is
  empty, the horizon day has not happened yet, or the cohort is older than
  `retention_since` (`Gamend.Analytics.Catalog.overview/0`). Options:
  `segment:` (`segments/0`).
  """
  @spec daily_series(pos_integer(), Date.t(), keyword()) :: [map()]
  def daily_series(days \\ @series_days, today \\ Date.utc_today(), opts \\ [])
      when is_integer(days) and days > 0 do
    segment = Keyword.get(opts, :segment, :all)
    first = Date.add(today, -(days - 1))
    rolling = rolling_active(first, today, segment)
    %{sizes: sizes, retained: retained} = cohort_snapshot(first, today, segment)
    since = retention_since()

    for offset <- 0..(days - 1) do
      day = Date.add(first, offset)
      size = Map.get(sizes, day, 0)
      %{active: active, wau: wau, mau: mau} = Map.fetch!(rolling, day)
      new_active = Map.get(retained, {day, day}, 0)
      size = if undercounted?(day, since), do: 0, else: size

      %{
        day: day,
        active: active,
        new_active: new_active,
        returning: max(active - new_active, 0),
        wau: wau,
        mau: mau,
        stickiness: ratio(active, mau),
        new_users: Map.get(sizes, day, 0),
        d1: cohort_rate(retained, day, 1, size, today),
        d7: cohort_rate(retained, day, 7, size, today),
        d30: cohort_rate(retained, day, 30, size, today)
      }
    end
  end

  # `%{day => %{active, wau, mau}}` for every day in `first..today`, from the
  # days that can count (30 before `first` on), counted by the database in
  # one pass. Each user's days in order: a day newly covers the window days
  # its previous day did not, from that day's window end (or its own day) to
  # its own window end 7 or 30 days on. So a day's WAU is the window starts
  # up to it less the days seen up to 7 days before it (each ends there),
  # and likewise MAU at 30. The rows come back grouped by (day, week start,
  # month start), a few thousand at most. Reading every (user, day) row into
  # the app instead took over 15 s, and gigabytes, at a million players.
  defp rolling_active(first, today, segment) do
    from_day = Date.add(first, -29)

    seen =
      from(a in ActivityDay,
        where: a.day >= ^from_day and a.day <= ^today,
        select: %{user_id: selected_as(a.user_id, :user_id), day: selected_as(a.day, :day)}
      )
      |> in_segment(segment)

    {seen_sql, params} = Repo.to_sql(:all, seen)
    later = if postgres?(), do: "GREATEST", else: "MAX"

    sql = """
    WITH seen AS (#{seen_sql})
    SELECT n, #{later}(n, COALESCE(prev + 7, n)) AS ws, #{later}(n, COALESCE(prev + 30, n)) AS ms,
      COUNT(*)
    FROM (
      SELECT n, LAG(n) OVER (PARTITION BY user_id ORDER BY n) AS prev
      FROM (SELECT user_id, #{epoch_day("day")} AS n FROM seen) numbered
    ) days
    GROUP BY n, ws, ms
    """

    {seen_on, week_starts, month_starts} =
      Repo.query!(sql, params, timeout: :infinity).rows
      |> Enum.reduce({%{}, %{}, %{}}, fn [day_n, ws, ms, count], {d, w, m} ->
        count = to_int(count)

        {Map.update(d, to_int(day_n), count, &(&1 + count)),
         Map.update(w, to_int(ws), count, &(&1 + count)),
         Map.update(m, to_int(ms), count, &(&1 + count))}
      end)

    first_n = epoch_n(first)

    {_week, _month, by_day} =
      Enum.reduce(epoch_n(from_day)..epoch_n(today), {0, 0, %{}}, fn n, {w, m, acc} ->
        w = w + Map.get(week_starts, n, 0) - Map.get(seen_on, n - 7, 0)
        m = m + Map.get(month_starts, n, 0) - Map.get(seen_on, n - 30, 0)

        acc =
          if n >= first_n,
            do: Map.put(acc, from_epoch_n(n), %{active: Map.get(seen_on, n, 0), wau: w, mau: m}),
            else: acc

        {w, m, acc}
      end)

    by_day
  end

  # A day as days since 1970-01-01, in SQL and back.
  @epoch_days 719_528

  defp epoch_day(column) do
    if postgres?(),
      do: "(#{column} - DATE '1970-01-01')",
      else: "CAST(julianday(#{column}) - 2440587.5 AS INTEGER)"
  end

  defp epoch_n(%Date{} = day), do: Date.to_gregorian_days(day) - @epoch_days
  defp from_epoch_n(n), do: Date.from_gregorian_days(n + @epoch_days)

  defp postgres?, do: AdvisoryLock.postgres?()

  @doc """
  Headline numbers as of `today`: DAU (today so far) / WAU / MAU,
  stickiness (`dau_7d_avg`, the average DAU of the 7 full days before today,
  ÷ MAU: today's DAU is partial until midnight), new users
  in the last 7 and 30 days, D1 / D7 / D30 pooled over every cohort of the
  last #{@cohort_window_days} days that is old enough to have reached the
  horizon and not older than `retention_since` (`Catalog.overview/0`), each
  with its pool's size (`d1_cohort`, …), and payer conversion (distinct users
  with a completed purchase in the last 30 days ÷ MAU). Options: `segment:`
  (`segments/0`).
  """
  @spec summary(Date.t(), keyword()) :: map()
  def summary(today \\ Date.utc_today(), opts \\ []) do
    segment = Keyword.get(opts, :segment, :all)
    opts = [segment: segment]
    dau = dau(today, opts)
    mau = mau(today, opts)
    since = retention_since()
    first = Date.add(today, -(@cohort_window_days - 1))
    %{sizes: sizes, retained: retained} = cohort_snapshot(first, today, segment)

    pooled =
      Map.new(@horizons, fn n ->
        {n, pooled_rate(sizes, retained, n, today, since)}
      end)

    dau_7d_avg = average_dau(Date.add(today, -7), Date.add(today, -1), segment)
    payers = payers_since(Date.add(today, -29), opts)

    %{
      day: today,
      segment: segment,
      dau: dau,
      wau: wau(today, opts),
      mau: mau,
      dau_7d_avg: dau_7d_avg,
      stickiness: ratio(dau_7d_avg, mau),
      new_users_7d: sum_sizes(sizes, Date.add(today, -6), today),
      new_users_30d: sum_sizes(sizes, Date.add(today, -29), today),
      retention_since: since,
      d1: elem(pooled[1], 0),
      d1_cohort: elem(pooled[1], 1),
      d7: elem(pooled[7], 0),
      d7_cohort: elem(pooled[7], 1),
      d30: elem(pooled[30], 0),
      d30_cohort: elem(pooled[30], 1),
      payers_30d: payers,
      conversion_30d: ratio(payers, mau)
    }
  end

  @doc "`summary/0` cached for a few minutes, for the admin index."
  @spec dashboard_stats() :: map()
  def dashboard_stats do
    Cache.cached({:analytics, :dashboard_stats}, [ttl: @stats_cache_ttl_ms], fn ->
      summary()
    end)
  end

  @doc """
  Distinct users with a completed purchase since `from` (UTC date, inclusive).
  Options: `segment:` (`segments/0`).
  """
  @spec payers_since(Date.t(), keyword()) :: non_neg_integer()
  def payers_since(%Date{} = from, opts \\ []) do
    start = start_of_day(from)

    from(p in Purchase,
      where: p.status == ^PurchaseStatus.completed() and p.inserted_at >= ^start,
      select: count(p.user_id, :distinct)
    )
    |> in_segment(Keyword.get(opts, :segment, :all))
    |> Repo.one() || 0
  end

  # -- the overview's cards ---------------------------------------------------------

  @doc """
  The accounts seen in the 30 days ending on `today`, by how many of those
  days each was seen: `[%{label, min, max, users}]`, one day first. Most of
  a young game's MAU is seen once; this says how many came back at all.
  Options: `segment:` (`segments/0`).
  """
  @spec active_days(Date.t(), keyword()) :: [map()]
  def active_days(today \\ Date.utc_today(), opts \\ []) do
    from_day = Date.add(today, -29)

    per_user =
      from(a in ActivityDay,
        where: a.day >= ^from_day and a.day <= ^today,
        group_by: a.user_id,
        select: %{days: count(a.day)}
      )
      |> in_segment(Keyword.get(opts, :segment, :all))

    counts =
      from(p in subquery(per_user), group_by: p.days, select: {p.days, count()})
      |> Repo.all()
      |> Enum.map(fn {days, users} -> {to_int(days), to_int(users)} end)

    for {min, max, label} <- @active_day_buckets do
      users =
        for {days, n} <- counts, days >= min and days <= max, reduce: 0, do: (sum -> sum + n)

      %{label: label, min: min, max: max, users: users}
    end
  end

  @doc """
  Retention by sign-up week, the last #{@cohort_week_count} weeks (Monday
  first) from `retention_since` on, newest first: `[%{week, from, size,
  cells}]`, each cell `%{week: k, users, rate}` the share of the week's
  accounts seen in their own week k after sign-up (days 7k to 7k + 6 after
  their sign-up day). A cell is `rate: nil` until every account of the week
  has lived through it. Options: `segment:` (`segments/0`).
  """
  @spec weekly_cohorts(Date.t(), keyword()) :: [map()]
  def weekly_cohorts(today \\ Date.utc_today(), opts \\ []) do
    segment = Keyword.get(opts, :segment, :all)
    monday = Date.beginning_of_week(today)
    first = latest(Date.add(monday, -7 * (@cohort_week_count - 1)), retention_since())

    if Date.compare(first, today) == :gt do
      []
    else
      sizes = cohort_sizes(first, today, segment)
      retained = weekly_retained(first, today, segment)

      for i <- 0..(@cohort_week_count - 1),
          week = Date.add(monday, -7 * i),
          Date.compare(Date.add(week, 6), first) != :lt do
        from_day = latest(week, first)

        last_signup =
          if Date.compare(Date.add(week, 6), today) == :gt, do: today, else: Date.add(week, 6)

        size = sum_sizes(sizes, from_day, last_signup)

        cells =
          for k <- @cohort_week_horizons do
            users = Map.get(retained, {week, k}, 0)
            lived? = Date.compare(Date.add(last_signup, 7 * k + 6), today) == :lt
            %{week: k, users: users, rate: if(lived?, do: ratio(users, size))}
          end

        %{week: week, from: from_day, size: size, cells: cells}
      end
    end
  end

  # `{sign-up week's Monday, k} => accounts` seen in their week k, counted by
  # the database per sign-up day (an account has one), summed per week here.
  defp weekly_retained(first, today, segment) do
    start = start_of_day(first)
    stop = start_of_day(Date.add(today, 1))
    last_k = Enum.max(@cohort_week_horizons)

    seen =
      from(a in ActivityDay,
        join: u in User,
        as: :user,
        on: u.id == a.user_id,
        where: u.inserted_at >= ^start and u.inserted_at < ^stop,
        where: a.day >= ^Date.add(first, 7) and a.day <= ^today,
        select: %{
          user_id: selected_as(a.user_id, :user_id),
          signup: selected_as(fragment("date(?)", u.inserted_at), :signup),
          day: selected_as(a.day, :day)
        }
      )
      |> in_segment(segment)

    {seen_sql, params} = Repo.to_sql(:all, seen)

    sql = """
    WITH seen AS (#{seen_sql})
    SELECT s, (d - s) / 7 AS k, COUNT(DISTINCT user_id)
    FROM (SELECT user_id, #{epoch_day("signup")} AS s, #{epoch_day("day")} AS d FROM seen) days
    WHERE d - s >= 7 AND d - s < #{7 * (last_k + 1)}
    GROUP BY s, k
    """

    Repo.query!(sql, params, timeout: :infinity).rows
    |> Enum.reduce(%{}, fn [signup_n, k, users], acc ->
      week = signup_n |> to_int() |> from_epoch_n() |> Date.beginning_of_week()
      Map.update(acc, {week, to_int(k)}, to_int(users), &(&1 + to_int(users)))
    end)
  end

  @doc """
  Activation, when the host declares it (`Catalog.overview/0`'s
  `activation`): of the accounts made in the 30 days ending on `today` (from
  `retention_since` on), how many reported one of its events on the day
  they were made, and D1 for those that did and those that did not
  (cohorts before today only). `%{label, new, activated, rate,
  d1_activated, d1_activated_cohort, d1_other, d1_other_cohort}`, or nil
  with no activation declared. Options: `segment:` (`segments/0`).
  """
  @spec activation(Date.t(), keyword()) :: map() | nil
  def activation(today \\ Date.utc_today(), opts \\ []) do
    case Catalog.overview().activation do
      nil -> nil
      %{label: label, events: events} -> activation(label, events, today, opts)
    end
  end

  defp activation(label, events, today, opts) do
    first = latest(Date.add(today, -29), retention_since())
    start = start_of_day(first)
    stop = start_of_day(Date.add(today, 1))

    made =
      from(u in User,
        as: :user,
        where: u.inserted_at >= ^start and u.inserted_at < ^stop,
        select: %{
          user_id: selected_as(u.id, :user_id),
          signup: selected_as(fragment("date(?)", u.inserted_at), :signup)
        }
      )
      |> in_segment(Keyword.get(opts, :segment, :all))

    {made_sql, params} = Repo.to_sql(:all, made)
    at = length(params)
    names = Enum.map_join(1..length(events), ", ", &placeholder(at + &1))

    sql = """
    WITH made AS (#{made_sql}),
    days AS (SELECT user_id, #{epoch_day("signup")} AS s FROM made)
    SELECT
      CASE WHEN EXISTS (
        SELECT 1 FROM #{Event.__schema__(:source)} e
        WHERE e.user_id = days.user_id AND e.name IN (#{names})
          AND #{epoch_timestamp("e.inserted_at")} = days.s) THEN 1 ELSE 0 END AS activated,
      CASE WHEN EXISTS (
        SELECT 1 FROM #{ActivityDay.__schema__(:source)} a
        WHERE a.user_id = days.user_id AND #{epoch_day("a.day")} = days.s + 1) THEN 1 ELSE 0 END AS back,
      CASE WHEN days.s < #{epoch_n(today)} THEN 1 ELSE 0 END AS old_enough,
      COUNT(*)
    FROM days
    GROUP BY 1, 2, 3
    """

    totals =
      Repo.query!(sql, params ++ events, timeout: :infinity).rows
      |> Enum.reduce(%{}, fn [activated, back, old_enough, n], acc ->
        key = {to_int(activated) == 1, to_int(back) == 1, to_int(old_enough) == 1}
        Map.update(acc, key, to_int(n), &(&1 + to_int(n)))
      end)

    sum = fn match? -> for {key, n} <- totals, match?.(key), reduce: 0, do: (acc -> acc + n) end
    new = sum.(fn _key -> true end)
    activated = sum.(fn {activated, _back, _old} -> activated end)
    activated_old = sum.(fn {activated, _back, old} -> activated and old end)
    other_old = sum.(fn {activated, _back, old} -> not activated and old end)

    %{
      label: label,
      events: events,
      new: new,
      activated: activated,
      rate: ratio(activated, new),
      d1_activated: ratio(sum.(&match?({true, true, true}, &1)), activated_old),
      d1_activated_cohort: activated_old,
      d1_other: ratio(sum.(&match?({false, true, true}, &1)), other_old),
      d1_other_cohort: other_old
    }
  end

  @doc """
  The host's funnel (`Catalog.overview/0`) over the `days` days ending on
  `today`: `[%{label, source, unit, value, of_previous}]`, `unit` `:events`
  for a counter's total (a visitor counts there, each time) and `:people`
  otherwise, `of_previous` the step's share of the one before: nil first,
  and nil where the unit changes (events and people do not divide).
  """
  @spec funnel(pos_integer(), Date.t()) :: [map()]
  def funnel(days \\ 30, today \\ Date.utc_today()) do
    first = Date.add(today, -(days - 1))

    Catalog.overview().funnel
    |> Enum.map_reduce(nil, fn %{label: label, source: source}, previous ->
      value = funnel_count(source, first, today)
      unit = if match?({:counter, _}, source), do: :events, else: :people

      share =
        case previous do
          {before, ^unit} -> ratio(value, before)
          _first_or_other_unit -> nil
        end

      {%{label: label, source: source, unit: unit, value: value, of_previous: share},
       {value, unit}}
    end)
    |> elem(0)
  end

  defp funnel_count({:counter, keys}, first, today) do
    keys = List.wrap(keys)

    from(c in DailyCount,
      where: c.key in ^keys and c.day >= ^first and c.day <= ^today,
      select: sum(c.count)
    )
    |> Repo.one()
    |> to_int()
  end

  defp funnel_count(:new_accounts, first, today), do: new_users(first, today)

  defp funnel_count(:registered, first, today) do
    from(u in User,
      as: :user,
      where:
        u.inserted_at >= ^start_of_day(first) and
          u.inserted_at < ^start_of_day(Date.add(today, 1)),
      select: count(u.id)
    )
    |> Segment.restrict(:registered)
    |> Repo.one()
    |> to_int()
  end

  defp funnel_count({:entitlement, keys}, first, today) do
    keys = List.wrap(keys)

    from(e in Entitlement,
      where: e.key in ^keys,
      where:
        e.inserted_at >= ^start_of_day(first) and
          e.inserted_at < ^start_of_day(Date.add(today, 1)),
      select: count(e.user_id, :distinct)
    )
    |> Repo.one()
    |> to_int()
  end

  defp funnel_count(:payers, first, _today), do: payers_since(first)

  @doc """
  Money over the `days` days ending on `today`, for the Overview: checkouts
  opened, purchases fulfilled, checkouts refused or failed and webhook
  deliveries that failed or were refused (`Gamend.Payments.Counters`),
  revenue by currency (completed production purchases, minor units),
  payers, and the free trials when the host names their keys
  (`Catalog.overview/0`'s `trial_keys`): `%{started, running, taken, paid,
  conversion}`, `paid` the people with a completed purchase after their
  trial began.
  """
  @spec money(pos_integer(), Date.t()) :: map()
  def money(days \\ 30, today \\ Date.utc_today()) do
    first = Date.add(today, -(days - 1))
    start = start_of_day(first)
    counter = &funnel_count({:counter, &1}, first, today)

    revenue =
      from(p in Purchase,
        where:
          p.status == ^PurchaseStatus.completed() and
            p.environment == ^PaymentEnvironment.production(),
        where: p.inserted_at >= ^start and not is_nil(p.amount),
        group_by: p.currency,
        select: {p.currency, sum(p.amount)}
      )
      |> Repo.all()
      |> Enum.map(fn {currency, amount} -> {currency, to_int(amount)} end)

    %{
      checkouts_opened: counter.("payments.checkout.opened"),
      purchases: counter.("payments.purchase.fulfilled"),
      checkouts_refused: counter.(["payments.checkout.refused", "payments.checkout.failed"]),
      webhook_problems:
        counter.(["payments.webhook.result:failed", "payments.webhook.result:refused"]),
      revenue: revenue,
      payers: payers_since(first),
      trials: trials(Catalog.overview().trial_keys, start)
    }
  end

  defp trials([], _start), do: nil

  defp trials(keys, start) do
    now = DateTime.utc_now()
    people = &(&1 |> select([e], count(e.user_id, :distinct)) |> Repo.one() |> to_int())
    base = from(e in Entitlement, where: e.key in ^keys)
    taken = people.(base)

    paid =
      people.(
        from(e in base,
          join: p in Purchase,
          on:
            p.user_id == e.user_id and p.status == ^PurchaseStatus.completed() and
              p.inserted_at >= e.inserted_at
        )
      )

    %{
      started: people.(where(base, [e], e.inserted_at >= ^start)),
      running:
        people.(
          where(
            base,
            [e],
            e.status == ^EntitlementStatus.active() and is_nil(e.revoked_at) and
              (is_nil(e.expires_at) or e.expires_at > ^now)
          )
        ),
      taken: taken,
      paid: paid,
      conversion: ratio(paid, taken)
    }
  end

  # A positional parameter after `n - 1` others: `$n` on Postgres, `?` on
  # SQLite (whose placeholders count in order).
  defp placeholder(n), do: if(postgres?(), do: "$#{n}", else: "?")

  # A timestamp column's UTC day as days since 1970-01-01.
  defp epoch_timestamp(column) do
    if postgres?(),
      do: "(CAST(#{column} AS date) - DATE '1970-01-01')",
      else: "CAST(julianday(#{column}) - 2440587.5 AS INTEGER)"
  end

  # Accounts made per UTC day in `first..today`.
  defp cohort_sizes(first, today, segment) do
    start = start_of_day(first)
    stop = start_of_day(Date.add(today, 1))

    from(u in User,
      as: :user,
      where: u.inserted_at >= ^start and u.inserted_at < ^stop,
      group_by: fragment("date(?)", u.inserted_at),
      select: {fragment("date(?)", u.inserted_at), count(u.id)}
    )
    |> in_segment(segment)
    |> Repo.all()
    |> Map.new(fn {day, n} -> {to_date(day), n} end)
  end

  # Cohort sizes (users registered per UTC day) and retained counts
  # (`{cohort_day, seen_day} => users`) for cohorts registered in `first..today`.
  # One grouped query each; the join output is at most days² rows, so the
  # per-horizon lookups happen in Elixir rather than as N more queries.
  defp cohort_snapshot(first, today, segment) do
    start = start_of_day(first)
    stop = start_of_day(Date.add(today, 1))

    sizes = cohort_sizes(first, today, segment)

    retained =
      from(a in ActivityDay,
        join: u in User,
        as: :user,
        on: u.id == a.user_id,
        where: u.inserted_at >= ^start and u.inserted_at < ^stop,
        where: a.day >= ^first and a.day <= ^today,
        group_by: [fragment("date(?)", u.inserted_at), a.day],
        select: {fragment("date(?)", u.inserted_at), a.day, count(a.user_id)}
      )
      |> in_segment(segment)
      |> Repo.all()
      |> Map.new(fn {cohort, day, n} -> {{to_date(cohort), to_date(day)}, n} end)

    %{sizes: sizes, retained: retained}
  end

  # Retention of one cohort at horizon `n`: nil until day+n has happened.
  defp cohort_rate(_retained, _day, _n, 0, _today), do: nil

  defp cohort_rate(retained, day, n, size, today) do
    target = Date.add(day, n)

    if Date.compare(target, today) == :gt,
      do: nil,
      else: Map.get(retained, {day, target}, 0) / size
  end

  # Sum of retained over sum of cohort sizes, `{rate, accounts pooled}`,
  # cohorts old enough and counted in full only. Pooling (rather than
  # averaging per-cohort rates) so a day with two sign-ups does not weigh as
  # much as a day with two hundred.
  defp pooled_rate(sizes, retained, n, today, since) do
    latest = Date.add(today, -n)

    {kept, total} =
      Enum.reduce(sizes, {0, 0}, fn {day, size}, {kept, total} ->
        if Date.compare(day, latest) == :gt or undercounted?(day, since),
          do: {kept, total},
          else: {kept + Map.get(retained, {day, Date.add(day, n)}, 0), total + size}
      end)

    {ratio(kept, total), total}
  end

  # A cohort from before the activity it is judged by was counted in full
  # (`Catalog.overview/0`'s `retention_since`) reads low: left out.
  defp undercounted?(_day, nil), do: false
  defp undercounted?(day, since), do: Date.compare(day, since) == :lt

  defp retention_since, do: Catalog.overview().retention_since

  # The later of two days; nil is no bound.
  defp latest(day, nil), do: day
  defp latest(day, other), do: if(Date.compare(other, day) == :gt, do: other, else: day)

  # The average of each day's active users over `from..to`: one row per user
  # per day, so the rows over the days.
  defp average_dau(from, to, segment) do
    rows =
      from(a in ActivityDay, where: a.day >= ^from and a.day <= ^to, select: count(a.user_id))
      |> in_segment(segment)
      |> Repo.one()

    to_int(rows) / (Date.diff(to, from) + 1)
  end

  defp sum_sizes(sizes, from, to) do
    sizes
    |> Enum.filter(fn {day, _} ->
      Date.compare(day, from) != :lt and Date.compare(day, to) != :gt
    end)
    |> Enum.map(fn {_, n} -> n end)
    |> Enum.sum()
  end

  defp ratio(_num, 0), do: nil
  defp ratio(num, den), do: num / den

  defp start_of_day(%Date{} = day), do: DateTime.new!(day, ~T[00:00:00], "Etc/UTC")

  # `date(...)` comes back as a Date on Postgres and as "YYYY-MM-DD" on SQLite.
  defp to_date(%Date{} = date), do: date
  defp to_date(text) when is_binary(text), do: Date.from_iso8601!(text)

  # `sum(bigint)` is a Decimal on Postgres and an integer on SQLite.
  defp to_int(nil), do: 0
  defp to_int(n) when is_integer(n), do: n
  defp to_int(%Decimal{} = d), do: Decimal.to_integer(d)
  defp to_int(f) when is_float(f), do: round(f)
end
