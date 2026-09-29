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
    * `lobby_snapshot` — recorded runs for `/admin/lobby_snapshots`, capped at 12
      regardless of `--count` (this set is about having something to read, not
      volume)
    * `quest` — a daily, an auto-claim achievement, a chained follow-up and a
      twelve-member group that lists as one card, with per-user progress in
      every state (including claimable rows)
    * `ready_check` — one check per seeded lobby in every outcome (open,
      passed, timed out, declined), also capped at 12
    * `chat_moderation` — a blocklist across every severity and match mode, a
      report queue deep enough to page through (every status, some filter-filed,
      some resolved) and mutes in every scope, including expired ones

  The `lobby_snapshot` set goes through the real `capture_lobby/3` path rather
  than inserting rows, so what you see is shaped exactly like production data —
  including content-addressed section dedup. One of its runs reproduces the July
  2026 rubber-banding bug (a distance that reverts between snapshots), which is
  the case the section diff exists to make obvious.

  Seeded runs keep their lobby row so `--clean` can find them again. Real
  completed runs outlive theirs, since a lobby is deleted when its last member
  leaves.

  All sets share one pool of N anonymous device accounts, so the same players
  appear across them (as they would in a real deployment).

  Rows are inserted in bulk rather than through the contexts: this is about
  volume, not about exercising business rules, and 1000 individual writes on
  SQLite is slow. The cache is flushed afterwards so pages read the new rows.
  """

  import Ecto.Query

  alias Gamend.Accounts.User
  alias Gamend.Chat.FilterWord
  alias Gamend.Chat.Message
  alias Gamend.Chat.Moderation
  alias Gamend.Chat.Moderation.Normalizer
  alias Gamend.Chat.Mute
  alias Gamend.Chat.Report
  alias Gamend.Groups.Group
  alias Gamend.Groups.GroupMember
  alias Gamend.Leaderboards.Leaderboard
  alias Gamend.Leaderboards.Record
  alias Gamend.Lobbies.Lobby
  alias Gamend.LobbySnapshots
  alias Gamend.LobbySnapshots.Event, as: SnapshotEvent
  alias Gamend.LobbySnapshots.Snapshot
  alias Gamend.LobbySnapshots.Writer
  alias Gamend.Parties.Party
  alias Gamend.Push.PushToken
  alias Gamend.Quests.Quest
  alias Gamend.Quests.QuestProgress
  alias Gamend.ReadyChecks.Check, as: ReadyCheck
  alias Gamend.ReadyChecks.Participant, as: ReadyCheckParticipant
  alias Gamend.Repo
  alias Gamend.Tournaments.Entry
  alias Gamend.Tournaments.Tournament
  alias Gamend.UUIDv7

  @prefix "demo-seed"
  @leaderboard_slug "demo_seed_scores"
  @group_title "Demo Seed Group"
  @tournament_slug "demo-seed-cup"
  @quest_key_prefix "demo-seed-"
  @default_count 1000
  @batch 500
  @all_sets ~w(leaderboard group tournament lobby_snapshot quest push ready_check chat_moderation)
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
        "leaderboard" -> seed_leaderboard(users)
        "group" -> seed_group(users)
        "tournament" -> seed_tournament(users)
        "lobby_snapshot" -> seed_lobby_snapshots(users)
        "quest" -> seed_quests(users)
        "push" -> seed_push_tokens(users)
        "ready_check" -> seed_ready_checks(users)
        "chat_moderation" -> seed_chat_moderation(users)
      end)

      Gamend.Cache.delete_all()
      info("done — run `demo.seed --clean` to remove it again")
    end

    :ok
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
      from(u in User, where: like(u.device_id, ^"#{@prefix}-%"), select: {u.device_id, u.id})
      |> Repo.all()
      |> Map.new()

    missing =
      for i <- 1..count,
          device_id = device_id(i),
          not Map.has_key?(existing, device_id),
          do: {i, device_id}

    now = DateTime.utc_now(:second)

    missing
    |> Enum.map(fn {i, device_id} ->
      %{
        id: UUIDv7.generate(),
        device_id: device_id,
        username: username(i),
        display_name: display_name(i),
        is_admin: false,
        is_activated: true,
        metadata: %{},
        token_version: 0,
        inserted_at: now,
        updated_at: now
      }
    end)
    |> insert_batches(User)

    info("players: #{count} (#{length(missing)} new)")

    from(u in User,
      where: like(u.device_id, ^"#{@prefix}-%"),
      order_by: u.device_id,
      limit: ^count,
      select: u.id
    )
    |> Repo.all()
  end

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

    Repo.delete_all(from(r in Record, where: r.leaderboard_id == ^leaderboard.id))
    now = DateTime.utc_now(:second)

    user_ids
    |> Enum.map(fn user_id ->
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
  end

  defp seed_group(user_ids) do
    [creator | members] = user_ids
    group = demo_group(user_ids)

    Repo.delete_all(from(m in GroupMember, where: m.group_id == ^group.id))
    now = DateTime.utc_now(:second)

    rows =
      [%{user_id: creator, role: "admin"}] ++ Enum.map(members, &%{user_id: &1, role: "member"})

    rows
    |> Enum.map(fn row ->
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
      type: "public",
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
        state: "registration",
        registration_opens_at: DateTime.add(now, -3600),
        starts_at: DateTime.add(now, 7 * 86_400),
        round_window_sec: 3600,
        bracket_size: 8,
        team_size: 1,
        deadline_policy: "forfeit_both",
        metadata: %{}
      })

    Repo.delete_all(from(e in Entry, where: e.tournament_id == ^tournament.id))

    user_ids
    |> Enum.map(fn user_id ->
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
        reset: "daily",
        category: "Daily",
        objectives: [%{event: "login", target: 3, params: %{}}],
        rewards: [%{type: "currency", code: "gold", amount: 100}],
        auto_claim: false,
        active: true,
        metadata: %{}
      })

    achievement =
      upsert_quest(%{
        key: @quest_key_prefix <> "first-win",
        title: "Demo First Win",
        description: "Win your first demo match.",
        reset: "never",
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
        reset: "never",
        category: "Chained",
        objectives: [%{event: "demo_win", target: 10, params: %{}}],
        rewards: [%{type: "item", code: "loot_crate", amount: 1}],
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
          reset: "never",
          category: "Exploration",
          group_key: @quest_key_prefix <> "world-tour",
          group_title: "Sail the world",
          sort_order: i,
          objectives: [
            %{event: "demo_city_visited", target: 5, params: %{"country" => country}}
          ],
          rewards: [%{type: "currency", code: "gold", amount: 50}],
          auto_claim: false,
          active: true,
          metadata: %{}
        })
      end

    now = DateTime.utc_now(:second)
    today = Gamend.Quests.period_key("daily", now)

    Repo.delete_all(from(p in QuestProgress, where: like(p.quest_key, ^"#{@quest_key_prefix}%")))

    daily_rows =
      user_ids
      |> Enum.with_index()
      |> Enum.map(fn {user_id, i} ->
        completed? = rem(i, 3) == 0
        claimed? = rem(i, 6) == 0

        status =
          cond do
            claimed? -> "claimed"
            completed? -> "completed"
            true -> "active"
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
      |> Enum.with_index()
      |> Enum.filter(fn {_id, i} -> rem(i, 2) == 0 end)
      |> Enum.map(fn {user_id, _i} ->
        %{
          id: UUIDv7.generate(),
          user_id: user_id,
          quest_key: achievement.key,
          period_key: "static",
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
      |> Enum.with_index()
      |> Enum.filter(fn {_id, i} -> rem(i, 4) == 0 end)
      |> Enum.map(fn {user_id, i} ->
        %{
          id: UUIDv7.generate(),
          user_id: user_id,
          quest_key: chain.key,
          period_key: "static",
          objective_progress: %{"0" => rem(i, 10)},
          status: "active",
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
          period_key: "static",
          objective_progress: %{"0" => rem(i, 5) + 1},
          status: "active",
          completed_at: nil,
          claimed_at: nil,
          rewards_granted_at: nil,
          metadata: %{},
          inserted_at: now,
          updated_at: now
        }
      end

    rows = daily_rows ++ achievement_rows ++ chain_rows ++ group_rows
    insert_batches(rows, QuestProgress)

    info(
      "quests: #{3 + length(group_members)} definitions, #{length(rows)} progress rows -> /admin/quests"
    )
  end

  # Definitions go through the context (embeds can't be bulk-inserted).
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
    Repo.delete_all(from(p in QuestProgress, where: like(p.quest_key, ^"#{@quest_key_prefix}%")))
    Repo.delete_all(from(q in Quest, where: like(q.key, ^"#{@quest_key_prefix}%")))
  end

  # One device per player (platform/provider cycling), every tenth disabled so
  # the admin page shows the dead-token state. Log provider, so a test push
  # against this data is observable in the server log. Rows cascade-delete
  # with their demo user on clean.
  defp seed_push_tokens(user_ids) do
    Repo.delete_all(from(t in PushToken, where: like(t.token, ^"#{@prefix}-token-%")))
    now = DateTime.utc_now(:second)

    user_ids
    |> Enum.with_index()
    |> Enum.map(fn {user_id, i} ->
      {platform, provider} =
        case rem(i, 3) do
          0 -> {"android", "fcm"}
          1 -> {"ios", "apns"}
          2 -> {"web", "fcm"}
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
            0 -> {"pending", nil}
            1 -> {"passed", nil}
            2 -> {"failed", "timeout"}
            3 -> {"failed", "declined"}
          end

        lobby =
          upsert(Lobby, [title: "#{@lobby_title_prefix} Ready #{pad(i)}"], %{
            title: "#{@lobby_title_prefix} Ready #{pad(i)}",
            host_id: host_id,
            max_users: 4,
            metadata: %{},
            state: "created",
            state_changed_at: now
          })

        %{
          id: UUIDv7.generate(),
          kind: if(rem(i, 3) == 0, do: "accept", else: "ready"),
          status: status,
          lobby_id: lobby.id,
          deadline_at: DateTime.add(now, 15, :second),
          opened_by: host_id,
          reason: reason,
          resolved_at: if(status != "pending", do: now),
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

  defp participant_state(%{status: "passed"}, _index), do: "ready"
  defp participant_state(%{status: "failed", reason: "declined"}, 0), do: "declined"
  defp participant_state(%{status: "failed", reason: "timeout"}, 0), do: "timed_out"
  defp participant_state(%{status: "pending"}, 0), do: "pending"
  defp participant_state(_check, _index), do: "ready"

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
        state: "created",
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

    Repo.delete_all(from(r in Report, where: r.message_id in subquery(message_ids)))
    Repo.delete_all(from(m in Message, where: m.chat_ref_id in ^room_ids))
    Repo.delete_all(from(m in Mute, where: m.user_id in subquery(demo_user_ids())))
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
        at = DateTime.add(now, -(i * 900 + 60), :second)

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

    rows =
      messages
      |> Enum.zip(reporters)
      |> Enum.with_index()
      |> Enum.map(fn {{message, reporter_id}, i} ->
        {status, note} = report_status(i)
        {_content, reason, flagged?} = chat_line(i)
        at = DateTime.add(now, -i * 900, :second)

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

    insert_batches(rows, Report)
    length(rows)
  end

  defp report_status(i) do
    case rem(i, 4) do
      0 -> {"open", nil}
      1 -> {"reviewing", nil}
      2 -> {"actioned", "24h mute — third report this week."}
      3 -> {"dismissed", "Heated, but inside the rules."}
    end
  end

  # Every scope, and a spread of permanent / expiring / already expired so the
  # sweep has rows to reap. One mute per player keeps the unique index happy.
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
          user_id: user_id,
          scope: scope,
          scope_ref_id: scope_ref_id,
          expires_at: expires_at,
          reason: reason,
          muted_by: moderator,
          inserted_at: now,
          updated_at: now
        }
      end)

    insert_batches(rows, Mute)
    length(rows)
  end

  defp mute_scope(rooms, i) do
    case rem(i, 4) do
      0 -> {"global", nil}
      1 -> {"lobby", Map.fetch!(rooms, "lobby")}
      2 -> {"group", Map.fetch!(rooms, "group")}
      3 -> {"party", Map.fetch!(rooms, "party")}
    end
  end

  defp mute_expiry(now, i) do
    case rem(div(i, 4), 3) do
      0 -> {nil, "Permanent — ban evasion."}
      1 -> {DateTime.add(now, 900), "Cooling off, back in 15 minutes."}
      2 -> {DateTime.add(now, -86_400), "Expired yesterday; waiting for the sweep."}
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

    if lb, do: Repo.delete_all(from(r in Record, where: r.leaderboard_id == ^lb.id))
    if group, do: Repo.delete_all(from(m in GroupMember, where: m.group_id == ^group.id))
    if tournament, do: Repo.delete_all(from(e in Entry, where: e.tournament_id == ^tournament.id))

    if lb, do: Repo.delete(lb)
    if group, do: Repo.delete(group)
    if tournament, do: Repo.delete(tournament)

    # Before the players go: seeded lobbies reference them as host.
    clean_lobby_snapshots()
    clean_quests()

    # Reports, mutes and messages cascade with their players; the blocklist has
    # no player to hang off.
    clean_filter_words()

    {users, _} = Repo.delete_all(from(u in User, where: like(u.device_id, ^"#{@prefix}-%")))

    Gamend.Cache.delete_all()
    info("removed demo data (#{users} players)")
  end

  # ── Helpers ───────────────────────────────────────────────────────────────

  # insert_all rejects oversized statements, so rows go in batches.
  defp insert_batches([], _schema), do: :ok

  defp insert_batches(rows, schema) do
    rows
    |> Enum.chunk_every(@batch)
    |> Enum.each(&Repo.insert_all(schema, &1))
  end

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

  # ── Lobby snapshots ───────────────────────────────────────────────────────

  defp seed_lobby_snapshots(user_ids) do
    previous = Application.get_env(:gamend_core, Gamend.LobbySnapshots, [])

    # Capture is off by default, so force it on for the duration rather than
    # making the operator set an env var to seed demo data.
    Application.put_env(
      :gamend_core,
      Gamend.LobbySnapshots,
      Keyword.merge(previous, enabled: true)
    )

    hosts = Enum.take(user_ids, @max_runs)
    info("recording #{length(hosts)} runs (this set ignores --count)")

    hosts
    |> Enum.with_index()
    |> Enum.each(fn {host_id, index} -> record_run(host_id, index) end)

    Writer.flush()
    backdate_runs()

    Application.put_env(:gamend_core, Gamend.LobbySnapshots, previous)
  end

  # Run 0 is the interesting one: it replays the shape of the July 2026
  # rubber-banding bug, where the boat's distance and the slow's anchor both
  # revert. Expanding snapshot 4 in the admin view shows it as a change *back*.
  defp record_run(host_id, 0), do: play(host_id, "rubber-band", rubber_band_frames())
  defp record_run(host_id, 1), do: play(host_id, "hook error", error_frames())
  defp record_run(host_id, index), do: play(host_id, "run #{index}", normal_frames(index))

  defp play(host_id, label, frames) do
    {:ok, lobby} =
      Gamend.Lobbies.create_lobby(%{
        title: "#{@lobby_title_prefix} — #{label}",
        host_id: host_id,
        max_users: 4
      })

    Enum.each(frames, fn frame ->
      {:ok, _} =
        Gamend.Lobbies.update_lobby(
          Repo.get!(Lobby, lobby.id),
          %{metadata: frame.metadata}
        )

      LobbySnapshots.capture_lobby(lobby.id, frame.trigger,
        sync: true,
        flagged: Map.get(frame, :flagged, false),
        user_id: host_id
      )

      Enum.each(Map.get(frame, :events, []), fn {kind, payload} ->
        LobbySnapshots.record_event(lobby.id, kind, payload, user_id: host_id)
      end)
    end)
  end

  defp boat(distance, speed, anchor) do
    %{
      "boat_adventure" => %{
        "distance" => distance,
        "speed" => speed,
        "effects" => %{
          "speed_reduced" => %{"distance_at_start" => anchor, "duration_ms" => 4000}
        },
        "actors" => [%{"type" => "starfish", "wave" => 1, "hp" => 2}]
      },
      "word_match" => %{"score" => round(distance / 10), "current_word" => "harbour"},
      "game_state" => "running"
    }
  end

  defp rubber_band_frames do
    [
      %{trigger: "hook:start_boat_game", metadata: boat(0.0, 100, 0.0)},
      %{
        trigger: "hook:guess_word",
        metadata: boat(120.0, 100, 0.0),
        events: [{"boat.speed", %{"from" => 100, "to" => 100, "gap" => 91.2}}]
      },
      %{
        trigger: "timer:scheduled_collision",
        metadata: boat(250.0, 50, 250.0),
        events: [
          {"boat.collision", %{"actor" => "starfish", "wave" => 1, "damage" => 1}},
          {"boat.speed", %{"from" => 100, "to" => 50, "gap" => 78.39, "targets_ahead" => 8}}
        ]
      },
      %{trigger: "hook:guess_word", metadata: boat(370.0, 50, 250.0)},
      # The bug: a stale client echo re-anchors the slow, dragging distance back.
      %{
        trigger: "hook:guess_word",
        metadata: boat(250.0, 50, 250.0),
        events: [{"boat.merge_divergence", %{"current" => 370.0, "incoming" => 250.0}}]
      },
      %{trigger: "hook:guess_word", metadata: boat(480.0, 100, 250.0)},
      %{trigger: "lobby:deleted", metadata: boat(480.0, 100, 250.0) |> finished()}
    ]
  end

  defp error_frames do
    [
      %{trigger: "hook:start_boat_game", metadata: boat(0.0, 100, 0.0)},
      %{trigger: "hook:guess_word", metadata: boat(90.0, 100, 0.0)},
      %{
        trigger: "hook:finish_boat_game",
        metadata: boat(90.0, 100, 0.0),
        flagged: true,
        events: [{"hook.error", %{"reason" => "function_clause", "hook" => "finish_boat_game"}}]
      }
    ]
  end

  defp normal_frames(index) do
    steps = 3 + rem(index, 3)

    frames =
      for step <- 0..steps do
        distance = step * 140.0 + index * 10
        speed = if rem(step, 3) == 2, do: 50, else: 100

        %{
          trigger: if(step == 0, do: "hook:start_boat_game", else: "hook:guess_word"),
          metadata: boat(distance, speed, if(speed == 50, do: distance, else: 0.0)),
          events:
            if(speed == 50,
              do: [{"boat.speed", %{"from" => 100, "to" => 50, "gap" => 62.5}}],
              else: []
            )
        }
      end

    # Every run ends the way a real one does: the last member leaves and the
    # lobby is torn down.
    teardown = %{trigger: "lobby:deleted", metadata: finished(List.last(frames).metadata)}

    Enum.reverse([teardown | Enum.reverse(frames)])
  end

  defp finished(metadata), do: put_in(metadata, ["game_state"], "finished")

  # Captures happen milliseconds apart, which makes every run look simultaneous
  # in the list view. Spread them so durations and start times read like real
  # sessions — and so the retention window has something meaningful to act on.
  defp backdate_runs do
    lobby_ids =
      from(l in Lobby,
        where: like(l.title, ^"#{@lobby_title_prefix}%"),
        order_by: l.inserted_at,
        select: l.id
      )
      |> Repo.all()

    lobby_ids
    |> Enum.with_index()
    |> Enum.each(fn {lobby_id, run_index} ->
      started = DateTime.add(DateTime.utc_now(), -(run_index * 5 + 1) * 3600, :second)

      shift_rows(Snapshot, lobby_id, started)
      shift_rows(SnapshotEvent, lobby_id, started)
    end)
  end

  defp shift_rows(schema, lobby_id, started) do
    ids =
      from(r in schema,
        where: r.lobby_id == ^lobby_id,
        order_by: [asc: r.inserted_at, asc: r.id],
        select: r.id
      )
      |> Repo.all()

    ids
    |> Enum.with_index()
    |> Enum.each(fn {id, step} ->
      at = DateTime.add(started, step * 6, :second)
      Repo.update_all(from(r in schema, where: r.id == ^id), set: [inserted_at: at])
    end)
  end

  defp clean_lobby_snapshots do
    lobby_ids =
      from(l in Lobby, where: like(l.title, ^"#{@lobby_title_prefix}%"))
      |> Repo.all()
      |> Enum.map(& &1.id)

    if lobby_ids != [] do
      Repo.delete_all(from(s in Snapshot, where: s.lobby_id in ^lobby_ids))

      Repo.delete_all(from(e in SnapshotEvent, where: e.lobby_id in ^lobby_ids))

      Enum.each(lobby_ids, fn id ->
        case Repo.get(Lobby, id) do
          nil -> :ok
          lobby -> Gamend.Lobbies.delete_lobby(lobby)
        end
      end)
    end

    # Blobs are content-addressed and may be shared with real runs, so they are
    # left for the retention sweep's reference-aware GC rather than deleted here.
    info("removed #{length(lobby_ids)} seeded runs")
  end

  defp info(message), do: IO.puts("  #{message}")
end
