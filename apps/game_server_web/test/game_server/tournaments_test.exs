defmodule GameServer.TournamentsTest do
  use GameServer.DataCase

  alias GameServer.AccountsFixtures
  alias GameServer.Tournaments
  alias GameServer.Tournaments.Tournament

  # Not @behaviour GameServer.Hooks: implements only the tournament callbacks
  # (they are optional callbacks; hooks dispatch by function export).
  defmodule CaptureHook do
    defp notify(msg) do
      case Application.get_env(:game_server, :hooks_test_pid) do
        nil -> :ok
        pid -> send(pid, msg)
      end

      :ok
    end

    def before_tournament_register(user, tournament) do
      notify({:before_tournament_register, user.id, tournament.id})

      if Application.get_env(:game_server, :tournament_reject_register) do
        {:error, :not_enough_coins}
      else
        {:ok, tournament}
      end
    end

    def after_tournament_register(user, tournament),
      do: notify({:after_tournament_register, user.id, tournament.id})

    def before_tournament_leave(user, tournament) do
      notify({:before_tournament_leave, user.id, tournament.id})

      if Application.get_env(:game_server, :tournament_reject_leave) do
        {:error, :entry_is_final}
      else
        {:ok, tournament}
      end
    end

    def tournament_match_ready(match), do: notify({:tournament_match_ready, match.id})
    def tournament_match_expired(match), do: notify({:tournament_match_expired, match.id})

    def before_tournament_result(match, winner) do
      notify({:before_tournament_result, match.id, winner})

      if Application.get_env(:game_server, :tournament_reject_result) do
        {:error, :invalid_report}
      else
        {:ok, winner}
      end
    end

    def after_tournament_match_resolved(match),
      do: notify({:after_tournament_match_resolved, match.id})

    def after_tournament_finished(tournament, standings),
      do: notify({:after_tournament_finished, tournament.id, standings})
  end

  setup do
    orig_mod = Application.get_env(:game_server_core, :hooks_module)
    Application.put_env(:game_server_core, :hooks_module, CaptureHook)
    Application.put_env(:game_server, :hooks_test_pid, self())

    on_exit(fn ->
      if orig_mod,
        do: Application.put_env(:game_server_core, :hooks_module, orig_mod),
        else: Application.delete_env(:game_server_core, :hooks_module)

      Application.delete_env(:game_server, :hooks_test_pid)
      Application.delete_env(:game_server, :tournament_reject_register)
      Application.delete_env(:game_server, :tournament_reject_leave)
      Application.delete_env(:game_server, :tournament_reject_result)
    end)

    :ok
  end

  defp create_tournament(attrs \\ %{}) do
    now = DateTime.utc_now(:second)

    defaults = %{
      slug: "test-cup-#{System.unique_integer([:positive])}",
      title: "Test Cup",
      starts_at: DateTime.add(now, 3600),
      round_window_sec: 600,
      bracket_size: 8
    }

    {:ok, tournament} = Tournaments.create_tournament(Map.merge(defaults, attrs))
    tournament
  end

  defp users(n), do: for(_ <- 1..n, do: AccountsFixtures.user_fixture())

  defp join_all(tournament, users) do
    Enum.map(users, fn user ->
      {:ok, entry} = Tournaments.join_tournament(user, tournament)
      entry
    end)
  end

  defp draw!(tournament) do
    {:ok, tournament} =
      Tournaments.update_tournament(tournament, %{starts_at: DateTime.utc_now(:second)})

    Tournaments.advance_lifecycle(tournament)
  end

  describe "create_tournament/1" do
    test "validates bracket size and windows" do
      assert {:error, changeset} = Tournaments.create_tournament(%{})
      assert %{slug: _, title: _, round_window_sec: _} = errors_on(changeset)

      # nil starts_at = manual start; recurring tournaments need the anchor
      assert {:error, changeset} =
               Tournaments.create_tournament(%{
                 slug: "recurring",
                 title: "R",
                 round_window_sec: 60,
                 recur: "0 0 * * 6"
               })

      assert %{starts_at: _} = errors_on(changeset)

      now = DateTime.utc_now(:second)

      assert {:error, changeset} =
               Tournaments.create_tournament(%{
                 slug: "bad",
                 title: "Bad",
                 starts_at: now,
                 round_window_sec: 60,
                 bracket_size: 6
               })

      assert %{bracket_size: _} = errors_on(changeset)

      assert {:error, changeset} =
               Tournaments.create_tournament(%{
                 slug: "bad",
                 title: "Bad",
                 starts_at: now,
                 ends_at: DateTime.add(now, -60),
                 round_window_sec: 60
               })

      assert %{ends_at: _} = errors_on(changeset)
    end
  end

  describe "registration" do
    test "join registers an entry and fires hooks" do
      tournament = create_tournament()
      user = AccountsFixtures.user_fixture()

      assert {:ok, entry} = Tournaments.join_tournament(user, tournament)
      assert entry.leader_id == user.id
      assert entry.state == "registered"
      assert_receive {:before_tournament_register, _, _}
      assert_receive {:after_tournament_register, _, _}

      assert {:error, :already_registered} = Tournaments.join_tournament(user, tournament)
    end

    test "before_tournament_register veto blocks joining" do
      tournament = create_tournament()
      user = AccountsFixtures.user_fixture()
      Application.put_env(:game_server, :tournament_reject_register, true)

      assert {:error, :not_enough_coins} = Tournaments.join_tournament(user, tournament)
      assert Tournaments.count_entries(tournament.id) == 0
    end

    test "max_entries caps the field" do
      tournament = create_tournament(%{max_entries: 2})
      [u1, u2, u3] = users(3)

      assert {:ok, _} = Tournaments.join_tournament(u1, tournament)
      assert {:ok, _} = Tournaments.join_tournament(u2, tournament)
      assert {:error, :tournament_full} = Tournaments.join_tournament(u3, tournament)
    end

    test "scheduled tournament with future registration window rejects joins" do
      now = DateTime.utc_now(:second)
      tournament = create_tournament(%{registration_opens_at: DateTime.add(now, 1800)})
      user = AccountsFixtures.user_fixture()

      assert {:error, :registration_closed} = Tournaments.join_tournament(user, tournament)
    end

    test "leave withdraws before the draw; hook can veto" do
      tournament = create_tournament()
      user = AccountsFixtures.user_fixture()
      {:ok, _} = Tournaments.join_tournament(user, tournament)

      Application.put_env(:game_server, :tournament_reject_leave, true)
      assert {:error, :entry_is_final} = Tournaments.leave_tournament(user, tournament)

      Application.put_env(:game_server, :tournament_reject_leave, false)
      assert {:ok, _} = Tournaments.leave_tournament(user, tournament)
      assert Tournaments.count_entries(tournament.id) == 0
    end
  end

  describe "draw" do
    test "four entries produce a bracket of 4 with two ready round-1 matches" do
      tournament = create_tournament()
      join_all(tournament, users(4))

      tournament = draw!(tournament)
      assert tournament.state == "running"

      assert [%{size: 4}] = Tournaments.list_brackets(tournament.id)
      matches = Tournaments.list_matches(tournament.id)
      assert length(matches) == 3

      round1 = Enum.filter(matches, &(&1.round == 1))
      assert length(round1) == 2
      assert Enum.all?(round1, &(&1.a_entry_id && &1.b_entry_id))

      assert_receive {:tournament_match_ready, _}
      assert_receive {:tournament_match_ready, _}

      assert Enum.all?(Tournaments.list_entries(tournament.id), &(&1.state == "active"))
    end

    test "three entries: top seed gets a bye resolved at draw" do
      tournament = create_tournament()
      join_all(tournament, users(3))

      tournament = draw!(tournament)
      matches = Tournaments.list_matches(tournament.id)

      byes = Enum.filter(matches, &(&1.round == 1 and &1.resolved_at != nil))
      assert [bye] = byes
      assert bye.metadata["bye"] == true
      assert bye.winner_entry_id

      # The byed entry is already seated in the final.
      final = Enum.find(matches, &(&1.round == 2))
      assert bye.winner_entry_id in [final.a_entry_id, final.b_entry_id]
    end

    test "ten entries split into two brackets" do
      tournament = create_tournament(%{bracket_size: 8})
      join_all(tournament, users(10))

      tournament = draw!(tournament)
      brackets = Tournaments.list_brackets(tournament.id)
      assert [%{index: 0, size: 8}, %{index: 1, size: 2}] = brackets
    end

    test "a single entry wins uncontested and the tournament finishes" do
      tournament = create_tournament()
      [user] = users(1)
      {:ok, _} = Tournaments.join_tournament(user, tournament)

      tournament = draw!(tournament)
      assert tournament.state == "finished"
      assert [entry] = Tournaments.list_entries(tournament.id)
      assert entry.state == "winner"
      assert_receive {:after_tournament_finished, _, _}
    end
  end

  describe "resolve_match/2" do
    setup do
      tournament = create_tournament()
      join_all(tournament, users(4))
      tournament = draw!(tournament)

      round1 =
        Tournaments.list_matches(tournament.id)
        |> Enum.filter(&(&1.round == 1))

      %{tournament: tournament, round1: round1}
    end

    test "winner advances into the final; champion finishes the tournament", %{
      tournament: tournament,
      round1: [m1, m2]
    } do
      assert {:ok, resolved} = Tournaments.resolve_match(m1.id, m1.a_entry_id)
      assert resolved.winner_entry_id == m1.a_entry_id
      assert_receive {:before_tournament_result, _, _}
      assert_receive {:after_tournament_match_resolved, _}

      final =
        Tournaments.list_matches(tournament.id)
        |> Enum.find(&(&1.round == 2))

      assert final.a_entry_id == m1.a_entry_id

      assert {:ok, _} = Tournaments.resolve_match(m2.id, m2.b_entry_id)

      final = Tournaments.get_match(final.id)
      assert final.a_entry_id && final.b_entry_id
      assert_receive {:tournament_match_ready, _}

      assert {:ok, _} = Tournaments.resolve_match(final.id, final.a_entry_id)

      tournament = Tournaments.get_tournament(tournament.id)
      assert tournament.state == "finished"

      champion = Enum.find(Tournaments.list_entries(tournament.id), &(&1.state == "winner"))
      assert champion.id == final.a_entry_id
      assert champion.wins == 2

      assert_receive {:after_tournament_finished, _, standings}
      assert [%{state: "winner"}] = Enum.map(standings.champions, &%{state: &1.state})
      assert [%{placement: 1} | _] = standings.entries
    end

    test "first write wins", %{round1: [m1, _m2]} do
      assert {:ok, _} = Tournaments.resolve_match(m1.id, m1.a_entry_id)
      assert {:error, :already_resolved} = Tournaments.resolve_match(m1.id, m1.b_entry_id)
    end

    test "winner must be one of the match entries", %{round1: [m1, m2]} do
      assert {:error, :invalid_winner} = Tournaments.resolve_match(m1.id, m2.a_entry_id)
      assert {:error, :invalid_winner} = Tournaments.resolve_match(m1.id, "not-an-id")
    end

    test "before_tournament_result veto leaves the match open", %{round1: [m1, _]} do
      Application.put_env(:game_server, :tournament_reject_result, true)
      assert {:error, :invalid_report} = Tournaments.resolve_match(m1.id, m1.a_entry_id)
      assert Tournaments.get_match(m1.id).resolved_at == nil
    end

    test ":no_winner eliminates both and byes the other finalist", %{
      tournament: tournament,
      round1: [m1, m2]
    } do
      assert {:ok, _} = Tournaments.resolve_match(m1.id, :no_winner)

      for entry_id <- [m1.a_entry_id, m1.b_entry_id] do
        entry = Enum.find(Tournaments.list_entries(tournament.id), &(&1.id == entry_id))
        assert entry.state == "eliminated"
      end

      # Second semifinal resolves: its winner takes the final on a bye.
      assert {:ok, _} = Tournaments.resolve_match(m2.id, m2.a_entry_id)

      final = Tournaments.list_matches(tournament.id) |> Enum.find(&(&1.round == 2))
      assert final.resolved_at
      assert final.winner_entry_id == m2.a_entry_id
      assert final.metadata["bye"] == true

      assert Tournaments.get_tournament(tournament.id).state == "finished"
    end

    test "update_match_metadata merges game scratch data", %{round1: [m1, _]} do
      assert {:ok, match} = Tournaments.update_match_metadata(m1.id, %{"lobby_id" => "abc"})
      assert match.metadata["lobby_id"] == "abc"

      assert {:ok, match} = Tournaments.update_match_metadata(m1.id, %{"runs" => 2})
      assert match.metadata == %{"lobby_id" => "abc", "runs" => 2}
    end

    test "my_match returns the caller's open match", %{tournament: tournament, round1: [m1, _]} do
      entry = Enum.find(Tournaments.list_entries(tournament.id), &(&1.id == m1.a_entry_id))
      match = Tournaments.my_match(tournament, entry.leader_id)
      assert match.id == m1.id

      {:ok, _} = Tournaments.resolve_match(m1.id, m1.b_entry_id)
      assert Tournaments.my_match(tournament, entry.leader_id) == nil
    end
  end

  describe "deadlines" do
    test "expired matches fire the hook, then the deadline_at policy applies" do
      tournament = create_tournament(%{round_window_sec: 600})
      join_all(tournament, users(2))
      tournament = draw!(tournament)

      [match] = Tournaments.list_matches(tournament.id)
      assert_receive {:tournament_match_ready, _}

      past = DateTime.add(DateTime.utc_now(:second), 700)
      Tournaments.tick(past)
      assert_receive {:tournament_match_expired, _}
      assert Tournaments.get_match(match.id).resolved_at == nil

      Tournaments.tick(DateTime.add(past, 60))
      match = Tournaments.get_match(match.id)
      assert match.resolved_at
      assert match.winner_entry_id == nil
      assert match.metadata["deadline_policy"] == true

      assert Tournaments.get_tournament(tournament.id).state == "finished"
    end

    test "advance_first_slot policy advances the first present entry" do
      tournament =
        create_tournament(%{round_window_sec: 600, deadline_policy: "advance_first_slot"})

      join_all(tournament, users(2))
      tournament = draw!(tournament)
      [match] = Tournaments.list_matches(tournament.id)

      past = DateTime.add(DateTime.utc_now(:second), 700)
      Tournaments.tick(past)
      Tournaments.tick(DateTime.add(past, 60))

      assert Tournaments.get_match(match.id).winner_entry_id == match.a_entry_id
    end
  end

  describe "lifecycle & recurrence" do
    test "nil starts_at stays in registration until an admin sets it (manual start)" do
      tournament = create_tournament(%{starts_at: nil})
      join_all(tournament, users(2))

      assert Tournaments.advance_lifecycle(tournament).state == "registration"
      Tournaments.tick()
      assert Tournaments.get_tournament(tournament.id).state == "registration"

      {:ok, tournament} =
        Tournaments.update_tournament(tournament, %{starts_at: DateTime.utc_now(:second)})

      assert Tournaments.advance_lifecycle(tournament).state == "running"
    end

    test "scheduled -> registration transition happens lazily" do
      now = DateTime.utc_now(:second)

      tournament =
        create_tournament(%{registration_opens_at: DateTime.add(now, -60)})

      assert Tournaments.advance_lifecycle(tournament).state == "registration"
    end

    test "finishing a recurring tournament spawns the next occurrence" do
      tournament = create_tournament(%{recur: "0 0 * * *", round_window_sec: 600})
      join_all(tournament, users(2))
      tournament = draw!(tournament)

      [match] = Tournaments.list_matches(tournament.id)
      {:ok, _} = Tournaments.resolve_match(match.id, match.a_entry_id)

      assert Tournaments.get_tournament(tournament.id).state == "finished"

      next =
        Tournaments.list_tournaments(slug: tournament.slug)
        |> Enum.find(&(&1.id != tournament.id))

      assert next
      assert next.state == "scheduled"
      assert DateTime.compare(next.starts_at, DateTime.utc_now()) == :gt
      assert next.recur == tournament.recur

      # Finishing again (idempotent tick) must not spawn duplicates.
      Tournaments.tick()
      assert length(Tournaments.list_tournaments(slug: tournament.slug)) == 2
    end

    test "get_tournament_by_slug prefers the live occurrence" do
      slug = "cup-#{System.unique_integer([:positive])}"
      _old = create_tournament(%{slug: slug, state: "finished"})
      current = create_tournament(%{slug: slug})

      assert Tournaments.get_tournament_by_slug(slug).id == current.id
    end
  end

  describe "bracket math" do
    test "standard_seed_order spreads top seeds" do
      assert Tournaments.standard_seed_order(2) == [1, 2]
      assert Tournaments.standard_seed_order(4) == [1, 4, 2, 3]
      assert Tournaments.standard_seed_order(8) == [1, 8, 4, 5, 2, 7, 3, 6]
    end

    test "bracket_size_for seats everyone within the cap" do
      assert Tournaments.bracket_size_for(2, 8) == 2
      assert Tournaments.bracket_size_for(3, 8) == 4
      assert Tournaments.bracket_size_for(5, 8) == 8
      assert Tournaments.bracket_size_for(9, 8) == 8
      assert Tournaments.bracket_size_for(3, 16) == 4
    end

    test "bracket_rounds and round_matches" do
      assert Tournaments.bracket_rounds(2) == 1
      assert Tournaments.bracket_rounds(8) == 3
      assert Tournaments.round_matches(8, 1) == 4
      assert Tournaments.round_matches(8, 3) == 1
    end
  end

  describe "reopen_tournament/1" do
    test "a cancelled tournament that was never drawn returns to registration" do
      tournament = create_tournament()
      join_all(tournament, users(2))
      {:ok, cancelled} = Tournaments.cancel_tournament(tournament)
      assert cancelled.state == "cancelled"

      assert {:ok, reopened} = Tournaments.reopen_tournament(cancelled)
      assert reopened.state == "registration"

      # registration works again
      assert {:ok, _} = Tournaments.join_tournament(AccountsFixtures.user_fixture(), reopened)
    end

    test "a cancelled tournament that was already drawn resumes running" do
      tournament = create_tournament()
      join_all(tournament, users(4))
      tournament = draw!(tournament)
      {:ok, cancelled} = Tournaments.cancel_tournament(tournament)

      assert {:ok, reopened} = Tournaments.reopen_tournament(cancelled)
      assert reopened.state == "running"
      # the draw is preserved
      assert length(Tournaments.list_matches(reopened.id)) == 3
    end

    test "only cancelled tournaments can be reopened" do
      tournament = create_tournament()
      assert {:error, :not_cancelled} = Tournaments.reopen_tournament(tournament)
    end
  end

  describe "stats/0" do
    test "counts tournaments, entries and matches by state" do
      tournament = create_tournament()
      join_all(tournament, users(3))
      tournament = draw!(tournament)

      # 3 entries in a bracket of 4: one round-1 bye resolves at the draw.
      stats = Tournaments.stats()

      assert stats.tournaments["running"] == 1
      assert stats.entries["active"] == 3
      assert stats.matches.total == 3
      assert stats.matches.open == 2
      assert stats.matches.overdue == 0

      open =
        Tournaments.list_matches(tournament.id)
        |> Enum.find(&(&1.round == 1 and is_nil(&1.resolved_at)))

      {:ok, _} = Tournaments.resolve_match(open.id, open.a_entry_id)

      stats = Tournaments.stats()
      assert stats.entries["eliminated"] == 1
      assert stats.matches.open == 1
    end

    test "overdue counts unresolved matches past their deadline_at" do
      tournament = create_tournament(%{round_window_sec: 600})
      join_all(tournament, users(2))

      # Deadlines anchor to starts_at, so a past start makes round 1 overdue.
      {:ok, tournament} =
        Tournaments.update_tournament(tournament, %{
          starts_at: DateTime.add(DateTime.utc_now(:second), -3600, :second)
        })

      _ = Tournaments.advance_lifecycle(tournament)

      stats = Tournaments.stats()
      assert stats.matches.open == 1
      assert stats.matches.overdue == 1
    end

    test "empty database reports zeroes" do
      stats = Tournaments.stats()
      assert stats.tournaments == %{}
      assert stats.entries == %{}
      assert stats.matches == %{total: 0, open: 0, overdue: 0}
    end
  end

  describe "list_entries/2 search and ordering" do
    defp named_user(display_name) do
      AccountsFixtures.user_fixture()
      |> Ecto.Changeset.change(display_name: display_name)
      |> GameServer.Repo.update!()
    end

    test "filters by leader name, case-insensitively and on partial matches" do
      tournament = create_tournament()
      join_all(tournament, [named_user("Ada Lovelace"), named_user("Grace Hopper")])

      assert [entry] =
               Tournaments.list_entries(tournament.id, search: "HOPP", preload_leader: true)

      assert entry.leader.display_name == "Grace Hopper"
      assert Tournaments.count_entries(tournament.id, search: "HOPP") == 1
      assert Tournaments.count_entries(tournament.id) == 2
    end

    test "falls back to the username when a player has no display name" do
      user =
        AccountsFixtures.user_fixture()
        |> Ecto.Changeset.change(username: "solo_flyer")
        |> GameServer.Repo.update!()

      tournament = create_tournament()
      join_all(tournament, [user])

      assert [_entry] = Tournaments.list_entries(tournament.id, search: "solo_fly")
    end

    test "treats LIKE wildcards in the search term literally" do
      tournament = create_tournament()
      join_all(tournament, [named_user("100% Effort"), named_user("Grace Hopper")])

      # "%" must match the character, not act as "everything"
      assert [entry] = Tournaments.list_entries(tournament.id, search: "0%", preload_leader: true)
      assert entry.leader.display_name == "100% Effort"
    end

    test "a blank search returns everyone" do
      tournament = create_tournament()
      join_all(tournament, users(3))

      assert length(Tournaments.list_entries(tournament.id, search: "")) == 3
      assert length(Tournaments.list_entries(tournament.id, search: "   ")) == 3
      assert Tournaments.count_entries(tournament.id, search: "") == 3
    end

    test "order: :bracket groups drawn entries by bracket and seed" do
      tournament = create_tournament(%{bracket_size: 4})
      join_all(tournament, users(8))
      draw!(tournament)

      entries = Tournaments.list_entries(tournament.id, order: :bracket)

      # two full brackets, each seeded 0..3, in that order
      assert Enum.map(entries, &{&1.bracket_index, &1.seed}) ==
               [{0, 0}, {0, 1}, {0, 2}, {0, 3}, {1, 0}, {1, 1}, {1, 2}, {1, 3}]
    end

    test "search and pagination agree on the total" do
      tournament = create_tournament()
      join_all(tournament, [named_user("Ada One"), named_user("Ada Two"), named_user("Bob")])

      assert Tournaments.count_entries(tournament.id, search: "ada") == 2

      assert length(Tournaments.list_entries(tournament.id, search: "ada", page: 1, page_size: 1)) ==
               1
    end
  end

  describe "tick" do
    test "draws due tournaments" do
      tournament = create_tournament()
      join_all(tournament, users(2))

      {:ok, _} =
        Tournaments.update_tournament(tournament, %{starts_at: DateTime.utc_now(:second)})

      Tournaments.tick()

      assert %Tournament{state: "running"} = Tournaments.get_tournament(tournament.id)
      assert_receive {:tournament_match_ready, _}
    end
  end
end
