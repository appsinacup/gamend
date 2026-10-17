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

  require Logger

  alias Gamend.Accounts
  alias Gamend.Accounts.User
  alias Gamend.Analytics.ActivityDay
  alias Gamend.Analytics.Buffer
  alias Gamend.Analytics.DailyCount
  alias Gamend.Analytics.Event
  alias Gamend.Analytics.Segment
  alias Gamend.Cache
  alias Gamend.Economy.LedgerEntry
  alias Gamend.Payments.Purchase
  alias Gamend.Repo

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
      Logger.warning("analytics: #{length(rows)} events not written: #{Exception.message(error)}")
      :error
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
    start = start_of_day(first)
    stop = start_of_day(Date.add(today, 1))

    presence =
      from(e in Event,
        where: not is_nil(e.user_id) and e.inserted_at >= ^start and e.inserted_at < ^stop,
        group_by: [e.name, fragment("date(?)", e.inserted_at), e.user_id],
        select: {e.name, fragment("date(?)", e.inserted_at), e.user_id}
      )
      |> in_segment(segment)
      |> Repo.all()
      |> Enum.group_by(&elem(&1, 0), fn {_name, day, user} -> {to_date(day), user} end)

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

    names =
      presence |> Map.keys() |> MapSet.new() |> MapSet.union(MapSet.new(Map.keys(events_7d)))

    names
    |> Enum.map(fn name ->
      feature_row(name, Map.get(presence, name, []), Map.get(events_7d, name, 0), today)
    end)
    |> Enum.sort_by(&{-&1.mau, -&1.events_7d, &1.name})
  end

  # `seen` is `[{day, user_id}]`, one per user per day.
  defp feature_row(name, seen, events_7d, today) do
    week = Date.add(today, -6)
    month = Date.add(today, -29)

    users_since = fn since ->
      seen
      |> Enum.filter(fn {day, _} -> Date.compare(day, since) != :lt end)
      |> Enum.map(&elem(&1, 1))
      |> Enum.uniq()
      |> length()
    end

    dau = users_since.(today)
    mau = users_since.(month)

    firsts =
      seen
      |> Enum.group_by(&elem(&1, 1), &elem(&1, 0))
      |> Map.new(fn {user, days} -> {user, Enum.min_by(days, &Date.to_erl/1)} end)

    present = MapSet.new(seen)

    retained = fn n ->
      {kept, total} =
        Enum.reduce(firsts, {0, 0}, fn {user, day}, {kept, total} ->
          horizon = Date.add(day, n)

          cond do
            Date.compare(horizon, today) == :gt -> {kept, total}
            MapSet.member?(present, {horizon, user}) -> {kept + 1, total + 1}
            true -> {kept, total + 1}
          end
        end)

      ratio(kept, total)
    end

    new_since = fn since ->
      Enum.count(firsts, fn {_user, day} -> Date.compare(day, since) != :lt end)
    end

    %{
      name: name,
      dau: dau,
      wau: users_since.(week),
      mau: mau,
      stickiness: ratio(dau, mau),
      events_7d: events_7d,
      new_7d: new_since.(week),
      new_30d: new_since.(month),
      d1: retained.(1),
      d7: retained.(7),
      d30: retained.(30)
    }
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
      %{row | value: if(is_nil(row.value), do: "none", else: to_string(row.value))}
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
  first: `%{day, active, wau, mau, stickiness, new_users, d1, d7, d30}`.
  `wau` / `mau` are the distinct users of the 7 / 30 days ending on that day,
  and `stickiness` is `active ÷ mau` of that day, so each row reads as the
  headline would have on it. A retention rate is `nil` when the cohort is
  empty or the horizon day has not happened yet. Options: `segment:`
  (`segments/0`).
  """
  @spec daily_series(pos_integer(), Date.t(), keyword()) :: [map()]
  def daily_series(days \\ @series_days, today \\ Date.utc_today(), opts \\ [])
      when is_integer(days) and days > 0 do
    segment = Keyword.get(opts, :segment, :all)
    first = Date.add(today, -(days - 1))
    rolling = rolling_active(first, today, segment)
    %{sizes: sizes, retained: retained} = cohort_snapshot(first, today, segment)

    for offset <- 0..(days - 1) do
      day = Date.add(first, offset)
      size = Map.get(sizes, day, 0)
      %{active: active, wau: wau, mau: mau} = Map.fetch!(rolling, day)

      %{
        day: day,
        active: active,
        wau: wau,
        mau: mau,
        stickiness: ratio(active, mau),
        new_users: size,
        d1: cohort_rate(retained, day, 1, size, today),
        d7: cohort_rate(retained, day, 7, size, today),
        d30: cohort_rate(retained, day, 30, size, today)
      }
    end
  end

  # `%{day => %{active, wau, mau}}` for every day in `first..today`: each
  # user's days seen, spread over the 7 and 30 days they count in. One read
  # of the days that can count (30 before `first` on), so a 90-day table is
  # one query, not 180.
  defp rolling_active(first, today, segment) do
    from_day = Date.add(first, -29)
    first_n = Date.to_gregorian_days(first)
    last_n = Date.to_gregorian_days(today)

    seen =
      from(a in ActivityDay,
        where: a.day >= ^from_day and a.day <= ^today,
        select: {a.user_id, a.day}
      )
      |> in_segment(segment)
      |> Repo.all()
      |> Enum.group_by(&elem(&1, 0), &(&1 |> elem(1) |> to_date() |> Date.to_gregorian_days()))

    empty = Map.new(first_n..last_n, &{&1, {0, 0, 0}})

    seen
    |> Enum.reduce(empty, fn {_user, days}, acc -> add_user_days(acc, days, first_n, last_n) end)
    |> Map.new(fn {n, {d, w, m}} ->
      {Date.from_gregorian_days(n), %{active: d, wau: w, mau: m}}
    end)
  end

  # One user's days seen, added to every `{active, wau, mau}` they count in.
  defp add_user_days(acc, days, first_n, last_n) do
    week = covered(days, 7, first_n, last_n)
    month = covered(days, 30, first_n, last_n)
    seen = MapSet.new(days)

    Enum.reduce(month, acc, fn n, acc ->
      Map.update!(acc, n, fn {d, w, m} ->
        {d + one_if(MapSet.member?(seen, n)), w + one_if(MapSet.member?(week, n)), m + 1}
      end)
    end)
  end

  defp one_if(true), do: 1
  defp one_if(false), do: 0

  # The days in `first_n..last_n` a user seen on `days` counts in, for a
  # window of `width` days ending on each.
  defp covered(days, width, first_n, last_n) do
    for d <- days, n <- max(d, first_n)..min(d + width - 1, last_n)//1, into: MapSet.new(), do: n
  end

  @doc """
  Headline numbers as of `today`: DAU / WAU / MAU, stickiness (DAU ÷ MAU),
  new users in the last 7 and 30 days, D1 / D7 / D30 pooled over every cohort
  of the last #{@cohort_window_days} days that is old enough to have reached
  the horizon, and payer conversion (distinct users with a completed purchase
  in the last 30 days ÷ MAU). Options: `segment:` (`segments/0`).
  """
  @spec summary(Date.t(), keyword()) :: map()
  def summary(today \\ Date.utc_today(), opts \\ []) do
    segment = Keyword.get(opts, :segment, :all)
    opts = [segment: segment]
    dau = dau(today, opts)
    mau = mau(today, opts)
    first = Date.add(today, -(@cohort_window_days - 1))
    %{sizes: sizes, retained: retained} = cohort_snapshot(first, today, segment)

    pooled =
      Map.new(@horizons, fn n ->
        {n, pooled_rate(sizes, retained, n, today)}
      end)

    payers = payers_since(Date.add(today, -29), opts)

    %{
      day: today,
      segment: segment,
      dau: dau,
      wau: wau(today, opts),
      mau: mau,
      stickiness: ratio(dau, mau),
      new_users_7d: sum_sizes(sizes, Date.add(today, -6), today),
      new_users_30d: sum_sizes(sizes, Date.add(today, -29), today),
      d1: pooled[1],
      d7: pooled[7],
      d30: pooled[30],
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
      where: p.status == "completed" and p.inserted_at >= ^start,
      select: count(p.user_id, :distinct)
    )
    |> in_segment(Keyword.get(opts, :segment, :all))
    |> Repo.one() || 0
  end

  # Cohort sizes (users registered per UTC day) and retained counts
  # (`{cohort_day, seen_day} => users`) for cohorts registered in `first..today`.
  # One grouped query each; the join output is at most days² rows, so the
  # per-horizon lookups happen in Elixir rather than as N more queries.
  defp cohort_snapshot(first, today, segment) do
    start = start_of_day(first)
    stop = start_of_day(Date.add(today, 1))

    sizes =
      from(u in User,
        as: :user,
        where: u.inserted_at >= ^start and u.inserted_at < ^stop,
        group_by: fragment("date(?)", u.inserted_at),
        select: {fragment("date(?)", u.inserted_at), count(u.id)}
      )
      |> in_segment(segment)
      |> Repo.all()
      |> Map.new(fn {day, n} -> {to_date(day), n} end)

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

  # Sum of retained over sum of cohort sizes, cohorts old enough only. Pooling
  # (rather than averaging per-cohort rates) so a day with two sign-ups does
  # not weigh as much as a day with two hundred.
  defp pooled_rate(sizes, retained, n, today) do
    latest = Date.add(today, -n)

    {kept, total} =
      Enum.reduce(sizes, {0, 0}, fn {day, size}, {kept, total} ->
        if Date.compare(day, latest) == :gt,
          do: {kept, total},
          else: {kept + Map.get(retained, {day, Date.add(day, n)}, 0), total + size}
      end)

    ratio(kept, total)
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
