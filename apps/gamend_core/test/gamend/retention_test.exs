defmodule Gamend.RetentionTest do
  use Gamend.DataCase, async: false

  alias Gamend.Accounts.{User, UserToken}
  alias Gamend.AccountsFixtures
  alias Gamend.Groups.GroupInvite
  alias Gamend.Lobbies
  alias Gamend.Lobbies.Lobby
  alias Gamend.Matchmaking.Ticket
  alias Gamend.Parties
  alias Gamend.Parties.Party
  alias Gamend.Repo
  alias Gamend.Retention

  defp backdate(schema, id, days) do
    cutoff = DateTime.add(DateTime.utc_now(:second), -days, :day)

    Repo.update_all(
      from(r in schema, where: r.id == ^id),
      set: [inserted_at: cutoff]
    )
  end

  setup do
    original = Application.get_env(:gamend_core, Gamend.Retention, [])

    on_exit(fn ->
      Application.put_env(:gamend_core, Gamend.Retention, original)
    end)

    :ok
  end

  test "prunes chat messages older than the configured retention" do
    Application.put_env(:gamend_core, Gamend.Retention, chat_messages_days: 30)

    a = AccountsFixtures.user_fixture()

    old =
      Repo.insert!(%Gamend.Chat.Message{
        sender_id: a.id,
        content: "old",
        chat_type: "lobby",
        chat_ref_id: Ecto.UUID.generate()
      })

    fresh =
      Repo.insert!(%Gamend.Chat.Message{
        sender_id: a.id,
        content: "fresh",
        chat_type: "lobby",
        chat_ref_id: Ecto.UUID.generate()
      })

    backdate(Gamend.Chat.Message, old.id, 31)

    results = Retention.prune_all()

    assert results.chat_messages == 1
    refute Repo.get(Gamend.Chat.Message, old.id)
    assert Repo.get(Gamend.Chat.Message, fresh.id)
  end

  test "retention of 0 keeps everything" do
    Application.put_env(:gamend_core, Gamend.Retention, chat_messages_days: 0)

    a = AccountsFixtures.user_fixture()

    old =
      Repo.insert!(%Gamend.Chat.Message{
        sender_id: a.id,
        content: "old",
        chat_type: "lobby",
        chat_ref_id: Ecto.UUID.generate()
      })

    backdate(Gamend.Chat.Message, old.id, 400)

    results = Retention.prune_all()

    assert results.chat_messages == 0
    assert Repo.get(Gamend.Chat.Message, old.id)
  end

  test "prunes expired ip bans but keeps permanent and future ones" do
    now = DateTime.utc_now(:second)

    expired =
      Repo.insert!(%Gamend.IpBans.IpBan{ip: "10.0.0.1", expires_at: DateTime.add(now, -60)})

    future =
      Repo.insert!(%Gamend.IpBans.IpBan{ip: "10.0.0.2", expires_at: DateTime.add(now, 3600)})

    permanent = Repo.insert!(%Gamend.IpBans.IpBan{ip: "10.0.0.3", expires_at: nil})

    results = Retention.prune_all()

    assert results.expired_ip_bans == 1
    refute Repo.get(Gamend.IpBans.IpBan, expired.id)
    assert Repo.get(Gamend.IpBans.IpBan, future.id)
    assert Repo.get(Gamend.IpBans.IpBan, permanent.id)
  end

  describe "lobby snapshots" do
    alias Gamend.LobbySnapshots.{Blob, Event, Snapshot}

    defp snapshot!(lobby_id, opts \\ []) do
      snapshot =
        Repo.insert!(%Snapshot{
          lobby_id: lobby_id,
          trigger: Keyword.get(opts, :trigger, "test"),
          flagged: Keyword.get(opts, :flagged, false),
          section_hashes: Keyword.get(opts, :section_hashes, %{}),
          inserted_at: DateTime.utc_now()
        })

      if days = opts[:days_old], do: backdate(Snapshot, snapshot.id, days)
      snapshot
    end

    defp event!(lobby_id, opts \\ []) do
      event =
        Repo.insert!(%Event{
          lobby_id: lobby_id,
          kind: "test.event",
          payload: %{},
          inserted_at: DateTime.utc_now()
        })

      if days = opts[:days_old], do: backdate(Event, event.id, days)
      event
    end

    defp blob!(hash, days_referenced_ago) do
      at = DateTime.add(DateTime.utc_now(), -days_referenced_ago, :day)

      Repo.insert!(%Blob{
        hash: hash,
        content: %{"v" => %{}},
        byte_size: 2,
        last_referenced_at: at,
        inserted_at: at
      })
    end

    setup do
      Application.put_env(:gamend_core, Gamend.Retention,
        lobby_snapshots_days: 30,
        lobby_snapshots_flagged_days: 90
      )

      :ok
    end

    test "prunes snapshots and events past the window, keeping recent ones" do
      lobby = Ecto.UUID.generate()

      old_snapshot = snapshot!(lobby, days_old: 40)
      old_event = event!(lobby, days_old: 40)
      fresh_snapshot = snapshot!(lobby)
      fresh_event = event!(lobby)

      Retention.prune_all()

      refute Repo.get(Snapshot, old_snapshot.id)
      refute Repo.get(Event, old_event.id)
      assert Repo.get(Snapshot, fresh_snapshot.id)
      assert Repo.get(Event, fresh_event.id)
    end

    test "a flagged run keeps its whole timeline, unflagged snapshots included" do
      flagged_lobby = Ecto.UUID.generate()
      plain_lobby = Ecto.UUID.generate()

      # Flagged is a property of the run, not the row: the unflagged snapshot
      # below is part of the same run and must survive with it.
      flagged = snapshot!(flagged_lobby, days_old: 40, flagged: true)
      alongside = snapshot!(flagged_lobby, days_old: 40)
      flagged_event = event!(flagged_lobby, days_old: 40)

      plain = snapshot!(plain_lobby, days_old: 40)
      plain_event = event!(plain_lobby, days_old: 40)

      Retention.prune_all()

      assert Repo.get(Snapshot, flagged.id)
      assert Repo.get(Snapshot, alongside.id)
      assert Repo.get(Event, flagged_event.id)
      refute Repo.get(Snapshot, plain.id)
      refute Repo.get(Event, plain_event.id)
    end

    test "flagged runs expire once past the longer window" do
      lobby = Ecto.UUID.generate()

      ancient = snapshot!(lobby, days_old: 100, flagged: true)
      ancient_event = event!(lobby, days_old: 100)

      Retention.prune_all()

      refute Repo.get(Snapshot, ancient.id)
      refute Repo.get(Event, ancient_event.id)
    end

    test "keeps a blob an old snapshot still references" do
      # The dedup hazard: this blob's content was first stored long ago, but a
      # recent snapshot reuses it. Pruning on age alone would delete live
      # content — last_referenced_at is what prevents that.
      reused = blob!("reused", 0)
      stale = blob!("stale", 100)

      _recent = snapshot!(Ecto.UUID.generate(), section_hashes: %{"lobby" => "reused"})

      Retention.prune_all()

      assert Repo.get(Blob, reused.hash)
      refute Repo.get(Blob, stale.hash)
    end

    test "keeps everything when the window is disabled" do
      Application.put_env(:gamend_core, Gamend.Retention, lobby_snapshots_days: 0)

      lobby = Ecto.UUID.generate()
      ancient = snapshot!(lobby, days_old: 500)
      ancient_blob = blob!("ancient", 500)

      Retention.prune_all()

      assert Repo.get(Snapshot, ancient.id)
      assert Repo.get(Blob, ancient_blob.hash)
    end

    test "a flagged window shorter than the normal one does not expire flagged runs first" do
      Application.put_env(:gamend_core, Gamend.Retention,
        lobby_snapshots_days: 30,
        lobby_snapshots_flagged_days: 1
      )

      lobby = Ecto.UUID.generate()
      flagged = snapshot!(lobby, days_old: 10, flagged: true)

      Retention.prune_all()

      assert Repo.get(Snapshot, flagged.id)
    end
  end

  defp unique, do: System.unique_integer([:positive])

  describe "lobbies" do
    defp lobby_fixture(attrs \\ %{}) do
      {:ok, lobby} =
        Lobbies.create_lobby(Map.merge(%{title: "L#{unique()}"}, attrs))

      lobby
    end

    defp age_lobby(lobby, minutes) do
      at = DateTime.add(DateTime.utc_now(:second), -minutes, :minute)

      Repo.update_all(from(l in Lobby, where: l.id == ^lobby.id),
        set: [updated_at: at, state_changed_at: at]
      )

      lobby
    end

    defp put_member(lobby, user, opts) do
      Repo.update_all(from(u in User, where: u.id == ^user.id),
        set: [
          lobby_id: lobby.id,
          is_online: Keyword.get(opts, :online, false),
          last_seen_at: Keyword.get(opts, :last_seen)
        ]
      )
    end

    test "reaps a lobby nobody has been seen in past the window" do
      Application.put_env(:gamend_core, Gamend.Retention, abandoned_lobby_minutes: 15)

      quiet = age_lobby(lobby_fixture(), 20)
      fresh = lobby_fixture()

      Retention.prune_all()

      refute Repo.get(Lobby, quiet.id)
      assert Repo.get(Lobby, fresh.id)
    end

    test "the live cycle reaps it too, and runs nothing else" do
      Application.put_env(:gamend_core, Gamend.Retention, abandoned_lobby_minutes: 15)

      quiet = age_lobby(lobby_fixture(), 20)
      results = Retention.prune_live()

      assert results |> Map.keys() |> Enum.sort() ==
               [
                 :abandoned_parties,
                 :lobbies,
                 :offline_lobby_memberships,
                 :offline_party_memberships
               ]

      assert results.lobbies == 1
      refute Repo.get(Lobby, quiet.id)
    end

    test "keeps a lobby inside the window" do
      Application.put_env(:gamend_core, Gamend.Retention, abandoned_lobby_minutes: 60)

      quiet = age_lobby(lobby_fixture(), 20)

      Retention.prune_all()

      assert Repo.get(Lobby, quiet.id)
    end

    # An ended match is the game's business: it deletes its own lobby. Core
    # reaps on silence alone, so state never changes the outcome.
    test "state does not change what is reaped" do
      Application.put_env(:gamend_core, Gamend.Retention, abandoned_lobby_minutes: 15)

      {:ok, ended} = Lobbies.transition_state(lobby_fixture(), "ended")
      {:ok, playing} = Lobbies.transition_state(lobby_fixture(), "playing")
      fresh_ended = elem(Lobbies.transition_state(lobby_fixture(), "ended"), 1)

      age_lobby(ended, 20)
      age_lobby(playing, 20)

      Retention.prune_all()

      refute Repo.get(Lobby, ended.id)
      refute Repo.get(Lobby, playing.id)
      assert Repo.get(Lobby, fresh_ended.id)
    end

    test "disabled by a window of 0" do
      Application.put_env(:gamend_core, Gamend.Retention, abandoned_lobby_minutes: 0)

      quiet = age_lobby(lobby_fixture(), 600)

      Retention.prune_all()

      assert Repo.get(Lobby, quiet.id)
    end

    test "never reaps a lobby whose member is online" do
      Application.put_env(:gamend_core, Gamend.Retention, abandoned_lobby_minutes: 15)

      lobby = lobby_fixture()
      # A connected socket refreshes last_seen every few minutes; that recent
      # heartbeat — not the is_online flag — is what "present" means here.
      seen = DateTime.add(DateTime.utc_now(:second), -2, :minute)
      put_member(lobby, AccountsFixtures.user_fixture(), online: true, last_seen: seen)
      age_lobby(lobby, 600)

      Retention.prune_all()

      assert Repo.get(Lobby, lobby.id)
    end

    test "never reaps around a reconnect inside the window" do
      Application.put_env(:gamend_core, Gamend.Retention, abandoned_lobby_minutes: 15)

      lobby = lobby_fixture()
      seen = DateTime.add(DateTime.utc_now(:second), -2, :minute)
      put_member(lobby, AccountsFixtures.user_fixture(), online: false, last_seen: seen)
      age_lobby(lobby, 600)

      Retention.prune_all()

      assert Repo.get(Lobby, lobby.id)
    end

    test "reaps a lobby whose members all went quiet past the window" do
      Application.put_env(:gamend_core, Gamend.Retention, abandoned_lobby_minutes: 15)

      lobby = lobby_fixture()
      seen = DateTime.add(DateTime.utc_now(:second), -60, :minute)
      put_member(lobby, AccountsFixtures.user_fixture(), online: false, last_seen: seen)
      age_lobby(lobby, 60)

      Retention.prune_all()

      refute Repo.get(Lobby, lobby.id)
    end

    # A hard server stop skips every channel terminate, so users stay flagged
    # is_online=true with a last_seen frozen at their final heartbeat. The
    # flag alone must never keep a lobby alive: an eleven-hour-old solo run
    # survived a restart this way and rejoined its player into yesterday's
    # game. "Seen" is last_seen_at, which live sockets refresh continuously.
    test "a stale is_online flag from a hard stop does not keep a lobby alive" do
      Application.put_env(:gamend_core, Gamend.Retention, abandoned_lobby_minutes: 15)

      lobby = lobby_fixture()
      seen = DateTime.add(DateTime.utc_now(:second), -11 * 60, :minute)
      put_member(lobby, AccountsFixtures.user_fixture(), online: true, last_seen: seen)
      age_lobby(lobby, 11 * 60)

      Retention.prune_all()

      refute Repo.get(Lobby, lobby.id)
    end

    # A lobby its remaining players are still using is never reaped, so
    # without releasing the seat the absent player keeps `lobby_id` set for as
    # long as the game runs — and join_lobby/create_lobby both refuse with
    # :already_in_lobby, locking them out of playing at all.
    test "releases the seat of a long-offline player in a lobby still in use" do
      Application.put_env(:gamend_core, Gamend.Retention, abandoned_lobby_minutes: 15)

      lobby = lobby_fixture()
      gone = AccountsFixtures.user_fixture()
      playing = AccountsFixtures.user_fixture()

      put_member(lobby, gone,
        online: false,
        last_seen: DateTime.add(DateTime.utc_now(:second), -60, :minute)
      )

      put_member(lobby, playing, online: true, last_seen: DateTime.utc_now(:second))

      Retention.prune_all()

      assert Repo.get(Lobby, lobby.id), "the lobby is still in use and must survive"
      assert Repo.get(User, gone.id).lobby_id == nil
      assert Repo.get(User, playing.id).lobby_id == lobby.id
    end

    test "keeps the seat of a player offline inside the window" do
      Application.put_env(:gamend_core, Gamend.Retention, abandoned_lobby_minutes: 60)

      lobby = lobby_fixture()
      recent = AccountsFixtures.user_fixture()

      put_member(lobby, recent,
        online: false,
        last_seen: DateTime.add(DateTime.utc_now(:second), -20, :minute)
      )

      Retention.prune_all()

      assert Repo.get(User, recent.id).lobby_id == lobby.id
    end

    # The two rules have to compose: releasing seats must not leave a lobby
    # nobody is in sitting around, and reaping a lobby must not leave its
    # members pointing at a row that no longer exists. Whichever fires,
    # everyone ends up free and no orphan is left behind.
    test "a lobby everyone abandoned is gone and leaves nobody holding a seat" do
      Application.put_env(:gamend_core, Gamend.Retention, abandoned_lobby_minutes: 15)

      lobby = lobby_fixture()
      gone = DateTime.add(DateTime.utc_now(:second), -60, :minute)
      one = AccountsFixtures.user_fixture()
      two = AccountsFixtures.user_fixture()

      put_member(lobby, one, online: false, last_seen: gone)
      put_member(lobby, two, online: false, last_seen: gone)
      age_lobby(lobby, 60)

      Retention.prune_all()

      refute Repo.get(Lobby, lobby.id)
      assert Repo.get(User, one.id).lobby_id == nil
      assert Repo.get(User, two.id).lobby_id == nil
    end

    test "0 disables seat release along with lobby reaping" do
      Application.put_env(:gamend_core, Gamend.Retention, abandoned_lobby_minutes: 0)

      lobby = lobby_fixture()
      gone = AccountsFixtures.user_fixture()

      put_member(lobby, gone,
        online: false,
        last_seen: DateTime.add(DateTime.utc_now(:second), -600, :minute)
      )

      Retention.prune_all()

      assert Repo.get(User, gone.id).lobby_id == lobby.id
    end
  end

  describe "user tokens" do
    test "prunes only tokens past their own context's validity" do
      user = AccountsFixtures.user_fixture()

      live_session = token!(user, "session", minutes: 60)
      dead_session = token!(user, "session", minutes: 15 * 24 * 60)
      live_login = token!(user, "login", minutes: 5)
      dead_login = token!(user, "login", minutes: 30)
      live_change = token!(user, "change:old@example.com", minutes: 60)
      dead_change = token!(user, "change:old@example.com", minutes: 8 * 24 * 60)

      Retention.prune_all()

      assert Repo.get(UserToken, live_session.id)
      assert Repo.get(UserToken, live_login.id)
      assert Repo.get(UserToken, live_change.id)
      refute Repo.get(UserToken, dead_session.id)
      refute Repo.get(UserToken, dead_login.id)
      refute Repo.get(UserToken, dead_change.id)
    end

    defp token!(user, context, minutes: minutes) do
      token =
        Repo.insert!(%UserToken{
          token: :crypto.strong_rand_bytes(32),
          context: context,
          user_id: user.id,
          sent_to: user.email
        })

      at = DateTime.add(DateTime.utc_now(:second), -minutes, :minute)
      Repo.update_all(from(t in UserToken, where: t.id == ^token.id), set: [inserted_at: at])
      token
    end
  end

  describe "invites, tickets and ledgers" do
    test "prunes resolved invites but never pending ones" do
      Application.put_env(:gamend_core, Gamend.Retention, invites_days: 30)

      inviter = AccountsFixtures.user_fixture()
      invitee = AccountsFixtures.user_fixture()
      {:ok, group} = Gamend.Groups.create_group(inviter.id, %{title: "g#{unique()}"})

      resolved = invite!(group, inviter, invitee, "declined")
      pending = invite!(group, inviter, AccountsFixtures.user_fixture(), "pending")

      Retention.prune_all()

      refute Repo.get(GroupInvite, resolved.id)
      assert Repo.get(GroupInvite, pending.id)
    end

    test "keeps resolved invites when disabled" do
      Application.put_env(:gamend_core, Gamend.Retention, invites_days: 0)

      inviter = AccountsFixtures.user_fixture()
      {:ok, group} = Gamend.Groups.create_group(inviter.id, %{title: "g#{unique()}"})
      resolved = invite!(group, inviter, AccountsFixtures.user_fixture(), "declined")

      Retention.prune_all()

      assert Repo.get(GroupInvite, resolved.id)
    end

    defp invite!(group, sender, recipient, status) do
      invite =
        Repo.insert!(%GroupInvite{
          group_id: group.id,
          sender_id: sender.id,
          recipient_id: recipient.id,
          status: status
        })

      at = DateTime.add(DateTime.utc_now(:second), -60, :day)
      Repo.update_all(from(i in GroupInvite, where: i.id == ^invite.id), set: [updated_at: at])
      invite
    end

    test "prunes matchmaking tickets older than the window, in any status" do
      Application.put_env(:gamend_core, Gamend.Retention, matchmaking_tickets_hours: 24)

      old = ticket!(hours: 48)
      fresh = ticket!(hours: 1)

      Retention.prune_all()

      refute Repo.get(Ticket, old.id)
      assert Repo.get(Ticket, fresh.id)
    end

    defp ticket!(hours: hours) do
      user = AccountsFixtures.user_fixture()
      now = DateTime.utc_now()

      ticket =
        Repo.insert!(%Ticket{
          user_id: user.id,
          status: "queued",
          queued_at: now,
          min_players: 2,
          max_players: 2,
          timeout_ms: 30_000
        })

      at = DateTime.add(now, -hours, :hour)
      Repo.update_all(from(t in Ticket, where: t.id == ^ticket.id), set: [inserted_at: at])
      ticket
    end

    test "ledgers are opt-in and kept by default" do
      user = AccountsFixtures.user_fixture()

      entry =
        Repo.insert!(%Gamend.Economy.LedgerEntry{
          user_id: user.id,
          currency: "coins",
          delta: 10,
          balance_after: 10,
          reason: "test"
        })

      backdate(Gamend.Economy.LedgerEntry, entry.id, 500)

      Retention.prune_all()
      assert Repo.get(Gamend.Economy.LedgerEntry, entry.id)

      Application.put_env(:gamend_core, Gamend.Retention, ledger_days: 30)
      Retention.prune_all()
      refute Repo.get(Gamend.Economy.LedgerEntry, entry.id)
    end
  end

  describe "isolation" do
    test "one class failing does not abort the rest" do
      Application.put_env(:gamend_core, Gamend.Retention,
        chat_messages_days: 30,
        invites_days: :not_an_integer
      )

      user = AccountsFixtures.user_fixture()

      old =
        Repo.insert!(%Gamend.Chat.Message{
          sender_id: user.id,
          content: "old",
          chat_type: "lobby",
          chat_ref_id: Ecto.UUID.generate()
        })

      backdate(Gamend.Chat.Message, old.id, 60)

      results = ExUnit.CaptureLog.capture_log(fn -> send(self(), Retention.prune_all()) end)
      assert results =~ "retention class"
      assert_received %{chat_messages: 1, resolved_invites: 0}
      refute Repo.get(Gamend.Chat.Message, old.id)
    end
  end

  describe "abandoned parties" do
    defp party_with(members, opts) do
      [leader | rest] = members
      {:ok, party} = Parties.create_party(leader, %{})

      for u <- [leader | rest] do
        Repo.update_all(from(x in User, where: x.id == ^u.id),
          set: [
            party_id: party.id,
            is_online: Keyword.get(opts, :online, false),
            last_seen_at: Keyword.get(opts, :last_seen)
          ]
        )
      end

      party
    end

    # Nothing clears party_id on disconnect (a reconnecting player rejoins
    # their party), so without this the row and every member's party_id
    # outlive the group forever.
    test "disbands a party every member abandoned" do
      Application.put_env(:gamend_core, Gamend.Retention, abandoned_party_minutes: 15)

      gone = DateTime.add(DateTime.utc_now(:second), -60, :minute)
      a = AccountsFixtures.user_fixture()
      b = AccountsFixtures.user_fixture()
      party = party_with([a, b], online: false, last_seen: gone)

      Retention.prune_all()

      refute Repo.get(Party, party.id)
      assert Repo.get(User, a.id).party_id == nil
      assert Repo.get(User, b.id).party_id == nil
    end

    test "keeps a party with anyone still around" do
      Application.put_env(:gamend_core, Gamend.Retention, abandoned_party_minutes: 15)

      a = AccountsFixtures.user_fixture()
      b = AccountsFixtures.user_fixture()
      party = party_with([a, b], online: true, last_seen: DateTime.utc_now(:second))

      Retention.prune_all()

      assert Repo.get(Party, party.id)
      assert Repo.get(User, a.id).party_id == party.id
    end

    test "0 disables party disbanding" do
      Application.put_env(:gamend_core, Gamend.Retention, abandoned_party_minutes: 0)

      gone = DateTime.add(DateTime.utc_now(:second), -600, :minute)
      a = AccountsFixtures.user_fixture()
      party = party_with([a], online: false, last_seen: gone)

      Retention.prune_all()

      assert Repo.get(Party, party.id)
    end

    # The disband sweep above only fires once EVERY member is quiet, so a single
    # player still online kept a party alive around a leader who had gone hours
    # ago — and only the leader can steer or open a ready check, so the rest were
    # held in a party that could do nothing. Releasing the leader's seat hands
    # the party to whoever is still there rather than ending it under them.
    test "a long-gone leader hands the party to a member still online" do
      Application.put_env(:gamend_core, Gamend.Retention, abandoned_party_minutes: 15)

      gone = DateTime.add(DateTime.utc_now(:second), -60, :minute)
      leader = AccountsFixtures.user_fixture()
      member = AccountsFixtures.user_fixture()
      party = party_with([leader, member], online: true, last_seen: DateTime.utc_now(:second))

      Repo.update_all(from(u in User, where: u.id == ^leader.id),
        set: [is_online: false, last_seen_at: gone]
      )

      Retention.prune_all()

      assert Repo.get(Party, party.id).leader_id == member.id
      assert Repo.get(User, leader.id).party_id == nil
      assert Repo.get(User, member.id).party_id == party.id
    end

    # Nobody left to hand it to: an empty party is just a row.
    test "the last member leaving still ends the party" do
      Application.put_env(:gamend_core, Gamend.Retention, abandoned_party_minutes: 15)

      gone = DateTime.add(DateTime.utc_now(:second), -60, :minute)
      leader = AccountsFixtures.user_fixture()
      party = party_with([leader], online: false, last_seen: gone)

      Retention.prune_all()

      refute Repo.get(Party, party.id)
      assert Repo.get(User, leader.id).party_id == nil
    end

    # A member is only a seat: releasing it leaves the party standing, exactly
    # as releasing a lobby seat does.
    test "a long-gone member is released without ending the party" do
      Application.put_env(:gamend_core, Gamend.Retention, abandoned_party_minutes: 15)

      gone = DateTime.add(DateTime.utc_now(:second), -60, :minute)
      leader = AccountsFixtures.user_fixture()
      member = AccountsFixtures.user_fixture()
      party = party_with([leader, member], online: true, last_seen: DateTime.utc_now(:second))

      Repo.update_all(from(u in User, where: u.id == ^member.id),
        set: [is_online: false, last_seen_at: gone]
      )

      Retention.prune_all()

      assert Repo.get(Party, party.id)
      assert Repo.get(User, leader.id).party_id == party.id
      assert Repo.get(User, member.id).party_id == nil
    end

    test "0 disables releasing party seats" do
      Application.put_env(:gamend_core, Gamend.Retention, abandoned_party_minutes: 0)

      gone = DateTime.add(DateTime.utc_now(:second), -600, :minute)
      leader = AccountsFixtures.user_fixture()
      member = AccountsFixtures.user_fixture()
      party = party_with([leader, member], online: true, last_seen: DateTime.utc_now(:second))

      Repo.update_all(from(u in User, where: u.id == ^leader.id),
        set: [is_online: false, last_seen_at: gone]
      )

      Retention.prune_all()

      assert Repo.get(Party, party.id)
      assert Repo.get(User, leader.id).party_id == party.id
    end
  end

  describe "orphaned avatars" do
    alias Gamend.Storage
    alias Gamend.Storage.Local

    setup do
      dir =
        Path.join(System.tmp_dir!(), "retention_avatars_#{System.unique_integer([:positive])}")

      old = Application.get_env(:gamend_core, Local)
      Application.put_env(:gamend_core, Local, dir: dir)

      on_exit(fn ->
        File.rm_rf(dir)

        if old,
          do: Application.put_env(:gamend_core, Local, old),
          else: Application.delete_env(:gamend_core, Local)
      end)

      :ok
    end

    # Age is what separates an orphan from an object still being written, so the
    # mtime has to be set explicitly rather than waiting out the grace window.
    defp put_avatar(owner_id, minutes_old) do
      key = Storage.build_key("avatars", owner_id, "avatar.jpg")
      {:ok, ^key} = Storage.put(key, "BYTES", content_type: "image/jpeg")
      backdate_object(key, minutes_old)
      key
    end

    defp backdate_object(key, minutes_old) do
      Local.root_dir()
      |> Path.join(key)
      |> File.touch!(System.os_time(:second) - minutes_old * 60)
    end

    test "deletes stored avatars whose owner no longer exists" do
      live = AccountsFixtures.user_fixture()
      live_key = put_avatar(live.id, 120)
      orphan_key = put_avatar(Gamend.UUIDv7.generate(), 120)

      results = Retention.prune_all()

      assert results.orphaned_avatars == 1
      refute Storage.exists?(orphan_key)
      assert Storage.exists?(live_key)
    end

    test "leaves a just-written object alone — it may be mid-upload" do
      fresh_key = put_avatar(Gamend.UUIDv7.generate(), 0)

      assert Retention.prune_all().orphaned_avatars == 0
      assert Storage.exists?(fresh_key)
    end

    test "reaches an orphan that sorts past the first page of objects" do
      # Both backends list in key order, so an orphan whose owner id sorts last
      # is only found if the sweep pages past the live users ahead of it.
      live = AccountsFixtures.user_fixture()
      for _ <- 1..500, do: put_avatar(live.id, 120)
      orphan_key = put_avatar("ffffffff-ffff-7fff-8fff-ffffffffffff", 120)

      assert Retention.prune_all().orphaned_avatars == 1
      refute Storage.exists?(orphan_key)
    end

    test "never touches keys whose owner segment is not a user id" do
      {:ok, foreign} = Storage.put("avatars/shared/branding.png", "BYTES")
      backdate_object(foreign, 120)

      assert Retention.prune_all().orphaned_avatars == 0
      assert Storage.exists?(foreign)
    end
  end

  describe "register_class/2" do
    setup do
      on_exit(fn -> Gamend.Retention.unregister_class(:test_host_table) end)
      :ok
    end

    # CONTRIBUTING requires every unbounded table to have a retention class, and
    # a host application's tables are no exception — but core's list was fixed,
    # so a fork could not comply with a rule core enforces on itself.
    test "a registered class runs with core's and reports its count" do
      Gamend.Retention.register_class(:test_host_table, fn -> 7 end)

      results = Gamend.Retention.prune_all()

      assert results[:test_host_table] == 7
      assert Map.has_key?(results, :chat_messages)
    end

    test "registering the same name twice replaces it, so a boot-time call cannot double-prune" do
      Gamend.Retention.register_class(:test_host_table, fn -> 1 end)
      Gamend.Retention.register_class(:test_host_table, fn -> 2 end)

      assert map_size(Gamend.Retention.registered_classes()) == 1
      assert Gamend.Retention.prune_all()[:test_host_table] == 2
    end

    test "unregister_class/1 removes it" do
      Gamend.Retention.register_class(:test_host_table, fn -> 1 end)
      Gamend.Retention.unregister_class(:test_host_table)

      refute Map.has_key?(Gamend.Retention.prune_all(), :test_host_table)
    end

    # Shadowing a core class would silently stop core pruning that table, which
    # is exactly the unbounded growth this module exists to prevent.
    test "a class cannot shadow one of core's" do
      Gamend.Retention.register_class(:chat_messages, fn -> 999 end)
      on_exit(fn -> Gamend.Retention.unregister_class(:chat_messages) end)

      refute Gamend.Retention.prune_all()[:chat_messages] == 999
    end

    # A host's class must not be able to take the whole sweep down with it.
    test "a raising class is isolated and counted as zero" do
      Gamend.Retention.register_class(:test_host_table, fn -> raise "boom" end)

      results = Gamend.Retention.prune_all()

      assert results[:test_host_table] == 0
      assert Map.has_key?(results, :chat_messages)
    end
  end
end
