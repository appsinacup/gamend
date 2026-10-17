defmodule Gamend.Analytics do
  @moduledoc ~S"""
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


  **Note:** This is an SDK stub. Calling these functions will raise an error.
  The actual implementation runs on the Gamend.
  """

  @type rate() :: float() | nil

  @doc ~S"""
    Distinct users seen on any day in `from..to` (inclusive, UTC dates).
    Options: `segment:` (`segments/0`).
    
  """
  @spec active_users(Date.t(), Date.t(), keyword()) :: non_neg_integer()
  def active_users(_from, _to, _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Analytics.active_users/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Adds `n` to the counter `key` for the UTC day of `now`. Gathered by
    `Gamend.Analytics.Buffer` and written as one upsert per `(key, day)` at the
    next flush (within `flush_ms`, 10 s); written through at once where the
    buffer is off (tests) or not running. Cheap enough for any path.
    
    Keys are dotted, game-owned strings up to 128 chars;
    put a dimension after a colon (`"level.started.lang:ja"`) so `counts/2`
    can pull a whole family by prefix and `families/3` can group it. Never
    raises; a bad key is dropped with a warning.
    
  """
  @spec count(String.t(), pos_integer(), DateTime.t()) :: :ok
  def count(_key, _n \\ 1, _now \\ DateTime.utc_now()) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Analytics.count/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Totals of `counts/3` per key over the window, largest first.
  """
  @spec count_totals(String.t(), pos_integer(), Date.t()) :: [{String.t(), integer()}]
  def count_totals(_key, _days \\ 7, _today \\ Date.utc_today()) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Analytics.count_totals/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Per-day values of one counter or a prefix family over the last `days` days
    ending on `today`, as `%{key => %{Date => count}}`. `key` may end in `*` to
    match a prefix (`"level.started.lang:*"`).
    
  """
  @spec counts(String.t(), pos_integer(), Date.t()) :: %{
          required(String.t()) => %{required(Date.t()) => integer()}
        }
  def counts(_key, _days \\ 7, _today \\ Date.utc_today()) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Analytics.counts/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    One row per UTC day for the last `days` days ending on `today`, oldest
    first: `%{day, active, wau, mau, stickiness, new_users, d1, d7, d30}`.
    `wau` / `mau` are the distinct users of the 7 / 30 days ending on that day,
    and `stickiness` is `active ÷ mau` of that day, so each row reads as the
    headline would have on it. A retention rate is `nil` when the cohort is
    empty or the horizon day has not happened yet. Options: `segment:`
    (`segments/0`).
    
  """
  @spec daily_series(pos_integer(), Date.t(), keyword()) :: [map()]
  def daily_series(_days \\ 30, _today \\ Date.utc_today(), _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Analytics.daily_series/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    `summary/0` cached for a few minutes, for the admin index.
  """
  @spec dashboard_stats() :: map()
  def dashboard_stats() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        %{}

      _ ->
        raise "Gamend.Analytics.dashboard_stats/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Daily active users on `day` (default: today, UTC).
  """
  @spec dau(
          Date.t(),
          keyword()
        ) :: non_neg_integer()
  def dau(_day \\ Date.utc_today(), _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Analytics.dau/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Currency granted and spent per UTC day per ledger `reason` over the last
    `days` days: `[%{day, currency, reason, granted, spent, entries}]`, newest
    first. `granted`/`spent` are positive integers (spent is the absolute
    value of negative deltas). Options: `:currency` to filter.
    
  """
  @spec economy_flow(
          pos_integer(),
          keyword()
        ) :: [map()]
  def economy_flow(_days \\ 7, _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Analytics.economy_flow/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    `economy_flow/2` collapsed over the window: one row per `{currency,
    reason}` with `granted`, `spent`, `net`, sorted by absolute net.
    
  """
  @spec economy_totals(
          pos_integer(),
          keyword()
        ) :: [map()]
  def economy_totals(_days \\ 7, _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Analytics.economy_totals/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    The counters of the last `days` days grouped by family, largest first:
    `[%{key, total, by_day, dims}]`, where `key` is the bare counter
    (`"web.game.finished"`), `by_day` its `%{Date => n}`, and `dims` every
    dimension written under it — `%{"lang" => [{"ro", 120}, {"es", 80}]}` from
    the keys `web.game.finished.lang:ro` and `…lang:es` — each list largest
    first. `prefix` as in `counts/3` (`"web.*"`, or one key).
    
  """
  @spec families(String.t(), pos_integer(), Date.t()) :: [map()]
  def families(_prefix \\ "*", _days \\ 7, _today \\ Date.utc_today()) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Analytics.families/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Every event name of the last 60 days as a feature,
    with what `summary/1` says of the whole site: `[%{name, dau, wau, mau,
    stickiness, events_7d, new_7d, new_30d, d1, d7, d30}]`, largest MAU first.
    
    Active = at least one event of that name that day (only an account's
    events are kept as rows). "New" = first event of the name in the window (a
    player back after 60 quiet days reads as new). D1 / D7
    / D30 are pooled over the first-day cohorts old enough to have reached the
    horizon, as `summary/1` pools sign-up cohorts.
    
    Options: `segment:` (`segments/0`, default `:all`).
    
  """
  @spec feature_summary(
          Date.t(),
          keyword()
        ) :: [map()]
  def feature_summary(_today \\ Date.utc_today(), _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Analytics.feature_summary/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Writes everything `Gamend.Analytics.Buffer` has gathered, now, in the caller's process.
  """
  @spec flush() :: {non_neg_integer(), non_neg_integer()}
  def flush() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Analytics.flush/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Monthly active users: distinct users seen in the 30 days ending on `day`.
  """
  @spec mau(
          Date.t(),
          keyword()
        ) :: non_neg_integer()
  def mau(_day \\ Date.utc_today(), _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Analytics.mau/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Accounts created on any UTC day in `from..to` (inclusive).
  """
  @spec new_users(Date.t(), Date.t()) :: non_neg_integer()
  def new_users(_from, _to) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Analytics.new_users/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Distinct users with a completed purchase since `from` (UTC date, inclusive).
    Options: `segment:` (`segments/0`).
    
  """
  @spec payers_since(
          Date.t(),
          keyword()
        ) :: non_neg_integer()
  def payers_since(_from, _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Analytics.payers_since/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    One feature broken down by one of its dimensions over the last `days`
    days: `[%{value, people, events}]`, people = distinct signed-in users,
    largest first; a row without the dimension is `"none"`. The dimensions a
    feature has are the keys of its family's `dims` (`families/3`). Options:
    `segment:` (`segments/0`).
    
        people_by_dimension("web.game.started", "game")
        #=> [%{value: "hangman", people: 41, events: 212}, …]
    
  """
  @spec people_by_dimension(String.t(), String.t(), pos_integer(), Date.t(), keyword()) :: [map()]
  def people_by_dimension(_name, _dim, _days \\ 30, _today \\ Date.utc_today(), _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Analytics.people_by_dimension/5 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    The last `limit` events, newest first.
  """
  @spec recent_events(pos_integer()) :: [Gamend.Analytics.Event.t()]
  def recent_events(_limit \\ 50) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Analytics.recent_events/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Records that `user_id` was seen on the UTC day of `now`. Idempotent; the
    common case (already recorded today) is a single cache read. Never raises —
    a missing user (deleted mid-request) is a silent no-op, like the
    `last_seen_at` touch this rides along with.
    
  """
  @spec record_activity(Ecto.UUID.t(), DateTime.t()) :: :ok
  def record_activity(_user_id, _now \\ DateTime.utc_now()) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Analytics.record_activity/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    A segment from a request parameter; anything unknown is `:all`.
  """
  @spec segment(term()) :: Gamend.Analytics.Segment.t()
  def segment(_param) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Analytics.segment/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Every segment the people numbers split by (`Gamend.Analytics.Segment`).
  """
  @spec segments() :: [Gamend.Analytics.Segment.t()]
  def segments() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Analytics.segments/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
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
  def snapshot() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        %{}

      _ ->
        raise "Gamend.Analytics.snapshot/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Headline numbers as of `today`: DAU / WAU / MAU, stickiness (DAU ÷ MAU),
    new users in the last 7 and 30 days, D1 / D7 / D30 pooled over every cohort
    of the last 60 days that is old enough to have reached
    the horizon, and payer conversion (distinct users with a completed purchase
    in the last 30 days ÷ MAU). Options: `segment:` (`segments/0`).
    
  """
  @spec summary(
          Date.t(),
          keyword()
        ) :: map()
  def summary(_today \\ Date.utc_today(), _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        %{}

      _ ->
        raise "Gamend.Analytics.summary/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Records that something happened: `name` is counted for the day (`count/3`),
    once more per DIMENSION (`name.lang:ro`), and, when it has a user, the
    whole event — `dims`, `user_id`, the moment — is kept as a row in
    `analytics_events`. One call, so a counter and its event can never
    disagree.
    
    An event with no user (a visitor, a webhook) is counted and never kept: a
    row is there to say WHO, and a visitor has no id to say it with. On a site
    crawlers read, they were nearly every row.
    
    `name` is dotted `[a-z0-9_]`, up to 64 chars (`"web.game.finished"`).
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
  def track(_name, _dims \\ %{}, _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Analytics.track/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Weekly active users: distinct users seen in the 7 days ending on `day`.
  """
  @spec wau(
          Date.t(),
          keyword()
        ) :: non_neg_integer()
  def wau(_day \\ Date.utc_today(), _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Analytics.wau/2 is a stub - only available at runtime on Gamend"
    end
  end
end
