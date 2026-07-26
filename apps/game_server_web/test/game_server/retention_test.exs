defmodule GameServer.RetentionTest do
  use GameServer.DataCase, async: false

  alias GameServer.Accounts.{User, UserToken}
  alias GameServer.AccountsFixtures
  alias GameServer.Groups.GroupInvite
  alias GameServer.Lobbies
  alias GameServer.Lobbies.Lobby
  alias GameServer.Matchmaking.Ticket
  alias GameServer.Repo
  alias GameServer.Retention

  defp backdate(schema, id, days) do
    cutoff = DateTime.add(DateTime.utc_now(:second), -days, :day)

    Repo.update_all(
      from(r in schema, where: r.id == ^id),
      set: [inserted_at: cutoff]
    )
  end

  setup do
    original = Application.get_env(:game_server_core, GameServer.Retention, [])

    on_exit(fn ->
      Application.put_env(:game_server_core, GameServer.Retention, original)
    end)

    :ok
  end

  test "prunes chat messages older than the configured retention" do
    Application.put_env(:game_server_core, GameServer.Retention, chat_messages_days: 30)

    a = AccountsFixtures.user_fixture()

    old =
      Repo.insert!(%GameServer.Chat.Message{
        sender_id: a.id,
        content: "old",
        chat_type: "lobby",
        chat_ref_id: Ecto.UUID.generate()
      })

    fresh =
      Repo.insert!(%GameServer.Chat.Message{
        sender_id: a.id,
        content: "fresh",
        chat_type: "lobby",
        chat_ref_id: Ecto.UUID.generate()
      })

    backdate(GameServer.Chat.Message, old.id, 31)

    results = Retention.prune_all()

    assert results.chat_messages == 1
    refute Repo.get(GameServer.Chat.Message, old.id)
    assert Repo.get(GameServer.Chat.Message, fresh.id)
  end

  test "retention of 0 keeps everything" do
    Application.put_env(:game_server_core, GameServer.Retention, chat_messages_days: 0)

    a = AccountsFixtures.user_fixture()

    old =
      Repo.insert!(%GameServer.Chat.Message{
        sender_id: a.id,
        content: "old",
        chat_type: "lobby",
        chat_ref_id: Ecto.UUID.generate()
      })

    backdate(GameServer.Chat.Message, old.id, 400)

    results = Retention.prune_all()

    assert results.chat_messages == 0
    assert Repo.get(GameServer.Chat.Message, old.id)
  end

  test "prunes expired ip bans but keeps permanent and future ones" do
    now = DateTime.utc_now(:second)

    expired =
      Repo.insert!(%GameServer.IpBans.IpBan{ip: "10.0.0.1", expires_at: DateTime.add(now, -60)})

    future =
      Repo.insert!(%GameServer.IpBans.IpBan{ip: "10.0.0.2", expires_at: DateTime.add(now, 3600)})

    permanent = Repo.insert!(%GameServer.IpBans.IpBan{ip: "10.0.0.3", expires_at: nil})

    results = Retention.prune_all()

    assert results.expired_ip_bans == 1
    refute Repo.get(GameServer.IpBans.IpBan, expired.id)
    assert Repo.get(GameServer.IpBans.IpBan, future.id)
    assert Repo.get(GameServer.IpBans.IpBan, permanent.id)
  end

  describe "lobby snapshots" do
    alias GameServer.LobbySnapshots.{Blob, Event, Snapshot}

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
      Application.put_env(:game_server_core, GameServer.Retention,
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
      Application.put_env(:game_server_core, GameServer.Retention, lobby_snapshots_days: 0)

      lobby = Ecto.UUID.generate()
      ancient = snapshot!(lobby, days_old: 500)
      ancient_blob = blob!("ancient", 500)

      Retention.prune_all()

      assert Repo.get(Snapshot, ancient.id)
      assert Repo.get(Blob, ancient_blob.hash)
    end

    test "a flagged window shorter than the normal one does not expire flagged runs first" do
      Application.put_env(:game_server_core, GameServer.Retention,
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
      Application.put_env(:game_server_core, GameServer.Retention, abandoned_lobby_minutes: 15)

      quiet = age_lobby(lobby_fixture(), 20)
      fresh = lobby_fixture()

      Retention.prune_all()

      refute Repo.get(Lobby, quiet.id)
      assert Repo.get(Lobby, fresh.id)
    end

    test "keeps a lobby inside the window" do
      Application.put_env(:game_server_core, GameServer.Retention, abandoned_lobby_minutes: 60)

      quiet = age_lobby(lobby_fixture(), 20)

      Retention.prune_all()

      assert Repo.get(Lobby, quiet.id)
    end

    # An ended match is the game's business: it deletes its own lobby. Core
    # reaps on silence alone, so state never changes the outcome.
    test "state does not change what is reaped" do
      Application.put_env(:game_server_core, GameServer.Retention, abandoned_lobby_minutes: 15)

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
      Application.put_env(:game_server_core, GameServer.Retention, abandoned_lobby_minutes: 0)

      quiet = age_lobby(lobby_fixture(), 600)

      Retention.prune_all()

      assert Repo.get(Lobby, quiet.id)
    end

    test "never reaps a lobby whose member is online" do
      Application.put_env(:game_server_core, GameServer.Retention, abandoned_lobby_minutes: 15)

      lobby = lobby_fixture()
      put_member(lobby, AccountsFixtures.user_fixture(), online: true)
      age_lobby(lobby, 600)

      Retention.prune_all()

      assert Repo.get(Lobby, lobby.id)
    end

    test "never reaps around a reconnect inside the window" do
      Application.put_env(:game_server_core, GameServer.Retention, abandoned_lobby_minutes: 15)

      lobby = lobby_fixture()
      seen = DateTime.add(DateTime.utc_now(:second), -2, :minute)
      put_member(lobby, AccountsFixtures.user_fixture(), online: false, last_seen: seen)
      age_lobby(lobby, 600)

      Retention.prune_all()

      assert Repo.get(Lobby, lobby.id)
    end

    test "reaps a lobby whose members all went quiet past the window" do
      Application.put_env(:game_server_core, GameServer.Retention, abandoned_lobby_minutes: 15)

      lobby = lobby_fixture()
      seen = DateTime.add(DateTime.utc_now(:second), -60, :minute)
      put_member(lobby, AccountsFixtures.user_fixture(), online: false, last_seen: seen)
      age_lobby(lobby, 60)

      Retention.prune_all()

      refute Repo.get(Lobby, lobby.id)
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
      Application.put_env(:game_server_core, GameServer.Retention, invites_days: 30)

      inviter = AccountsFixtures.user_fixture()
      invitee = AccountsFixtures.user_fixture()
      {:ok, group} = GameServer.Groups.create_group(inviter.id, %{title: "g#{unique()}"})

      resolved = invite!(group, inviter, invitee, "declined")
      pending = invite!(group, inviter, AccountsFixtures.user_fixture(), "pending")

      Retention.prune_all()

      refute Repo.get(GroupInvite, resolved.id)
      assert Repo.get(GroupInvite, pending.id)
    end

    test "keeps resolved invites when disabled" do
      Application.put_env(:game_server_core, GameServer.Retention, invites_days: 0)

      inviter = AccountsFixtures.user_fixture()
      {:ok, group} = GameServer.Groups.create_group(inviter.id, %{title: "g#{unique()}"})
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
      Application.put_env(:game_server_core, GameServer.Retention, matchmaking_tickets_hours: 24)

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
        Repo.insert!(%GameServer.Economy.LedgerEntry{
          user_id: user.id,
          currency: "coins",
          delta: 10,
          balance_after: 10,
          reason: "test"
        })

      backdate(GameServer.Economy.LedgerEntry, entry.id, 500)

      Retention.prune_all()
      assert Repo.get(GameServer.Economy.LedgerEntry, entry.id)

      Application.put_env(:game_server_core, GameServer.Retention, ledger_days: 30)
      Retention.prune_all()
      refute Repo.get(GameServer.Economy.LedgerEntry, entry.id)
    end
  end

  describe "isolation" do
    test "one class failing does not abort the rest" do
      Application.put_env(:game_server_core, GameServer.Retention,
        chat_messages_days: 30,
        invites_days: :not_an_integer
      )

      user = AccountsFixtures.user_fixture()

      old =
        Repo.insert!(%GameServer.Chat.Message{
          sender_id: user.id,
          content: "old",
          chat_type: "lobby",
          chat_ref_id: Ecto.UUID.generate()
        })

      backdate(GameServer.Chat.Message, old.id, 60)

      results = ExUnit.CaptureLog.capture_log(fn -> send(self(), Retention.prune_all()) end)
      assert results =~ "retention class"
      assert_received %{chat_messages: 1, resolved_invites: 0}
      refute Repo.get(GameServer.Chat.Message, old.id)
    end
  end
end
