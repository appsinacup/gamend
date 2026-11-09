defmodule Gamend.DemoSeed do
  @moduledoc """
  Fills the database with enough demo data to exercise pagination and the
  list/detail pages at realistic sizes.

  Everything is namespaced with a `demo-seed` prefix so `--clean` can remove it
  again without touching real data.

  ## Usage

  `mix demo.seed` in a checkout, `gamend demo.seed` from a release, with the
  same arguments:

      mix demo.seed                       # all sets, 1000 rows each
      mix demo.seed --count 250           # smaller run
      mix demo.seed --only leaderboard    # one set (comma-separated)
      mix demo.seed --only group,tournament
      mix demo.seed --clean               # remove everything this task created

  ## Sets

    * `leaderboard` — a leaderboard with N scored records
    * `group`       — a public group with N members
    * `tournament`  — a tournament with N registered entries, still open
    * `result` — finished and open plays for `/admin/results`, a dozen per
      player for the first 12 players, regardless of `--count` (this set is
      about having something to read, not volume)
    * `quest` — a daily, an auto-claim achievement, a chained follow-up and a
      twelve-member group that lists as one card, with per-user progress in
      every state (including claimable rows), and a code-only quest with a
      page of generated codes and the shared code `SPRING-GIFT`
    * `ready_check` — one check per seeded lobby in every outcome (open,
      passed, timed out, declined), also capped at 12
    * `chat_moderation` — a blocklist across every severity and match mode, a
      report queue deep enough to page through (every status, some filter-filed,
      some resolved) and mutes in every scope, including expired ones

  The volume sets, one per admin list, sized from N:

    * `kv` — a profile row per player plus N/10 global keys (`/admin/kv`)
    * `notification` — one per player, and N/10 more for the first player
      (`/admin/notifications`, `/notifications`)
    * `analytics` — 2N events over 90 days, a few activity days per player,
      daily counters for a year (`/admin/analytics/*`)
    * `economy` — a wallet per player, 2N ledger entries, N/100 of them the
      first player's (`/admin/economy`)
    * `payment` — N/10 purchases, each with its entitlement (`/admin/payments`)
    * `report` — N/10 page reports over 500 pages (`/admin/reports`)
    * `friend` — a friendship per player, N/100 friends for the first player
      (`/admin/friends`)
    * `session` — a session token per player (`/admin/sessions`)
    * `lobby` — N/10 lobbies (`/admin/lobbies`)
    * `ban` — N/100 account and IP bans (`/admin/bans`)
    * `inventory` — two items per player (`/admin/economy`)

  The first player is the heavy one: `mix demo.bench` signs in as them for the
  player pages, so their lists are the long ones.

  The `result` set goes through `Gamend.Results`, so what you see is shaped
  exactly like a game's writes, then moves each play back in time so the list
  spans the last weeks.

  Seeded runs keep their lobby row so `--clean` can find them again. Real
  completed runs outlive theirs, since a lobby is deleted when its last member
  leaves.

  All sets share one pool of N anonymous device accounts, so the same players
  appear across them (as they would in a real deployment).

  Rows are inserted in bulk rather than through the contexts: this is about
  volume, not about exercising business rules, and 1000 individual writes on
  SQLite is slow. Rows are streamed in statements of up to 30,000 parameters,
  four at a time on Postgres, so a million rows a set fits in memory and takes
  seconds per set. The cache is flushed afterwards so pages read the new rows,
  and Postgres re-analyses the tables so the planner sees their new size.
  """

  import Ecto.Query

  alias Gamend.Accounts.User
  alias Gamend.Accounts.UserToken
  alias Gamend.Analytics.ActivityDay
  alias Gamend.Analytics.DailyCount
  alias Gamend.Analytics.Event, as: AnalyticsEvent
  alias Gamend.Bans.Ban
  alias Gamend.Chat.FilterWord
  alias Gamend.Chat.Message
  alias Gamend.Chat.Moderation
  alias Gamend.Chat.Moderation.Normalizer
  alias Gamend.Chat.Report
  alias Gamend.Economy.LedgerEntry
  alias Gamend.Economy.Wallet
  alias Gamend.Friends.Friendship
  alias Gamend.Groups.Group
  alias Gamend.Groups.GroupMember
  alias Gamend.Inventory.Item, as: InventoryItem
  alias Gamend.KV.Entry, as: KVEntry
  alias Gamend.Leaderboards.Leaderboard
  alias Gamend.Leaderboards.Record
  alias Gamend.Lobbies.Lobby
  alias Gamend.Notifications.Notification
  alias Gamend.Parties.Party
  alias Gamend.Payments.Entitlement
  alias Gamend.Payments.Purchase
  alias Gamend.Push.PushToken
  alias Gamend.Quests.Quest
  alias Gamend.Quests.QuestProgress
  alias Gamend.ReadyChecks.Check, as: ReadyCheck
  alias Gamend.ReadyChecks.Participant, as: ReadyCheckParticipant
  alias Gamend.Repo
  alias Gamend.Reports.Report, as: PageReport
  alias Gamend.Tournaments.Entry
  alias Gamend.Tournaments.Tournament
  alias Gamend.UUIDv7

  require Gamend.Bans.BanScope, as: BanScope
  require Gamend.Chat.ChatReportStatus, as: ChatReportStatus
  require Gamend.Chat.ChatType, as: ChatType
  require Gamend.ReadyChecks.CheckReason, as: CheckReason
  require Gamend.Tournaments.DeadlinePolicy, as: DeadlinePolicy
  require Gamend.Friends.FriendshipStatus, as: FriendshipStatus
  require Gamend.Groups.GroupRole, as: GroupRole
  require Gamend.Groups.GroupType, as: GroupType
  require Gamend.Quests.PeriodKey, as: PeriodKey
  require Gamend.Quests.QuestReset, as: QuestReset
  require Gamend.Quests.QuestStatus, as: QuestStatus
  require Gamend.Reports.ReportStatus, as: ReportStatus
  require Gamend.Quests.ReportedEvent, as: ReportedEvent
  require Gamend.Quests.RewardType, as: RewardType
  require Gamend.Tournaments.TournamentState, as: TournamentState
  require Gamend.Payments.PaymentEnvironment, as: PaymentEnvironment
  require Gamend.Payments.ProviderId, as: ProviderId
  require Gamend.Payments.PurchaseStatus, as: PurchaseStatus
  require Gamend.Push.Platform, as: Platform
  require Gamend.Push.PushProvider, as: PushProvider
  require Gamend.Lobbies.LobbyState, as: LobbyState
  require Gamend.LocaleCode, as: LocaleCode
  require Gamend.ReadyChecks.CheckKind, as: CheckKind
  require Gamend.ReadyChecks.CheckStatus, as: CheckStatus
  require Gamend.ReadyChecks.ParticipantState, as: ParticipantState
  require Gamend.Reports.ReportSource, as: ReportSource

  @answer "answer"

  @ready "ready"

  @demo_langs ~w(fr es de ro)
  @session "session"
  @page "page"
  @guest "guest"
  @account "account"
  @gold "gold"
  @inventory "inventory"
  @ban "ban"
  @lobby "lobby"
  @friend "friend"
  @report "report"
  @payment "payment"
  @notification "notification"
  @kv "kv"
  @push "push"
  @quest "quest"
  @result "result"
  @tournament "tournament"
  @group "group"
  @leaderboard "leaderboard"

  @prefix "demo-seed"
  @leaderboard_slug "demo_seed_scores"
  @season_slug "demo_seed_monthly"
  @group_title "Demo Seed Group"
  @tournament_slug "demo-seed-cup"
  @quest_key_prefix "demo-seed-"
  @default_count 1000
  # One statement's bind parameters: under SQLite's 32,766 and Postgres's 65,535.
  @max_params 30_000
  @all_sets ~w(leaderboard group tournament result quest push ready_check chat_moderation
               kv notification analytics economy payment report friend session lobby ban inventory)
  @year_sec 365 * 86_400
  @lobby_title_prefix "Demo Seed Run"
  @max_runs 12
  @chat_lobby_title "#{@lobby_title_prefix} Chat"
  @chat_room_types ~w(group lobby party)
  @min_reports 48
  @max_mutes 24

  # A spread over both match modes, all three severities and the provenance tag
  # (nil is a hand-added word). Nothing here overlaps priv/chat_filter/en.txt, so
  # importing the bundled list on top of a seeded database still works, and no
  # word carries a doubled letter — the normalizer collapses those, and a word
  # displayed as "bosting" reads like a typo in the admin list.
  @filter_words [
    {"idiot", "block", "substring", nil},
    {"moron", "block", "substring", "en"},
    {"scumbag", "block", "exact", "en"},
    {"kys", "block", "exact", nil},
    {"arschloch", "block", "substring", "de"},
    {"salaud", "block", "substring", "fr"},
    {"imbecil", "block", "substring", "es"},
    {"damn", "mask", "substring", nil},
    {"crap", "mask", "substring", nil},
    {"numpty", "mask", "substring", "en"},
    {"plonker", "mask", "exact", "en"},
    {"mist", "mask", "exact", "de"},
    {"merde", "mask", "substring", "fr"},
    {"trash", "flag", "substring", nil},
    {"scam", "flag", "substring", nil},
    {"hacker", "flag", "substring", nil},
    {"cheater", "flag", "substring", "en"},
    {"smurf", "flag", "exact", nil},
    {"rmt", "flag", "exact", "en"},
    {"goldfarm", "flag", "substring", nil},
    {"gamekeys", "flag", "substring", nil},
    {"buy gold", "flag", "substring", "en"}
  ]

  # Reported message and the reason it was reported for. The last two are
  # benign: a queue with no bogus reports in it never shows why `dismissed`
  # exists.
  @chat_lines [
    {"you are the worst teammate I have had all week", "Harassment"},
    {"learn to play before you queue ranked", "Harassment"},
    {"stop stealing my objectives", "Griefing"},
    {"report him, he threw the game on purpose", "Griefing"},
    {"add me, I sell accounts cheap", "Real-money trading"},
    {"join my stream, the link is in my profile", "Spam or advertising"},
    {"nobody from your region should be allowed to queue", "Hate speech"},
    {"I am a moderator, send me your login to verify", "Impersonation"},
    {"gg wp, close one", "Harassment"},
    {"my ping is awful tonight", "Spam or advertising"}
  ]

  # Each line is paired with the `flag` word it trips, which is what the filter
  # puts in the reason of the report it files.
  @flagged_lines [
    {"buy gold cheap, first ten buyers get a bonus", "buy gold"},
    {"this smurf ruins every lobby", "smurf"},
    {"you are trash, uninstall the game", "trash"},
    {"total scam, the drop rates are rigged", "scam"},
    {"goldfarm service, message me for prices", "goldfarm"}
  ]

  @doc """
  Seeds (or with `--clean` removes) the demo data. Takes the same arguments as
  `mix demo.seed`; the application must already be running. Raises
  `ArgumentError` on an unknown set.
  """
  @spec run([String.t()]) :: :ok
  def run(args) do
    {opts, _rest, _} =
      OptionParser.parse(args, strict: [count: :integer, only: :string, clean: :boolean])

    if opts[:clean] do
      clean()
    else
      count = opts[:count] || @default_count
      sets = parse_sets(opts[:only])

      info("seeding #{count} rows per set: #{Enum.join(sets, ", ")}")
      users = ensure_users(count)

      Enum.each(sets, fn
        @leaderboard -> seed_leaderboard(users)
        @group -> seed_group(users)
        @tournament -> seed_tournament(users)
        @result -> seed_results(users)
        @quest -> seed_quests(users)
        @push -> seed_push_tokens(users)
        "ready_check" -> seed_ready_checks(users)
        "chat_moderation" -> seed_chat_moderation(users)
        @kv -> seed_kv(users)
        @notification -> seed_notifications(users)
        "analytics" -> seed_analytics(users)
        "economy" -> seed_economy(users)
        @payment -> seed_payments(users)
        @report -> seed_reports(users)
        @friend -> seed_friends(users)
        @session -> seed_sessions(users)
        @lobby -> seed_lobbies(users)
        @ban -> seed_bans(users)
        @inventory -> seed_inventory(users)
      end)

      analyze()
      Gamend.Cache.delete_all()
      info("done — run `demo.seed --clean` to remove it again")
    end

    :ok
  end

  @doc """
  What `mix demo.bench` signs in with and links to: a session token for an
  admin (created on first call as `demo-seed-admin`, removed by `--clean`)
  and one for the heavy player (the first, whose lists are the long ones),
  plus the ids of the seeded pages. Raises `ArgumentError` before a seed.
  """
  @spec bench_context() :: %{admin_token: binary(), player_token: binary(), params: map()}
  def bench_context do
    player =
      Repo.get_by(User, device_id: device_id(1)) ||
        raise ArgumentError, "no demo players: run `demo.seed` first"

    group_id = Repo.one(from(g in Group, where: g.title == @group_title, select: g.id))

    lobby_id =
      Repo.one(
        from(l in Lobby,
          where: like(l.title, "Demo Seed Lobby %"),
          order_by: l.title,
          limit: 1,
          select: l.id
        )
      )

    %{
      admin_token: session_token(ensure_bench_admin()),
      player_token: session_token(player),
      params:
        %{
          "player_id" => player.id,
          "group_id" => group_id,
          "lobby_id" => lobby_id,
          "leaderboard" => @leaderboard_slug,
          "season_board" => @season_slug,
          "tournament" => @tournament_slug,
          "search_hit" => username(42),
          "search_broad" => @prefix,
          "search_miss" => "zq-no-such-name"
        }
        |> Map.merge(host_params(player.id))
    }
  end

  # The ids a host's own pages need (`config :gamend_core, :demo_bench_params,
  # {module, function}`, called with the heavy player's id): its seed made
  # them, and only it knows where they are.
  defp host_params(player_id) do
    case Application.get_env(:gamend_core, :demo_bench_params) do
      {module, function} -> apply(module, function, [player_id])
      nil -> %{}
    end
  end

  @doc """
  For a host's own seed (`mix polyglot.demo.seed`): the demo players' ids in
  order, the heavy one first, `count` of them (every one by default). Empty
  before `demo.seed` has run.
  """
  @spec player_ids(pos_integer() | nil) :: [Ecto.UUID.t()]
  def player_ids(count \\ nil) do
    from(u in User,
      where: like(u.device_id, ^"#{@prefix}-%") and not u.is_admin,
      order_by: u.device_id,
      select: u.id
    )
    |> then(&if count, do: limit(&1, ^count), else: &1)
    |> Repo.all(timeout: :infinity)
  end

  @doc """
  For a host's own seed: streams `rows` into `schema` the way every set here
  does (statements under the bind-parameter limit, four at once on
  Postgres) and answers how many went in. `analyze/0` after a bulk load.
  """
  @spec insert_rows(Enumerable.t(), module()) :: non_neg_integer()
  def insert_rows(rows, schema), do: insert_batches(rows, schema)

  @doc "Re-analyses the tables after a bulk load (Postgres; nothing on SQLite)."
  @spec analyze_tables() :: :ok
  def analyze_tables, do: analyze()

  defp ensure_bench_admin do
    device_id = "#{@prefix}-admin"

    case Repo.get_by(User, device_id: device_id) do
      nil ->
        Repo.insert!(%User{
          device_id: device_id,
          username: device_id,
          display_name: "Demo Bench Admin",
          is_admin: true,
          is_activated: true
        })

      admin ->
        admin
    end
  end

  # Inserted here rather than through `Gamend.Accounts`: that also touches the
  # player's presence, which needs the whole application running.
  defp session_token(user) do
    {token, row} = UserToken.build_session_token(user)
    Repo.insert!(row)
    token
  end

  defp parse_sets(nil), do: @all_sets

  defp parse_sets(only) do
    sets = only |> String.split(",", trim: true) |> Enum.map(&String.trim/1)

    case sets -- @all_sets do
      [] ->
        sets

      unknown ->
        raise ArgumentError,
              "unknown set(s): #{Enum.join(unknown, ", ")} (known: #{Enum.join(@all_sets, ", ")})"
    end
  end

  # ── Shared player pool ────────────────────────────────────────────────────

  defp ensure_users(count) do
    existing =
      from(u in User, where: like(u.device_id, ^"#{@prefix}-%"), select: u.device_id)
      |> Repo.all()
      |> MapSet.new()

    now = DateTime.utc_now(:second)

    added =
      1..count
      |> Stream.map(&{&1, device_id(&1)})
      |> Stream.reject(fn {_i, device_id} -> MapSet.member?(existing, device_id) end)
      |> Stream.map(fn {i, device_id} -> player_row(i, device_id, now) end)
      |> insert_batches(User)

    info("players: #{count} (#{added} new)")

    # `mix demo.bench`'s admin shares the prefix (so --clean takes it) but is
    # not a player.
    from(u in User,
      where: like(u.device_id, ^"#{@prefix}-%") and not u.is_admin,
      order_by: u.device_id,
      limit: ^count,
      select: u.id
    )
    |> Repo.all()
  end

  # Every third player registered (a confirmed email), the rest guests; last
  # seen over the past month and joined up to a year before that, so the
  # admin lists and the analytics segments have something to sort and split.
  # Confirmed, or the retention sweep deletes them as unconfirmed sign-ups
  # while the seed is still writing their rows.
  defp player_row(i, device_id, now) do
    last_seen = spread(now, i, 30 * 86_400)
    joined = spread(last_seen, i * 31, @year_sec)
    registered? = rem(i, 3) == 0

    %{
      id: UUIDv7.generate(),
      device_id: device_id,
      email: if(registered?, do: "#{device_id}@example.test"),
      confirmed_at: if(registered?, do: joined),
      username: username(i),
      display_name: display_name(i),
      is_admin: false,
      is_activated: true,
      metadata: %{},
      token_version: 0,
      last_seen_at: last_seen,
      inserted_at: joined,
      updated_at: joined
    }
  end

  # A deterministic instant in the `window` seconds before `from`, scattered by
  # `i` so neighbouring rows do not share a timestamp.
  defp spread(from, i, window), do: DateTime.add(from, -rem(i * 7_919, window), :second)

  defp device_id(i), do: "#{@prefix}-#{pad(i)}"
  defp username(i), do: "#{@prefix}-#{pad(i)}"
  defp display_name(i), do: "Demo Player #{pad(i)}"
  defp pad(i), do: String.pad_leading(Integer.to_string(i), 5, "0")

  # ── Sets ──────────────────────────────────────────────────────────────────

  defp seed_leaderboard(user_ids) do
    leaderboard =
      upsert(Leaderboard, [slug: @leaderboard_slug], %{
        slug: @leaderboard_slug,
        title: "Demo Seed Scores",
        description: "Volume demo data.",
        sort_order: :desc,
        operator: :best,
        metadata: %{}
      })

    Repo.delete_all(from(r in Record, where: r.leaderboard_id == ^leaderboard.id),
      timeout: :infinity
    )

    now = DateTime.utc_now(:second)

    user_ids
    |> Stream.map(fn user_id ->
      %{
        id: UUIDv7.generate(),
        leaderboard_id: leaderboard.id,
        user_id: user_id,
        score: :rand.uniform(1_000_000),
        metadata: %{},
        inserted_at: now,
        updated_at: now
      }
    end)
    |> insert_batches(Record)

    info("leaderboard: #{length(user_ids)} records -> /leaderboards/#{@leaderboard_slug}")
    seed_seasons(user_ids)
  end

  # Twelve monthly seasons under one slug, the last still running: what the
  # All time tab reads as one ranking. Every player has a row in one season,
  # every fourth in up to two more.
  defp seed_seasons(user_ids) do
    now = DateTime.utc_now(:second)
    month = %{DateTime.to_date(now) | day: 1}

    boards =
      for back <- 11..0//-1 do
        starts = month |> Date.shift(month: -back) |> DateTime.new!(~T[00:00:00])
        ends = month |> Date.shift(month: 1 - back) |> DateTime.new!(~T[00:00:00])

        upsert(Leaderboard, [slug: @season_slug, starts_at: starts], %{
          slug: @season_slug,
          title: "Demo Seed Monthly",
          description: "Volume demo seasons.",
          sort_order: :desc,
          operator: :best,
          starts_at: starts,
          ends_at: ends,
          metadata: %{}
        })
      end

    ids = Enum.map(boards, & &1.id)
    by_season = List.to_tuple(ids)
    Repo.delete_all(from(r in Record, where: r.leaderboard_id in ^ids), timeout: :infinity)

    rows =
      user_ids
      |> Stream.with_index()
      |> Stream.flat_map(fn {user_id, i} ->
        seasons =
          if rem(i, 4) == 0,
            do: Enum.uniq([rem(i, 12), rem(i * 7 + 3, 12), rem(i * 5 + 1, 12)]),
            else: [rem(i, 12)]

        for season <- seasons do
          %{
            id: UUIDv7.generate(),
            leaderboard_id: elem(by_season, season),
            user_id: user_id,
            score: :rand.uniform(1_000_000),
            metadata: %{},
            inserted_at: now,
            updated_at: now
          }
        end
      end)
      |> insert_batches(Record)

    # Written around `submit_score/5`, so All time's own board is filled here.
    {:ok, best} = Gamend.Leaderboards.rebuild_all_time(@season_slug)

    info(
      "seasons: 12 boards, #{rows} records, #{best} all-time rows -> /leaderboards/#{@season_slug}?period=all"
    )
  end

  defp seed_group(user_ids) do
    [creator | members] = user_ids
    group = demo_group(user_ids)

    Repo.delete_all(from(m in GroupMember, where: m.group_id == ^group.id), timeout: :infinity)
    now = DateTime.utc_now(:second)

    rows =
      [%{user_id: creator, role: GroupRole.admin()}] ++
        Enum.map(members, &%{user_id: &1, role: GroupRole.member()})

    rows
    |> Stream.map(fn row ->
      %{
        id: UUIDv7.generate(),
        group_id: group.id,
        user_id: row.user_id,
        role: row.role,
        inserted_at: now,
        updated_at: now
      }
    end)
    |> insert_batches(GroupMember)

    info("group: #{length(rows)} members -> /groups/#{group.id}")
  end

  defp demo_group(user_ids) do
    upsert(Group, [title: @group_title], %{
      title: @group_title,
      description: "Volume demo data.",
      type: GroupType.public(),
      max_members: length(user_ids) + 10,
      creator_id: hd(user_ids),
      metadata: %{}
    })
  end

  defp seed_tournament(user_ids) do
    now = DateTime.utc_now(:second)

    tournament =
      upsert(Tournament, [slug: @tournament_slug], %{
        slug: @tournament_slug,
        title: "Demo Seed Cup",
        description: "Volume demo data — registration is open.",
        state: TournamentState.registration(),
        registration_opens_at: DateTime.add(now, -3600),
        starts_at: DateTime.add(now, 7 * 86_400),
        round_window_sec: 3600,
        bracket_size: 8,
        team_size: 1,
        deadline_policy: DeadlinePolicy.forfeit_both(),
        metadata: %{}
      })

    Repo.delete_all(from(e in Entry, where: e.tournament_id == ^tournament.id),
      timeout: :infinity
    )

    user_ids
    |> Stream.map(fn user_id ->
      %{
        id: UUIDv7.generate(),
        tournament_id: tournament.id,
        leader_id: user_id,
        wins: 0,
        state: "registered",
        metadata: %{},
        inserted_at: now,
        updated_at: now
      }
    end)
    |> insert_batches(Entry)

    info("tournament: #{length(user_ids)} entries -> /tournaments/#{tournament.id}")
  end

  # ── Clean ─────────────────────────────────────────────────────────────────

  # A daily, an auto-claim achievement, a chain gated on it and a group that
  # collapses to one card — with per-user progress in every state, including
  # claimable completed rows.
  defp seed_quests(user_ids) do
    daily =
      upsert_quest(%{
        key: @quest_key_prefix <> "daily-login",
        title: "Demo Daily Login",
        description: "Log in 3 times today.",
        reset: QuestReset.daily(),
        category: "Daily",
        objectives: [%{event: ReportedEvent.login(), target: 3, params: %{}}],
        rewards: [%{type: RewardType.currency(), code: @gold, amount: 100}],
        auto_claim: false,
        active: true,
        metadata: %{}
      })

    achievement =
      upsert_quest(%{
        key: @quest_key_prefix <> "first-win",
        title: "Demo First Win",
        description: "Win your first demo match.",
        reset: QuestReset.never(),
        category: "Achievements",
        objectives: [%{event: "demo_win", target: 1, params: %{}}],
        rewards: [],
        auto_claim: true,
        active: true,
        metadata: %{}
      })

    chain =
      upsert_quest(%{
        key: @quest_key_prefix <> "veteran",
        title: "Demo Veteran",
        description: "Win 10 demo matches (after your first win).",
        reset: QuestReset.never(),
        category: "Chained",
        objectives: [%{event: "demo_win", target: 10, params: %{}}],
        rewards: [%{type: RewardType.item(), code: "loot_crate", amount: 1}],
        auto_claim: false,
        prerequisite_quest_key: achievement.key,
        active: true,
        metadata: %{}
      })

    # A group is only worth looking at in bulk: twelve definitions, one card.
    countries = ~w(Spain Romania Poland Portugal Greece Norway
                   Japan Chile Kenya Peru Iceland Vietnam)

    group_members =
      for {country, i} <- Enum.with_index(countries) do
        upsert_quest(%{
          key: @quest_key_prefix <> "visit-" <> String.downcase(country),
          title: "Visit #{country}",
          description: "Visit 5 cities in #{country}.",
          reset: QuestReset.never(),
          category: "Exploration",
          group_key: @quest_key_prefix <> "world-tour",
          group_title: "World tour",
          sort_order: i,
          objectives: [
            %{event: "demo_city_visited", target: 5, params: %{"country" => country}}
          ],
          rewards: [%{type: RewardType.currency(), code: @gold, amount: 50}],
          auto_claim: false,
          active: true,
          metadata: %{}
        })
      end

    seed_quest_codes()

    now = DateTime.utc_now(:second)
    today = Gamend.Quests.period_key(QuestReset.daily(), now)

    Repo.delete_all(from(p in QuestProgress, where: like(p.quest_key, ^"#{@quest_key_prefix}%")),
      timeout: :infinity
    )

    daily_rows =
      user_ids
      |> Stream.with_index()
      |> Stream.map(fn {user_id, i} ->
        completed? = rem(i, 3) == 0
        claimed? = rem(i, 6) == 0

        status =
          cond do
            claimed? -> QuestStatus.claimed()
            completed? -> QuestStatus.completed()
            true -> QuestStatus.active()
          end

        %{
          id: UUIDv7.generate(),
          user_id: user_id,
          quest_key: daily.key,
          period_key: today,
          objective_progress: %{"0" => if(completed?, do: 3, else: rem(i, 3))},
          status: status,
          completed_at: if(completed?, do: now),
          claimed_at: if(claimed?, do: now),
          rewards_granted_at: if(claimed?, do: now),
          metadata: %{},
          inserted_at: now,
          updated_at: now
        }
      end)

    achievement_rows =
      user_ids
      |> Stream.with_index()
      |> Stream.filter(fn {_id, i} -> rem(i, 2) == 0 end)
      |> Stream.map(fn {user_id, _i} ->
        %{
          id: UUIDv7.generate(),
          user_id: user_id,
          quest_key: achievement.key,
          period_key: PeriodKey.static(),
          objective_progress: %{"0" => 1},
          status: "claimed",
          completed_at: now,
          claimed_at: now,
          rewards_granted_at: now,
          metadata: %{},
          inserted_at: now,
          updated_at: now
        }
      end)

    chain_rows =
      user_ids
      |> Stream.with_index()
      |> Stream.filter(fn {_id, i} -> rem(i, 4) == 0 end)
      |> Stream.map(fn {user_id, i} ->
        %{
          id: UUIDv7.generate(),
          user_id: user_id,
          quest_key: chain.key,
          period_key: PeriodKey.static(),
          objective_progress: %{"0" => rem(i, 10)},
          status: QuestStatus.active(),
          completed_at: nil,
          claimed_at: nil,
          rewards_granted_at: nil,
          metadata: %{},
          inserted_at: now,
          updated_at: now
        }
      end)

    # Spread over the members so the collapsed card has a representative to
    # pick: the one furthest along, not whatever sorted first.
    group_rows =
      for {user_id, i} <- Enum.with_index(user_ids),
          rem(i, 3) == 0,
          member = Enum.at(group_members, rem(i, length(group_members))) do
        %{
          id: UUIDv7.generate(),
          user_id: user_id,
          quest_key: member.key,
          period_key: PeriodKey.static(),
          objective_progress: %{"0" => rem(i, 5) + 1},
          status: QuestStatus.active(),
          completed_at: nil,
          claimed_at: nil,
          rewards_granted_at: nil,
          metadata: %{},
          inserted_at: now,
          updated_at: now
        }
      end

    rows =
      insert_batches(
        Stream.concat([daily_rows, achievement_rows, chain_rows, group_rows]),
        QuestProgress
      )

    info(
      "quests: #{3 + length(group_members)} definitions, #{rows} progress rows -> /admin/quests"
    )
  end

  # Definitions go through the context (embeds can't be bulk-inserted).
  # Enough to page through on `/admin/quests/:id/codes`, and one shared code to
  # try at `/redeem`. Generated once: running the seed again keeps what is there.
  defp seed_quest_codes do
    quest =
      upsert_quest(%{
        key: @quest_key_prefix <> "spring-gift",
        title: "Spring gift",
        description: "For everyone who has the code.",
        code_only: true,
        category: "Events",
        rewards: [%{type: RewardType.currency(), code: @gold, amount: 100}],
        active: true,
        metadata: %{}
      })

    if Gamend.Quests.count_codes(quest.key) == 0 do
      {:ok, _} = Gamend.Quests.generate_codes(quest, 120)
      {:ok, _} = Gamend.Quests.create_code(quest, %{token: "SPRING-GIFT", max_uses: nil})
    end

    :ok
  end

  defp upsert_quest(attrs) do
    case Repo.get_by(Quest, key: attrs.key) do
      nil ->
        {:ok, quest} = Gamend.Quests.create_quest(attrs)
        quest

      quest ->
        quest
    end
  end

  defp clean_quests do
    Repo.delete_all(from(p in QuestProgress, where: like(p.quest_key, ^"#{@quest_key_prefix}%")),
      timeout: :infinity
    )

    Repo.delete_all(from(q in Quest, where: like(q.key, ^"#{@quest_key_prefix}%")),
      timeout: :infinity
    )
  end

  # One device per player (platform/provider cycling), every tenth disabled so
  # the admin page shows the dead-token state. Log provider, so a test push
  # against this data is observable in the server log. Rows cascade-delete
  # with their demo user on clean.
  defp seed_push_tokens(user_ids) do
    Repo.delete_all(from(t in PushToken, where: like(t.token, ^"#{@prefix}-token-%")),
      timeout: :infinity
    )

    now = DateTime.utc_now(:second)

    user_ids
    |> Stream.with_index()
    |> Stream.map(fn {user_id, i} ->
      {platform, provider} =
        case rem(i, 3) do
          0 -> {Platform.android(), PushProvider.fcm()}
          1 -> {Platform.ios(), PushProvider.apns()}
          2 -> {Platform.web(), PushProvider.fcm()}
        end

      %{
        id: UUIDv7.generate(),
        user_id: user_id,
        token: "#{@prefix}-token-#{pad(i)}",
        platform: platform,
        provider: provider,
        device_id: device_id(i),
        disabled_at: if(rem(i, 10) == 9, do: now),
        metadata: %{},
        inserted_at: now,
        updated_at: now
      }
    end)
    |> insert_batches(PushToken)

    info("push: #{length(user_ids)} device tokens -> /admin/push")
  end

  # Lobbies are hosted by seeded players and cascade on --clean, so the checks
  # attached to them go too. Each run gets one open check plus a spread of
  # resolved ones, which is what the admin page's 24h counters read.
  defp seed_ready_checks(user_ids) do
    hosts = Enum.take(user_ids, min(@max_runs, length(user_ids)))
    now = DateTime.utc_now(:second)

    checks =
      hosts
      |> Enum.with_index()
      |> Enum.map(fn {host_id, i} ->
        {status, reason} =
          case rem(i, 4) do
            0 -> {CheckStatus.pending(), nil}
            1 -> {CheckStatus.passed(), nil}
            2 -> {CheckStatus.failed(), CheckReason.timeout()}
            3 -> {CheckStatus.failed(), CheckReason.declined()}
          end

        lobby =
          upsert(Lobby, [title: "#{@lobby_title_prefix} Ready #{pad(i)}"], %{
            title: "#{@lobby_title_prefix} Ready #{pad(i)}",
            host_id: host_id,
            max_users: 4,
            metadata: %{},
            state: LobbyState.created(),
            state_changed_at: now
          })

        %{
          id: UUIDv7.generate(),
          kind: if(rem(i, 3) == 0, do: CheckKind.accept(), else: @ready),
          status: status,
          lobby_id: lobby.id,
          deadline_at: DateTime.add(now, 15, :second),
          opened_by: host_id,
          reason: reason,
          resolved_at: if(status != CheckStatus.pending(), do: now),
          metadata: %{},
          inserted_at: now,
          updated_at: now
        }
      end)

    insert_batches(checks, ReadyCheck)

    participants =
      checks
      |> Enum.with_index()
      |> Enum.flat_map(fn {check, i} ->
        user_ids
        |> Enum.slice(i, 3)
        |> Enum.with_index()
        |> Enum.map(fn {user_id, j} ->
          %{
            id: UUIDv7.generate(),
            ready_check_id: check.id,
            user_id: user_id,
            state: participant_state(check, j),
            responded_at: now,
            inserted_at: now,
            updated_at: now
          }
        end)
      end)

    insert_batches(participants, ReadyCheckParticipant)

    info("ready checks: #{length(checks)} (this set ignores --count) -> /admin/matchmaking")
  end

  defp participant_state(%{status: CheckStatus.passed()}, _index), do: @ready
  defp participant_state(%{status: CheckStatus.failed(), reason: "declined"}, 0), do: "declined"

  defp participant_state(%{status: CheckStatus.failed(), reason: CheckReason.timeout()}, 0),
    do: "timed_out"

  defp participant_state(%{status: CheckStatus.pending()}, 0), do: ParticipantState.pending()
  defp participant_state(_check, _index), do: @ready

  # ── Chat moderation ───────────────────────────────────────────────────────

  # Reports point at real messages in real rooms, so the queue's content
  # snapshots, "reported user" links and per-scope mute lists all resolve the
  # way they do in production.
  defp seed_chat_moderation(user_ids) do
    rooms = chat_rooms(user_ids)
    clean_chat_moderation(rooms)

    words = seed_filter_words()
    messages = seed_chat_messages(user_ids, rooms)
    reports = seed_chat_reports(messages, hd(user_ids))
    mutes = seed_chat_mutes(user_ids, rooms)

    info(
      "chat moderation: #{words} filter words, #{reports} reports, #{mutes} mutes -> /admin/chat_reports"
    )
  end

  defp chat_rooms(user_ids) do
    now = DateTime.utc_now(:second)
    [host | _rest] = user_ids

    lobby =
      upsert(Lobby, [title: @chat_lobby_title], %{
        title: @chat_lobby_title,
        host_id: host,
        max_users: 4,
        metadata: %{},
        state: LobbyState.created(),
        state_changed_at: now
      })

    party = upsert(Party, [leader_id: host], %{leader_id: host, max_size: 4, metadata: %{}})

    %{"group" => demo_group(user_ids).id, "lobby" => lobby.id, "party" => party.id}
  end

  # Reports go before their messages: deleting a message only nils out the
  # report pointing at it.
  defp clean_chat_moderation(rooms) do
    room_ids = Map.values(rooms)
    message_ids = from(m in Message, where: m.chat_ref_id in ^room_ids, select: m.id)

    Repo.delete_all(from(r in Report, where: r.message_id in subquery(message_ids)),
      timeout: :infinity
    )

    Repo.delete_all(from(m in Message, where: m.chat_ref_id in ^room_ids), timeout: :infinity)

    Repo.delete_all(
      from(b in Ban, where: b.kind == :chat and b.user_id in subquery(demo_user_ids())),
      timeout: :infinity
    )
  end

  # Words go in through the context: it stores them normalized (a raw insert
  # would never match) and mirrors them into the ETS blocklist.
  defp seed_filter_words do
    clean_filter_words()

    Enum.count(@filter_words, fn {word, severity, match_mode, lang} ->
      match?(
        {:ok, _word},
        Moderation.create_filter_word(%{
          "word" => word,
          "severity" => severity,
          "match_mode" => match_mode,
          "lang" => lang
        })
      )
    end)
  end

  defp clean_filter_words do
    words =
      Enum.map(@filter_words, fn {word, _severity, _mode, _lang} -> Normalizer.normalize(word) end)

    from(w in FilterWord, where: w.word in ^words)
    |> Repo.all()
    |> Enum.each(&Moderation.delete_filter_word/1)
  end

  defp seed_chat_messages(user_ids, rooms) do
    now = DateTime.utc_now(:second)

    rows =
      user_ids
      |> at_least(@min_reports)
      |> Enum.with_index()
      |> Enum.map(fn {sender_id, i} ->
        chat_type = Enum.at(@chat_room_types, rem(i, length(@chat_room_types)))
        {content, _reason, flagged?} = chat_line(i)
        # Fifteen minutes apart, wrapping within the year.
        at = DateTime.add(now, -(rem(i * 900, @year_sec) + 60), :second)

        %{
          id: UUIDv7.generate(),
          sender_id: sender_id,
          chat_type: chat_type,
          chat_ref_id: Map.fetch!(rooms, chat_type),
          content: content,
          metadata: if(flagged?, do: %{"flagged" => true}, else: %{}),
          inserted_at: at,
          updated_at: at
        }
      end)

    insert_batches(rows, Message)
    rows
  end

  # Every fifth message is one the filter flagged itself, so the queue mixes
  # system-filed reports (nil reporter) into the player-filed ones. Pure and
  # index-keyed, so the report built for message `i` reads off the same line.
  defp chat_line(i) when rem(i, 5) == 0 do
    {content, word} = Enum.at(@flagged_lines, rem(div(i, 5), length(@flagged_lines)))
    {content, "Filter: " <> word, true}
  end

  defp chat_line(i) do
    {content, reason} = Enum.at(@chat_lines, rem(i, length(@chat_lines)))
    {content, reason, false}
  end

  # The reporter is the next player along, since a player cannot report their
  # own message (`Chat.report_message/3` rejects it).
  defp seed_chat_reports(messages, moderator_id) do
    now = DateTime.utc_now(:second)

    reporters =
      messages
      |> Stream.map(& &1.sender_id)
      |> Stream.cycle()
      |> Stream.drop(1)
      |> Enum.take(length(messages))

    messages
    |> Stream.zip(reporters)
    |> Stream.with_index()
    |> Stream.map(fn {{message, reporter_id}, i} ->
      {status, note} = report_status(i)
      {_content, reason, flagged?} = chat_line(i)
      at = DateTime.add(now, -rem(i * 900, @year_sec), :second)

      %{
        id: UUIDv7.generate(),
        reporter_id: if(flagged?, do: nil, else: reporter_id),
        message_id: message.id,
        reported_user_id: message.sender_id,
        content_snapshot: message.content,
        reason: reason,
        status: status,
        resolved_by: if(note, do: moderator_id),
        resolution_note: note,
        resolved_at: if(note, do: now),
        inserted_at: at,
        updated_at: at
      }
    end)
    |> insert_batches(Report)
  end

  defp report_status(i) do
    case rem(i, 4) do
      0 -> {ChatReportStatus.open(), nil}
      1 -> {ChatReportStatus.reviewing(), nil}
      2 -> {ChatReportStatus.actioned(), "24h mute — third report this week."}
      3 -> {ChatReportStatus.dismissed(), "Heated, but inside the rules."}
    end
  end

  # Every scope, and a spread of permanent / expiring / already ended, so the
  # bans list has history. A mute is a chat ban (`Gamend.Bans`, kind `:chat`).
  defp seed_chat_mutes(user_ids, rooms) do
    now = DateTime.utc_now(:second)
    [moderator | rest] = user_ids

    rows =
      rest
      |> Enum.take(@max_mutes)
      |> Enum.with_index()
      |> Enum.map(fn {user_id, i} ->
        {scope, scope_ref_id} = mute_scope(rooms, i)
        {expires_at, reason} = mute_expiry(now, i)

        %{
          id: UUIDv7.generate(),
          kind: :chat,
          subject: user_id,
          user_id: user_id,
          scope: scope,
          scope_ref_id: scope_ref_id,
          expires_at: expires_at,
          reason: reason,
          source: :admin,
          banned_by: moderator,
          inserted_at: now,
          updated_at: now
        }
      end)

    insert_batches(rows, Ban)
    length(rows)
  end

  defp mute_scope(rooms, i) do
    case rem(i, 4) do
      0 -> {BanScope.global(), nil}
      1 -> {ChatType.lobby(), Map.fetch!(rooms, "lobby")}
      2 -> {ChatType.group(), Map.fetch!(rooms, "group")}
      3 -> {ChatType.party(), Map.fetch!(rooms, "party")}
    end
  end

  defp mute_expiry(now, i) do
    case rem(div(i, 4), 3) do
      0 -> {nil, "Permanent — ban evasion."}
      1 -> {DateTime.add(now, 900), "Cooling off, back in 15 minutes."}
      2 -> {DateTime.add(now, -86_400), "Expired yesterday; kept as history."}
    end
  end

  # A small --count still has to fill more than one page of the report queue.
  defp at_least(ids, minimum) when length(ids) >= minimum, do: ids
  defp at_least(ids, minimum), do: ids |> Stream.cycle() |> Enum.take(minimum)

  defp demo_user_ids do
    from(u in User, where: like(u.device_id, ^"#{@prefix}-%"), select: u.id)
  end

  defp clean do
    lb = Repo.get_by(Leaderboard, slug: @leaderboard_slug)
    group = Repo.get_by(Group, title: @group_title)
    tournament = Repo.get_by(Tournament, slug: @tournament_slug)

    if lb,
      do:
        Repo.delete_all(from(r in Record, where: r.leaderboard_id == ^lb.id), timeout: :infinity)

    if group,
      do:
        Repo.delete_all(from(m in GroupMember, where: m.group_id == ^group.id),
          timeout: :infinity
        )

    if tournament,
      do:
        Repo.delete_all(from(e in Entry, where: e.tournament_id == ^tournament.id),
          timeout: :infinity
        )

    if lb, do: Repo.delete(lb)
    # The seasons and All time's own board (`<slug>__all_time`).
    Repo.delete_all(from(l in Leaderboard, where: like(l.slug, ^"#{@season_slug}%")),
      timeout: :infinity
    )

    if group, do: Repo.delete(group)
    if tournament, do: Repo.delete(tournament)

    # Before the players go: seeded lobbies reference them as host.
    clean_results()
    clean_quests()

    # Reports, mutes and messages cascade with their players; the blocklist has
    # no player to hang off.
    clean_filter_words()
    clean_volume()

    {users, _} =
      Repo.delete_all(from(u in User, where: like(u.device_id, ^"#{@prefix}-%")),
        timeout: :infinity
      )

    Gamend.Cache.delete_all()
    info("removed demo data (#{users} players)")
  end

  # ── Volume sets ───────────────────────────────────────────────────────────
  #
  # One per admin list, each sized from N. Rows that cascade with their player
  # are cleaned by `--clean` deleting the players; the rest carry the prefix
  # (`clean_volume/0`).

  @event_names ~w(demo.page_view demo.round_finished demo.test_finished demo.hint
                  demo.checkout demo.signup)
  @event_langs ~w(es fr de it ro pt ja zh)

  # A profile row per player, plus N/10 global keys for the key search to wade
  # through.
  defp seed_kv(user_ids) do
    Repo.delete_all(from(e in KVEntry, where: like(e.key, ^"#{@prefix}:%")), timeout: :infinity)
    now = DateTime.utc_now(:second)

    profiles =
      user_ids
      |> Stream.with_index(1)
      |> Stream.map(fn {user_id, i} ->
        value = %{"level" => rem(i, 50), "title" => display_name(i)}
        kv_row("#{@prefix}:profile", user_id, value, spread(now, i, @year_sec))
      end)

    globals =
      Stream.map(1..max(div(length(user_ids), 10), 1), fn i ->
        kv_row("#{@prefix}:global:#{pad(i)}", nil, %{"n" => i}, spread(now, i, @year_sec))
      end)

    rows = insert_batches(Stream.concat(profiles, globals), KVEntry)
    info("kv: #{rows} entries -> /admin/kv")
  end

  defp kv_row(key, user_id, value, at) do
    %{
      id: UUIDv7.generate(),
      key: key,
      user_id: user_id,
      lobby_id: nil,
      value: value,
      metadata: %{},
      inserted_at: at,
      updated_at: at
    }
  end

  # One per player from the next one along, and N/10 more for the first
  # player, half of them unread.
  defp seed_notifications([heavy | _] = user_ids) do
    Repo.delete_all(from(n in Notification, where: like(n.title, ^"#{@prefix} %")),
      timeout: :infinity
    )

    now = DateTime.utc_now(:second)
    # The next player along, the last one's being the first.
    senders = Stream.concat(tl(user_ids), [heavy])

    each =
      user_ids
      |> Stream.zip(senders)
      |> Stream.with_index(1)
      |> Stream.map(fn {{recipient, sender}, i} ->
        notification_row(recipient, sender, i, now)
      end)

    inbox =
      user_ids
      |> tl()
      |> Stream.cycle()
      |> Stream.take(div(length(user_ids), 10))
      |> Stream.with_index(1)
      |> Stream.map(fn {sender, i} -> notification_row(heavy, sender, -i, now) end)

    rows = insert_batches(Stream.concat(each, inbox), Notification)
    info("notifications: #{rows} -> /admin/notifications, /notifications")
  end

  defp notification_row(recipient, sender, i, now) do
    at = spread(now, abs(i), 90 * 86_400)

    %{
      id: UUIDv7.generate(),
      sender_id: sender,
      recipient_id: recipient,
      title: "#{@prefix} notice #{i}",
      content: "Volume demo notification.",
      metadata: %{},
      read: rem(i, 2) == 0,
      inserted_at: at,
      updated_at: at
    }
  end

  # 2N events over 90 days, one to five activity days per player in the past
  # 60, and a year of daily counters for every event name.
  defp seed_analytics(user_ids) do
    clean_analytics()
    now = DateTime.utc_now(:second)
    today = DateTime.to_date(now)
    count = length(user_ids)

    events =
      user_ids
      |> Stream.cycle()
      |> Stream.take(count * 2)
      |> Stream.with_index()
      |> Stream.map(fn {user_id, i} ->
        %{
          id: UUIDv7.generate(),
          name: Enum.at(@event_names, rem(i, length(@event_names))),
          dims: %{
            "lang" => Enum.at(@event_langs, rem(i, length(@event_langs))),
            "who" => if(rem(i, 3) == 0, do: @account, else: @guest),
            "score" => rem(i, 11)
          },
          user_id: user_id,
          inserted_at: spread(now, i, 90 * 86_400)
        }
      end)

    days =
      user_ids
      |> Stream.with_index()
      |> Stream.flat_map(fn {user_id, i} ->
        for k <- 0..rem(i, 5) do
          day = Date.add(today, -(rem(i, 45) + k * 3))
          %{id: UUIDv7.generate(), user_id: user_id, day: day, inserted_at: now}
        end
      end)

    counters =
      for name <- @event_names, back <- 0..364 do
        %{
          id: UUIDv7.generate(),
          day: Date.add(today, -back),
          key: name,
          count: div(count, 50) + rem(back * 7, 100),
          inserted_at: now,
          updated_at: now
        }
      end

    events = insert_batches(events, AnalyticsEvent)
    days = insert_batches(days, ActivityDay)
    counters = insert_batches(counters, DailyCount)

    info(
      "analytics: #{events} events, #{days} activity days, #{counters} daily counts -> /admin/analytics"
    )
  end

  # Events lose their player on account deletion rather than going with it,
  # and the counters have none, so both go by name.
  defp clean_analytics do
    Repo.delete_all(from(e in AnalyticsEvent, where: like(e.name, "demo.%")), timeout: :infinity)
    Repo.delete_all(from(c in DailyCount, where: like(c.key, "demo.%")), timeout: :infinity)

    Repo.delete_all(from(d in ActivityDay, where: d.user_id in subquery(demo_user_ids())),
      timeout: :infinity
    )
  end

  # A coin wallet per player, a grant and a spend each, and N/100 entries of
  # history for the first player.
  defp seed_economy([heavy | _] = user_ids) do
    Repo.delete_all(from(w in Wallet, where: w.user_id in subquery(demo_user_ids())),
      timeout: :infinity
    )

    Repo.delete_all(from(l in LedgerEntry, where: l.user_id in subquery(demo_user_ids())),
      timeout: :infinity
    )

    now = DateTime.utc_now(:second)

    wallets =
      user_ids
      |> Stream.with_index(1)
      |> Stream.map(fn {user_id, i} ->
        %{
          id: UUIDv7.generate(),
          user_id: user_id,
          currency: "coins",
          balance: rem(i * 37, 5_000),
          inserted_at: now,
          updated_at: now
        }
      end)

    entries =
      user_ids
      |> Stream.with_index(1)
      |> Stream.flat_map(fn {user_id, i} ->
        [
          ledger_row(user_id, 500, "demo_seed_grant", i, now),
          ledger_row(user_id, -rem(i, 400), "demo_seed_spend", i + 1, now)
        ]
      end)

    history =
      Stream.map(1..div(length(user_ids), 100)//1, fn i ->
        ledger_row(heavy, if(rem(i, 2) == 0, do: 10, else: -10), "demo_seed_history", i, now)
      end)

    wallets = insert_batches(wallets, Wallet)
    entries = insert_batches(Stream.concat(entries, history), LedgerEntry)
    info("economy: #{wallets} wallets, #{entries} ledger entries -> /admin/economy")
  end

  defp ledger_row(user_id, delta, reason, i, now) do
    %{
      id: UUIDv7.generate(),
      user_id: user_id,
      currency: "coins",
      delta: delta,
      balance_after: rem(i * 37, 5_000),
      reason: reason,
      metadata: %{},
      inserted_at: spread(now, i, @year_sec)
    }
  end

  # Every tenth player bought something; the completed ones hold an
  # entitlement from it.
  defp seed_payments(user_ids) do
    Repo.delete_all(from(e in Entitlement, where: e.key == "demo_seed_pro"), timeout: :infinity)

    Repo.delete_all(from(p in Purchase, where: like(p.order_id, ^"#{@prefix}-order-%")),
      timeout: :infinity
    )

    now = DateTime.utc_now(:second)

    purchases =
      user_ids
      |> Enum.take_every(10)
      |> Enum.with_index(1)
      |> Enum.map(fn {user_id, i} ->
        at = spread(now, i, @year_sec)

        %{
          id: UUIDv7.generate(),
          user_id: user_id,
          provider: ProviderId.stripe(),
          order_id: "#{@prefix}-order-#{pad(i)}",
          provider_transaction_id: "#{@prefix}-tx-#{pad(i)}",
          status:
            Enum.at(
              [
                PurchaseStatus.completed(),
                PurchaseStatus.completed(),
                PurchaseStatus.completed(),
                PurchaseStatus.refunded(),
                PurchaseStatus.failed()
              ],
              rem(i, 5)
            ),
          quantity: 1,
          currency: "eur",
          amount: if(rem(i, 3) == 0, do: 3_900, else: 499),
          environment: PaymentEnvironment.production(),
          raw_provider_payload: %{},
          metadata: %{},
          purchased_at: at,
          inserted_at: at,
          updated_at: at
        }
      end)

    entitlements =
      for %{status: PurchaseStatus.completed()} = purchase <- purchases do
        %{
          id: UUIDv7.generate(),
          user_id: purchase.user_id,
          source_purchase_id: purchase.id,
          key: "demo_seed_pro",
          status: QuestStatus.active(),
          starts_at: purchase.purchased_at,
          metadata: %{},
          inserted_at: purchase.inserted_at,
          updated_at: purchase.inserted_at
        }
      end

    bought = insert_batches(purchases, Purchase)
    held = insert_batches(entitlements, Entitlement)
    info("payments: #{bought} purchases, #{held} entitlements -> /admin/payments")
  end

  # N/10 reports over 500 pages, so the queue groups them; one in four still
  # open.
  defp seed_reports(user_ids) do
    Repo.delete_all(from(r in PageReport, where: like(r.subject_ref, "/demo-seed/%")),
      timeout: :infinity
    )

    now = DateTime.utc_now(:second)

    rows =
      user_ids
      |> Stream.take_every(10)
      |> Stream.with_index(1)
      |> Stream.map(fn {user_id, i} ->
        path = "/demo-seed/page-#{rem(i, 500)}"
        status = Enum.at(PageReport.statuses(), rem(i, 4))
        at = spread(now, i, 90 * 86_400)

        %{
          id: UUIDv7.generate(),
          kind: @page,
          subject_ref: path,
          subject: %{"path" => path},
          data: %{},
          description: "Demo report #{i}: the page shows the wrong word.",
          locale: LocaleCode.en(),
          source: ReportSource.web(),
          client: %{},
          attachments: %{},
          status: status,
          resolved_at: if(status != ReportStatus.open(), do: at),
          user_id: user_id,
          inserted_at: at,
          updated_at: at
        }
      end)
      |> insert_batches(PageReport)

    info("reports: #{rows} -> /admin/reports")
  end

  # Each player and the next are friends (every fifth still pending); the
  # first player has N/100 more.
  defp seed_friends([heavy | _] = user_ids) do
    Repo.delete_all(from(f in Friendship, where: f.requester_id in subquery(demo_user_ids())),
      timeout: :infinity
    )

    now = DateTime.utc_now(:second)

    chain =
      user_ids
      |> Stream.zip(tl(user_ids))
      |> Stream.with_index(1)
      |> Stream.map(fn {{a, b}, i} ->
        friendship_row(
          a,
          b,
          if(rem(i, 5) == 0, do: FriendshipStatus.pending(), else: FriendshipStatus.accepted()),
          i,
          now
        )
      end)

    circle =
      user_ids
      |> Stream.drop(2)
      |> Stream.take(div(length(user_ids), 100))
      |> Stream.with_index(1)
      |> Stream.map(fn {friend, i} ->
        friendship_row(friend, heavy, FriendshipStatus.accepted(), i, now)
      end)

    rows = insert_batches(Stream.concat(chain, circle), Friendship)
    info("friends: #{rows} friendships -> /admin/friends")
  end

  defp friendship_row(requester, target, status, i, now) do
    at = spread(now, i, @year_sec)

    %{
      id: UUIDv7.generate(),
      requester_id: requester,
      target_id: target,
      status: status,
      inserted_at: at,
      updated_at: at
    }
  end

  # A web session per player, signed in over the past two weeks.
  defp seed_sessions(user_ids) do
    Repo.delete_all(
      from(t in UserToken,
        where: t.context == ^@session and t.user_id in subquery(demo_user_ids())
      ),
      timeout: :infinity
    )

    now = DateTime.utc_now(:second)

    rows =
      user_ids
      |> Stream.with_index(1)
      |> Stream.map(fn {user_id, i} ->
        at = spread(now, i, 14 * 86_400)

        %{
          id: UUIDv7.generate(),
          token: :crypto.strong_rand_bytes(32),
          context: @session,
          user_id: user_id,
          authenticated_at: at,
          inserted_at: at
        }
      end)
      |> insert_batches(UserToken)

    info("sessions: #{rows} -> /admin/sessions")
  end

  # N/10 lobbies, every seventh hidden and every fifth locked.
  defp seed_lobbies(user_ids) do
    Repo.delete_all(from(l in Lobby, where: like(l.title, "Demo Seed Lobby %")),
      timeout: :infinity
    )

    now = DateTime.utc_now(:second)

    rows =
      user_ids
      |> Stream.take_every(10)
      |> Stream.with_index(1)
      |> Stream.map(fn {host_id, i} ->
        at = spread(now, i, 7 * 86_400)

        %{
          id: UUIDv7.generate(),
          title: "Demo Seed Lobby #{pad(i)}",
          host_id: host_id,
          max_users: 8,
          is_hidden: rem(i, 7) == 0,
          is_locked: rem(i, 5) == 0,
          metadata: %{},
          state: LobbyState.created(),
          state_changed_at: at,
          inserted_at: at,
          updated_at: at
        }
      end)
      |> insert_batches(Lobby)

    info("lobbies: #{rows} -> /admin/lobbies")
  end

  # N/100 bans, half on accounts and half on addresses; some expired, some
  # lifted, so the list has history.
  defp seed_bans([admin | players]) do
    Repo.delete_all(from(b in Ban, where: like(b.reason, ^"#{@prefix}:%")), timeout: :infinity)
    now = DateTime.utc_now(:second)

    rows =
      players
      |> Stream.take_every(100)
      |> Stream.with_index(1)
      |> Stream.map(fn {user_id, i} ->
        {kind, subject, user} =
          if rem(i, 2) == 0,
            do: {:account, user_id, user_id},
            else:
              {:ip, "10.#{rem(div(i, 65_536), 256)}.#{rem(div(i, 256), 256)}.#{rem(i, 256)}", nil}

        at = spread(now, i, 90 * 86_400)

        %{
          id: UUIDv7.generate(),
          kind: kind,
          subject: subject,
          user_id: user,
          expires_at: if(rem(i, 3) == 1, do: DateTime.add(at, 86_400)),
          lifted_at: if(rem(i, 5) == 0, do: now),
          lifted_by: if(rem(i, 5) == 0, do: admin),
          reason: "#{@prefix}: volume demo ban #{i}",
          source: :admin,
          banned_by: admin,
          inserted_at: at,
          updated_at: at
        }
      end)
      |> insert_batches(Ban)

    info("bans: #{rows} -> /admin/bans")
  end

  # Two stacks per player.
  defp seed_inventory(user_ids) do
    Repo.delete_all(from(i in InventoryItem, where: like(i.item, "demo_seed_%")),
      timeout: :infinity
    )

    now = DateTime.utc_now(:second)

    rows =
      user_ids
      |> Stream.with_index(1)
      |> Stream.flat_map(fn {user_id, i} ->
        for {item, quantity} <- [{"demo_seed_crate", rem(i, 9) + 1}, {"demo_seed_key", rem(i, 3)}] do
          %{
            id: UUIDv7.generate(),
            user_id: user_id,
            item: item,
            quantity: quantity,
            metadata: %{},
            inserted_at: now,
            updated_at: now
          }
        end
      end)
      |> insert_batches(InventoryItem)

    info("inventory: #{rows} items -> /admin/economy")
  end

  # What does not leave with the players: rows that keep a nil player, and the
  # ones that never had one.
  defp clean_volume do
    clean_analytics()

    Repo.delete_all(from(p in Purchase, where: like(p.order_id, ^"#{@prefix}-order-%")),
      timeout: :infinity
    )

    Repo.delete_all(from(r in PageReport, where: like(r.subject_ref, "/demo-seed/%")),
      timeout: :infinity
    )

    Repo.delete_all(from(l in Lobby, where: like(l.title, "Demo Seed Lobby %")),
      timeout: :infinity
    )

    Repo.delete_all(from(b in Ban, where: like(b.reason, ^"#{@prefix}:%")), timeout: :infinity)
    Repo.delete_all(from(e in KVEntry, where: like(e.key, ^"#{@prefix}:%")), timeout: :infinity)
  end

  # ── Helpers ───────────────────────────────────────────────────────────────

  # Streams `rows` into `schema` in statements under @max_params bind
  # parameters, four at once on Postgres (SQLite has one writer). Answers how
  # many rows went in.
  defp insert_batches(rows, schema) do
    size = max(div(@max_params, length(schema.__schema__(:fields))), 1)
    concurrency = if postgres?(), do: 4, else: 1

    rows
    |> Stream.chunk_every(size)
    |> Task.async_stream(fn chunk -> elem(Repo.insert_all(schema, chunk), 0) end,
      max_concurrency: concurrency,
      ordered: false,
      timeout: :infinity
    )
    |> Enum.reduce(0, fn {:ok, inserted}, total -> total + inserted end)
  end

  # After a bulk load the planner still holds the old row counts until
  # autovacuum gets round to it, and a plan made for a hundred rows is the wrong
  # one for a million. SQLite plans without statistics.
  defp analyze do
    if postgres?(), do: Repo.query!("ANALYZE", [], timeout: :infinity)
    :ok
  end

  # Built at runtime: a literal comparison against the compiled adapter is
  # folded by the type checker (see `Gamend.Repo`).
  defp postgres?, do: Repo.__adapter__() == Module.concat([Ecto, Adapters, Postgres])

  defp upsert(schema, lookup, attrs) do
    case Repo.get_by(schema, lookup) do
      nil ->
        now = DateTime.utc_now(:second)

        attrs =
          attrs
          |> Map.put(:id, UUIDv7.generate())
          |> Map.put_new(:inserted_at, now)
          |> Map.put_new(:updated_at, now)

        Repo.insert_all(schema, [attrs])
        Repo.get_by!(schema, lookup)

      found ->
        found
    end
  end

  # ── Results ───────────────────────────────────────────────────────────────

  @result_kinds ~w(match hangman word_search)
  @plays_per_player 12

  # A dozen plays for each of the first players: most finished, the newest
  # of each player still open; answers right and wrong, a hint now and then.
  # Written through `Gamend.Results`, then moved back in time.
  defp seed_results(user_ids) do
    players = Enum.take(user_ids, @max_runs)

    info(
      "recording #{@plays_per_player} plays for #{length(players)} players (this set ignores --count)"
    )

    for {user_id, p} <- Enum.with_index(players), n <- 1..@plays_per_player do
      kind = Enum.at(@result_kinds, rem(n + p, length(@result_kinds)))

      {:ok, result} =
        Gamend.Results.start(user_id, kind,
          metadata: %{"demo_seed" => true, "lang" => Enum.at(@demo_langs, rem(n, 4))}
        )

      Gamend.Results.record(result, "deal", nil, %{"seed" => :rand.uniform(1_000_000)})

      for q <- 1..10 do
        Gamend.Results.record(result, @answer, if(:rand.uniform() < 0.7, do: 1, else: 0), %{
          "question" => "q#{q}"
        })

        if :rand.uniform() < 0.1, do: Gamend.Results.record(result, "hint", 10)
      end

      if n < @plays_per_player, do: Gamend.Results.finish(result)
      backdate_result(result.id, (@plays_per_player - n) * 2 + p)
    end
  end

  # A play moved `hours` back, its end with it, its events' times kept.
  defp backdate_result(result_id, hours) do
    shift = -hours * 3600

    from(r in Gamend.Results.Result, where: r.id == ^result_id)
    |> Repo.all()
    |> Enum.each(fn result ->
      started = DateTime.add(result.started_at, shift, :second)
      ended = result.ended_at && DateTime.add(started, 90 + :rand.uniform(240), :second)

      from(r in Gamend.Results.Result, where: r.id == ^result_id)
      |> Repo.update_all(set: [started_at: started, ended_at: ended])
    end)
  end

  defp clean_results do
    seeded =
      from(r in Gamend.Results.Result, where: r.kind in ^@result_kinds)
      |> Repo.all()
      |> Enum.filter(&(&1.metadata["demo_seed"] == true))

    Enum.each(seeded, &Gamend.Results.delete/1)
    info("removed #{length(seeded)} seeded results")
  end

  defp info(message), do: IO.puts("  #{message}")
end
