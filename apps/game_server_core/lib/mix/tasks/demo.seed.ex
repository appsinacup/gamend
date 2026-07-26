defmodule Mix.Tasks.Demo.Seed do
  @shortdoc "Seeds large volumes of demo data (leaderboard, group, tournament)"

  @moduledoc """
  Fills the database with enough demo data to exercise pagination and the
  list/detail pages at realistic sizes.

  Everything is namespaced with a `demo-seed` prefix so `--clean` can remove it
  again without touching real data.

  ## Usage

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
    * `quest` — a daily, an auto-claim achievement and a chained follow-up,
      with per-user progress in every state (including claimable rows)
    * `ready_check` — one check per seeded lobby in every outcome (open,
      passed, timed out, declined), also capped at 12

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

  use Mix.Task

  import Ecto.Query

  alias GameServer.Accounts.User
  alias GameServer.Groups.Group
  alias GameServer.Groups.GroupMember
  alias GameServer.Leaderboards.Leaderboard
  alias GameServer.Leaderboards.Record
  alias GameServer.Lobbies.Lobby
  alias GameServer.LobbySnapshots
  alias GameServer.LobbySnapshots.Event, as: SnapshotEvent
  alias GameServer.LobbySnapshots.Snapshot
  alias GameServer.LobbySnapshots.Writer
  alias GameServer.Push.PushToken
  alias GameServer.Quests.Quest
  alias GameServer.Quests.QuestProgress
  alias GameServer.ReadyChecks.Check, as: ReadyCheck
  alias GameServer.ReadyChecks.Participant, as: ReadyCheckParticipant
  alias GameServer.Repo
  alias GameServer.Tournaments.Entry
  alias GameServer.Tournaments.Tournament
  alias GameServer.UUIDv7

  @prefix "demo-seed"
  @leaderboard_slug "demo_seed_scores"
  @group_title "Demo Seed Group"
  @tournament_slug "demo-seed-cup"
  @quest_key_prefix "demo-seed-"
  @default_count 1000
  @batch 500
  @all_sets ~w(leaderboard group tournament lobby_snapshot quest push ready_check)
  @lobby_title_prefix "Demo Seed Run"
  @max_runs 12

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

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
      end)

      GameServer.Cache.delete_all()
      info("done — run `mix demo.seed --clean` to remove it again")
    end
  end

  defp parse_sets(nil), do: @all_sets

  defp parse_sets(only) do
    sets = only |> String.split(",", trim: true) |> Enum.map(&String.trim/1)

    case sets -- @all_sets do
      [] ->
        sets

      unknown ->
        Mix.raise(
          "unknown set(s): #{Enum.join(unknown, ", ")} (known: #{Enum.join(@all_sets, ", ")})"
        )
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

    group =
      upsert(Group, [title: @group_title], %{
        title: @group_title,
        description: "Volume demo data.",
        type: "public",
        max_members: length(user_ids) + 10,
        creator_id: creator,
        metadata: %{}
      })

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

  # A daily, an auto-claim achievement, and a chain gated on it — with per-user
  # progress in every state, including claimable completed rows.
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

    now = DateTime.utc_now(:second)
    today = GameServer.Quests.period_key("daily", now)

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

    insert_batches(daily_rows ++ achievement_rows ++ chain_rows, QuestProgress)

    info(
      "quests: 3 definitions, #{length(daily_rows) + length(achievement_rows) + length(chain_rows)} progress rows -> /admin/quests"
    )
  end

  # Definitions go through the context (embeds can't be bulk-inserted).
  defp upsert_quest(attrs) do
    case Repo.get_by(Quest, key: attrs.key) do
      nil ->
        {:ok, quest} = GameServer.Quests.create_quest(attrs)
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

    {users, _} = Repo.delete_all(from(u in User, where: like(u.device_id, ^"#{@prefix}-%")))

    GameServer.Cache.delete_all()
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
    previous = Application.get_env(:game_server_core, GameServer.LobbySnapshots, [])

    # Capture is off by default, so force it on for the duration rather than
    # making the operator set an env var to seed demo data.
    Application.put_env(
      :game_server_core,
      GameServer.LobbySnapshots,
      Keyword.merge(previous, enabled: true)
    )

    hosts = Enum.take(user_ids, @max_runs)
    info("recording #{length(hosts)} runs (this set ignores --count)")

    hosts
    |> Enum.with_index()
    |> Enum.each(fn {host_id, index} -> record_run(host_id, index) end)

    Writer.flush()
    backdate_runs()

    Application.put_env(:game_server_core, GameServer.LobbySnapshots, previous)
  end

  # Run 0 is the interesting one: it replays the shape of the July 2026
  # rubber-banding bug, where the boat's distance and the slow's anchor both
  # revert. Expanding snapshot 4 in the admin view shows it as a change *back*.
  defp record_run(host_id, 0), do: play(host_id, "rubber-band", rubber_band_frames())
  defp record_run(host_id, 1), do: play(host_id, "hook error", error_frames())
  defp record_run(host_id, index), do: play(host_id, "run #{index}", normal_frames(index))

  defp play(host_id, label, frames) do
    {:ok, lobby} =
      GameServer.Lobbies.create_lobby(%{
        title: "#{@lobby_title_prefix} — #{label}",
        host_id: host_id,
        max_users: 4
      })

    Enum.each(frames, fn frame ->
      {:ok, _} =
        GameServer.Lobbies.update_lobby(
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
          lobby -> GameServer.Lobbies.delete_lobby(lobby)
        end
      end)
    end

    # Blobs are content-addressed and may be shared with real runs, so they are
    # left for the retention sweep's reference-aware GC rather than deleted here.
    info("removed #{length(lobby_ids)} seeded runs")
  end

  defp info(message), do: Mix.shell().info("  #{message}")
end
