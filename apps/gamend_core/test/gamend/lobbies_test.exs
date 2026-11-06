defmodule Gamend.LobbiesTest do
  use Gamend.DataCase

  alias Gamend.Accounts
  alias Gamend.AccountsFixtures
  alias Gamend.KV
  alias Gamend.Lobbies

  describe "lobbies and memberships" do
    defmodule CaptureHook do
      use Gamend.TestSupport.NoopHooks

      @impl true
      def after_lobby_join(_user, lobby) do
        if pid = Application.get_env(:gamend, :hooks_test_pid) do
          send(pid, {:after_lobby_join, lobby})
        end

        :ok
      end
    end

    setup do
      host = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
      other = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()

      %{host: host, other: other}
    end

    test "create lobby with host and hostless lobby", %{host: host} do
      {:ok, lobby} = Lobbies.create_lobby(%{title: "room-1", host_id: host.id})

      assert lobby.title == "room-1"
      assert lobby.host_id == host.id

      {:ok, service_lobby} = Lobbies.create_lobby(%{title: "server-room", hostless: true})
      assert service_lobby.hostless
      assert is_nil(service_lobby.host_id)
    end

    test "create_lobby generates title for blank string-keyed params", %{host: host} do
      # Simulate browser form params: string keys, title present but blank.
      assert {:ok, lobby} = Lobbies.create_lobby(%{"title" => "", "host_id" => host.id})

      assert lobby.title |> to_string() |> String.trim() != ""
      assert lobby.host_id == host.id
    end

    test "hostless lobby creation clears host_id but keeps membership", %{host: host} do
      {:ok, lobby} =
        Lobbies.create_lobby(%{title: "hostless-with-host", host_id: host.id, hostless: true})

      assert lobby.hostless
      assert is_nil(lobby.host_id)

      members = Lobbies.get_lobby_members(lobby)
      assert Enum.any?(members, fn u -> u.id == host.id end)
    end

    test "join and capacity rules", %{host: host, other: other} do
      {:ok, lobby} = Lobbies.create_lobby(%{title: "join-room", host_id: host.id, max_users: 2})
      # lobby should be persisted and host membership will be created automatically

      # other joins
      assert {:ok, _} = Lobbies.join_lobby(other, lobby)

      # third user can't join when full
      user3 = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
      assert {:error, :full} = Lobbies.join_lobby(user3, lobby)
    end

    test "locked lobby rejects joins unless bypass_lock is set", %{host: host, other: other} do
      {:ok, lobby} =
        Lobbies.create_lobby(%{title: "locked-room", host_id: host.id, is_locked: true})

      assert {:error, :locked} = Lobbies.join_lobby(other, lobby)

      assert {:ok, joined} = Lobbies.join_lobby(other, lobby, %{bypass_lock: true})
      assert joined.lobby_id == lobby.id
    end

    test "bypass_lock still respects capacity", %{host: host, other: other} do
      {:ok, lobby} =
        Lobbies.create_lobby(%{
          title: "locked-full",
          host_id: host.id,
          max_users: 1,
          is_locked: true
        })

      assert {:error, :full} = Lobbies.join_lobby(other, lobby, %{bypass_lock: true})
    end

    test "bypass_lock works as a keyword list too", %{host: host, other: other} do
      {:ok, lobby} =
        Lobbies.create_lobby(%{title: "kw-locked", host_id: host.id, is_locked: true})

      assert {:ok, _} = Lobbies.join_lobby(other, lobby, bypass_lock: true)
    end

    test "blocked users cannot join the same lobby", %{host: host, other: other} do
      {:ok, _} = Gamend.Friends.block_user(host, other.id)

      {:ok, lobby} = Lobbies.create_lobby(%{title: "blocked-room", host_id: host.id})

      assert {:error, :blocked} = Lobbies.join_lobby(other, lobby)
    end

    test "bypass_lock is not a way around a block", %{host: host, other: other} do
      # `other` is the blocker here, so this also covers the reverse direction
      {:ok, _} = Gamend.Friends.block_user(other, host.id)

      {:ok, locked} =
        Lobbies.create_lobby(%{title: "blocked-locked", host_id: host.id, is_locked: true})

      assert {:error, :blocked} = Lobbies.join_lobby(other, locked, %{bypass_lock: true})
    end

    test "password-protected join", %{host: host, other: other} do
      pw = "secret"
      phash = Bcrypt.hash_pwd_salt(pw)

      {:ok, lobby} =
        Lobbies.create_lobby(%{title: "pw-room", host_id: host.id, password_hash: phash})

      assert {:error, :password_required} = Lobbies.join_lobby(other, lobby)
      assert {:error, :invalid_password} = Lobbies.join_lobby(other, lobby, password: "nope")
      assert {:ok, _} = Lobbies.join_lobby(other, lobby, password: pw)
    end

    test "list_lobbies_for_user does not return deleted lobby after cache warm", %{host: host} do
      {:ok, lobby} =
        Lobbies.create_lobby(%{title: "hidden-room", host_id: host.id, is_hidden: true})

      host = Accounts.get_user!(host.id)
      lobbies_before = Lobbies.list_lobbies_for_user(host)
      assert Enum.any?(lobbies_before, &(&1.id == lobby.id))

      # Warm the lobby cache explicitly
      _ = Lobbies.get_lobby(lobby.id)

      assert {:ok, _} = Accounts.delete_user(host)

      lobbies_after = Lobbies.list_lobbies_for_user(host)
      refute Enum.any?(lobbies_after, &(&1.id == lobby.id))
    end

    test "delete_lobby clears members and lobby scoped kv", %{host: host, other: other} do
      {:ok, lobby} = Lobbies.create_lobby(%{title: "delete-room", host_id: host.id, max_users: 2})
      assert {:ok, _} = Lobbies.join_lobby(other, lobby)

      assert {:ok, _} = KV.put("cleanup_test", %{"value" => 1}, %{}, lobby_id: lobby.id)

      assert {:ok, _} =
               KV.put("cleanup_user_test", %{"value" => 2}, %{},
                 user_id: other.id,
                 lobby_id: lobby.id
               )

      assert {:ok, _} = KV.get("cleanup_test", lobby_id: lobby.id)
      assert {:ok, _} = KV.get("cleanup_user_test", user_id: other.id, lobby_id: lobby.id)

      assert {:ok, _} = Lobbies.delete_lobby(lobby)

      refute Lobbies.get_lobby(lobby.id)
      assert is_nil(Accounts.get_user!(host.id).lobby_id)
      assert is_nil(Accounts.get_user!(other.id).lobby_id)
      assert :error = KV.get("cleanup_test", lobby_id: lobby.id)
      assert :error = KV.get("cleanup_user_test", user_id: other.id, lobby_id: lobby.id)
    end

    # Deleting a lobby detaches its members with one bulk update, so each of
    # them has to be told separately — `lobby_deleted` goes to the lobby LIST
    # topic, which a seated player has no reason to be listening on. Without
    # this the client kept the lobby_id it had cached, skipped creating a lobby
    # for its next game, and the server refused the start it had no lobby for.
    test "delete_lobby tells every member their seat is gone", %{host: host, other: other} do
      {:ok, lobby} =
        Lobbies.create_lobby(%{title: "announce-room", host_id: host.id, max_users: 2})

      assert {:ok, _} = Lobbies.join_lobby(other, lobby)

      for member <- [host, other] do
        Phoenix.PubSub.subscribe(Gamend.PubSub, "user:#{member.id}")
      end

      assert {:ok, _} = Lobbies.delete_lobby(lobby)

      for member <- [host, other] do
        topic = "user:#{member.id}"

        assert_receive %Phoenix.Socket.Broadcast{
                         topic: ^topic,
                         event: "updated",
                         payload: %{lobby_id: ""}
                       },
                       200
      end
    end

    test "search by metadata", %{host: host} do
      {:ok, _} =
        Lobbies.create_lobby(%{
          title: "meta-room",
          host_id: host.id,
          metadata: %{mode: "capture", region: "EU"}
        })

      {:ok, _} =
        Lobbies.create_lobby(%{
          title: "meta-room-2",
          hostless: true,
          metadata: %{mode: "deathmatch", region: "US"}
        })

      results =
        Lobbies.list_lobbies(%{title: "meta", metadata_key: "mode", metadata_value: "cap"})

      assert Enum.any?(results, fn r -> r.title == "meta-room" end)
      refute Enum.any?(results, fn r -> r.title == "meta-room-2" end)
    end

    test "leave lobby and host transfer", %{host: host, other: other} do
      {:ok, lobby} = Lobbies.create_lobby(%{title: "leave-room", host_id: host.id, max_users: 5})

      # other joins (host created as a member on lobby creation)
      assert {:ok, _} = Lobbies.join_lobby(other, lobby)

      # host leaves and other becomes host
      assert {:ok, _} = Lobbies.leave_lobby(host)

      refreshed = Lobbies.get_lobby!(lobby.id)
      assert refreshed.host_id == other.id
    end

    test "kick user by host", %{host: host, other: other} do
      {:ok, lobby} = Lobbies.create_lobby(%{title: "kick-room", host_id: host.id, max_users: 5})
      # host membership created on lobby creation; ensure other joins
      assert {:ok, _} = Lobbies.join_lobby(other, lobby)

      assert {:ok, _} = Lobbies.kick_user(host, lobby, other)
      # ensure other no longer in the lobby
      assert {:error, :not_in_lobby} == Lobbies.leave_lobby(other)
    end

    test "kick errors: cannot kick self, not_host, not_found, not_in_lobby", %{
      host: host,
      other: other
    } do
      # set up lobby and memberships
      {:ok, lobby} = Lobbies.create_lobby(%{title: "errors-room", host_id: host.id, max_users: 5})
      assert {:ok, _} = Lobbies.join_lobby(other, lobby)

      # cannot kick self
      assert {:error, :cannot_kick_self} = Lobbies.kick_user(host, lobby, host)

      # not_host (some other non-host user tries to kick) - create additional user
      another = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
      assert {:error, :not_host} = Lobbies.kick_user(another, lobby, other)

      # not_found (target id points to non-existing user)
      assert {:error, :not_found} =
               Lobbies.kick_user(host, lobby, %Gamend.Accounts.User{id: Ecto.UUID.generate()})

      # not_in_lobby: target exists but not in this lobby
      outsider = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
      assert {:error, :not_in_lobby} = Lobbies.kick_user(host, lobby, outsider)
    end

    test "cannot join if already in a lobby", %{host: host, other: other} do
      {:ok, lobby1} = Lobbies.create_lobby(%{title: "a-room-1", host_id: host.id})

      # other joins lobby1
      assert {:ok, _} = Lobbies.join_lobby(other, lobby1)

      # tries to join a different lobby and should get error :already_in_lobby
      {:ok, lobby2} =
        Lobbies.create_lobby(%{title: "a-room-2", host_id: AccountsFixtures.user_fixture().id})

      assert {:error, :already_in_lobby} = Lobbies.join_lobby(other, lobby2)
    end

    test "before_lobby_join hook can reject a join", %{host: host, other: other} do
      orig = Application.get_env(:gamend_core, :hooks_module)

      defmodule DenyJoinHook do
        def before_lobby_create(attrs), do: {:ok, attrs}
        def before_lobby_join(_user, _lobby, _opts), do: {:error, :banned}
        def after_lobby_create(_), do: :ok
        def after_lobby_join(_user, _lobby), do: :ok
        def before_lobby_leave(_, _), do: {:ok, :noop}
        def after_lobby_leave(_, _), do: :ok
        def before_lobby_kick(_, _, _), do: {:ok, :noop}
        def after_lobby_kick(_, _, _), do: :ok
        def before_lobby_update(_, _), do: {:ok, %{}}
        def after_lobby_updated(_), do: :ok
        def before_lobby_delete(_), do: {:ok, %{}}
        def after_lobby_deleted(_), do: :ok
        def after_lobby_host_change(_, _), do: :ok
      end

      Application.put_env(:gamend_core, :hooks_module, DenyJoinHook)

      on_exit(fn -> Application.put_env(:gamend_core, :hooks_module, orig) end)

      {:ok, lobby} = Lobbies.create_lobby(%{title: "deny-room", host_id: host.id})
      assert {:error, {:hook_rejected, :banned}} = Lobbies.join_lobby(other, lobby)
    end

    test "create_membership invokes hook without doing DB checkouts in child task", %{
      host: host,
      other: other
    } do
      orig = Application.get_env(:gamend_core, :hooks_module)
      orig_pid = Application.get_env(:gamend, :hooks_test_pid)

      on_exit(fn ->
        Application.put_env(:gamend_core, :hooks_module, orig)
        Application.put_env(:gamend, :hooks_test_pid, orig_pid)
      end)

      # register our capture hook and give it the pid so it can notify us
      Application.put_env(:gamend_core, :hooks_module, CaptureHook)
      Application.put_env(:gamend, :hooks_test_pid, self())

      {:ok, lobby} = Lobbies.create_lobby(%{title: "hook-room", host_id: host.id, max_users: 5})

      # Ensure join triggers create_membership which starts background task
      assert {:ok, _} = Lobbies.join_lobby(other, lobby)

      # create_membership starts a background task; wait for the hook message
      assert_receive {:after_lobby_join, received_lobby}, 200

      assert received_lobby.id == lobby.id
    end

    test "cannot shrink lobby max_users below current member count", %{host: host, other: other} do
      # create with max_users 3, host auto-joined
      {:ok, lobby} = Lobbies.create_lobby(%{title: "shrink-room", host_id: host.id, max_users: 3})

      # two other users join -> total 3
      assert {:ok, _} = Lobbies.join_lobby(other, lobby)
      user3 = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
      assert {:ok, _} = Lobbies.join_lobby(user3, lobby)

      # host tries to shrink to 2, should be rejected
      assert {:error, :too_small} = Lobbies.update_lobby_by_host(host, lobby, %{max_users: 2})

      # increasing is allowed
      assert {:ok, updated} = Lobbies.update_lobby_by_host(host, lobby, %{max_users: 6})
      assert updated.max_users == 6
    end

    test "quick_join finds and joins a matching lobby", %{host: host, other: other} do
      {:ok, _lobby} =
        Lobbies.create_lobby(%{
          title: "quick-room",
          host_id: host.id,
          max_users: 2,
          metadata: %{mode: "capture", region: "EU"}
        })

      assert {:ok, matched} = Lobbies.quick_join(other, nil, 2, %{mode: "cap"})

      # ensure the returned lobby matches the query criteria and the user joined it
      assert matched.max_users == 2

      assert String.contains?(
               to_string(
                 Map.get(matched.metadata || %{}, "mode") ||
                   Map.get(matched.metadata || %{}, :mode)
               ),
               "cap"
             )

      reloaded = Gamend.Repo.get(Gamend.Accounts.User, other.id)
      assert reloaded.lobby_id == matched.id
    end

    # A candidate that will not take this user is not a match — matchmaking has
    # to move on. One refusal used to abort the whole quick join, and the player
    # got an error where a fresh lobby was the obvious answer: in the game that
    # surfaced as "Could not start game" every time quick_join landed on a lobby
    # already mid-match, which a stale one did to every player who tried.
    defmodule RefuseJoinHook do
      use Gamend.TestSupport.NoopHooks

      @impl true
      def before_lobby_join(user, lobby, opts) do
        if lobby.state == "playing" do
          {:error, :match_in_progress}
        else
          {:ok, {user, lobby, opts}}
        end
      end
    end

    test "quick_join skips a candidate the game refuses and opens a fresh lobby", %{
      host: host,
      other: other
    } do
      {:ok, running} =
        Lobbies.create_lobby(%{title: "running-room", host_id: host.id, max_users: 4})

      {:ok, running} = Lobbies.transition_state(running, "playing")

      previous = Application.get_env(:gamend_core, :hooks_module)
      Application.put_env(:gamend_core, :hooks_module, RefuseJoinHook)

      on_exit(fn ->
        if previous do
          Application.put_env(:gamend_core, :hooks_module, previous)
        else
          Application.delete_env(:gamend_core, :hooks_module)
        end
      end)

      assert {:ok, fresh} = Lobbies.quick_join(other, "fresh-room", 4, %{})

      refute fresh.id == running.id
      assert Gamend.Repo.get(Accounts.User, other.id).lobby_id == fresh.id
    end

    test "joining a lobby disbanded after it was read answers not_found", %{
      host: host,
      other: other
    } do
      {:ok, stale} = Lobbies.create_lobby(%{title: "gone-room", host_id: host.id, max_users: 4})
      _ = Lobbies.delete_lobby(stale)

      assert {:error, :not_found} = Lobbies.join_lobby(other, stale)
      assert Gamend.Repo.get(Accounts.User, other.id).lobby_id == nil
    end

    test "changing a lobby disbanded after it was read answers not_found", %{host: host} do
      {:ok, stale} = Lobbies.create_lobby(%{title: "gone-room", host_id: host.id, max_users: 4})
      assert {:ok, _} = Lobbies.delete_lobby(stale)

      assert {:error, :not_found} = Lobbies.delete_lobby(stale)
      assert {:error, :not_found} = Lobbies.update_lobby(stale, %{title: "renamed"})
      assert {:error, :not_found} = Lobbies.transition_state(stale, "playing")
      assert {:error, :not_found} = Lobbies.write_webrtc_config(stale, %{webrtc_enabled: true})
    end

    test "the last member leaving deletes the lobby and its chat", %{host: host} do
      {:ok, lobby} = Lobbies.create_lobby(%{title: "chat-room", host_id: host.id, max_users: 4})

      message =
        Gamend.Repo.insert!(%Gamend.Chat.Message{
          sender_id: host.id,
          content: "gg",
          chat_type: "lobby",
          chat_ref_id: lobby.id
        })

      assert {:ok, :lobby_deleted} = Lobbies.leave_lobby(host)
      refute Gamend.Repo.get(Lobbies.Lobby, lobby.id)
      refute Gamend.Repo.get(Gamend.Chat.Message, message.id)
    end

    test "a member handed the host as they leave deletes the lobby rather than leaving it hosted by nobody",
         %{host: host, other: other} do
      {:ok, lobby} =
        Lobbies.create_lobby(%{title: "handover-room", host_id: host.id, max_users: 4})

      assert {:ok, _} = Lobbies.join_lobby(other, lobby)

      result =
        after_first_read("lobbies", fn -> {:ok, _} = Lobbies.leave_lobby(host) end, fn ->
          Lobbies.leave_lobby(other)
        end)

      assert result == {:ok, :lobby_deleted}
      refute Gamend.Repo.get(Lobbies.Lobby, lobby.id)
    end

    test "a kick landing after the host handed the lobby to its target answers not_host",
         %{host: host, other: other} do
      {:ok, lobby} =
        Lobbies.create_lobby(%{title: "handover-room", host_id: host.id, max_users: 4})

      assert {:ok, _} = Lobbies.join_lobby(other, lobby)

      result =
        after_first_read("lobbies", fn -> {:ok, _} = Lobbies.leave_lobby(host) end, fn ->
          Lobbies.kick_user(host, lobby, other)
        end)

      assert result == {:error, :not_host}
      assert Gamend.Repo.get!(Lobbies.Lobby, lobby.id).host_id == other.id
      assert Gamend.Repo.get(Accounts.User, other.id).lobby_id == lobby.id
    end

    # The host disbands while a quick join is between reading its candidates
    # and seating the player: the race CI's parallel flows hit, which wrote a
    # member into a deleted lobby and answered 500.
    defmodule VanishingLobbyHook do
      use Gamend.TestSupport.NoopHooks

      @impl true
      def before_lobby_join(user, lobby, opts) do
        if lobby.title == "vanishing-room", do: Gamend.Lobbies.delete_lobby(lobby)
        {:ok, {user, lobby, opts}}
      end
    end

    test "quick_join moves past a candidate disbanded as it joins", %{host: host, other: other} do
      {:ok, vanishing} =
        Lobbies.create_lobby(%{title: "vanishing-room", host_id: host.id, max_users: 4})

      previous = Application.get_env(:gamend_core, :hooks_module)
      Application.put_env(:gamend_core, :hooks_module, VanishingLobbyHook)

      on_exit(fn ->
        if previous do
          Application.put_env(:gamend_core, :hooks_module, previous)
        else
          Application.delete_env(:gamend_core, :hooks_module)
        end
      end)

      assert {:ok, fresh} = Lobbies.quick_join(other, "fresh-room", 4, %{})

      refute fresh.id == vanishing.id
      assert Gamend.Repo.get(Accounts.User, other.id).lobby_id == fresh.id
    end

    test "quick_join creates a new lobby when none matches", %{other: other} do
      # ensure there are no existing matching lobbies
      assert {:ok, lobby} = Lobbies.quick_join(other, "my-quick-room", 5, %{mode: "coop"})

      assert lobby.title == "my-quick-room"
      assert lobby.max_users == 5
      assert lobby.metadata == %{"mode" => "coop"} or lobby.metadata == %{mode: "coop"}

      reloaded = Gamend.Repo.get(Gamend.Accounts.User, other.id)
      assert reloaded.lobby_id == lobby.id
    end

    test "quick_join persists metadata when creating new lobby (no title provided)", %{
      other: other
    } do
      {:ok, lobby} = Lobbies.quick_join(other, nil, 6, %{mode: "capture", region: "EU"})

      assert lobby.max_users == 6
      # metadata stored as map with either atom or string keys
      m = lobby.metadata || %{}
      assert Map.get(m, :mode) == "capture" or Map.get(m, "mode") == "capture"
      assert Map.get(m, :region) == "EU" or Map.get(m, "region") == "EU"

      reloaded = Gamend.Repo.get(Gamend.Accounts.User, other.id)
      assert reloaded.lobby_id == lobby.id
    end

    test "quick_join generates a unique title when caller omits title (nil)", %{other: other} do
      assert {:ok, lobby} = Lobbies.quick_join(other, nil, 4, %{mode: "coop"})

      # generated title should be present and non-blank
      assert lobby.title != nil
      assert lobby.title |> to_string() |> String.trim() != ""

      reloaded = Gamend.Repo.get(Gamend.Accounts.User, other.id)
      assert reloaded.lobby_id == lobby.id
    end

    test "quick_join generates a unique title when caller provides blank title (empty string)", %{
      other: other
    } do
      assert {:ok, lobby} = Lobbies.quick_join(other, "", 3, %{})

      assert lobby.title != nil
      assert lobby.title |> to_string() |> String.trim() != ""

      reloaded = Gamend.Repo.get(Gamend.Accounts.User, other.id)
      assert reloaded.lobby_id == lobby.id
    end

    test "quick_join skips passworded lobbies and prefers non-passworded ones", %{
      host: host,
      other: other
    } do
      pw = "letmein"
      phash = Bcrypt.hash_pwd_salt(pw)

      # create a passworded lobby with matching metadata
      {:ok, pw_lobby} =
        Lobbies.create_lobby(%{
          title: "pw-match",
          host_id: host.id,
          max_users: 4,
          password_hash: phash,
          metadata: %{mode: "coop"}
        })

      # create a non-passworded lobby that should be preferred
      second_host = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()

      {:ok, _non_pw} =
        Lobbies.create_lobby(%{
          title: "no-pw",
          host_id: second_host.id,
          max_users: 4,
          metadata: %{mode: "coop"}
        })

      assert {:ok, matched} = Lobbies.quick_join(other, nil, 4, %{mode: "coop"})

      # matched lobby should be non-passworded and contain the requested metadata
      assert matched.password_hash == nil

      assert to_string(
               Map.get(matched.metadata || %{}, :mode) || Map.get(matched.metadata || %{}, "mode")
             )
             |> String.contains?("coop")

      # ensure it did not pick the passworded lobby
      assert matched.id != pw_lobby.id

      reloaded = Gamend.Repo.get(Gamend.Accounts.User, other.id)
      assert reloaded.lobby_id == matched.id
    end
  end

  describe "update_lobby_by_host/3 authorization" do
    setup do
      host = AccountsFixtures.user_fixture()
      member = AccountsFixtures.user_fixture()

      %{host: host, member: member}
    end

    test "the host of a host-managed lobby may update it", %{host: host} do
      {:ok, lobby} = Lobbies.create_lobby(%{title: "host-edits", host_id: host.id})

      assert {:ok, updated} =
               Lobbies.update_lobby_by_host(host, lobby, %{
                 "title" => "Renamed",
                 "is_locked" => true
               })

      assert updated.title == "Renamed"
      assert updated.is_locked
      assert Lobbies.can_manage_lobby?(host, lobby)
    end

    test "a non-host member may not", %{host: host, member: member} do
      {:ok, lobby} = Lobbies.create_lobby(%{title: "member-edits", host_id: host.id})
      assert {:ok, _} = Lobbies.join_lobby(member, lobby)

      assert {:error, :not_host} =
               Lobbies.update_lobby_by_host(member, lobby, %{"title" => "Hijacked"})

      assert Lobbies.get_lobby(lobby.id).title == "member-edits"
      refute Lobbies.can_manage_lobby?(member, lobby)
    end

    test "no member may update a hostless lobby — matchmaking matches belong to the server", %{
      member: member
    } do
      {:ok, lobby} = Lobbies.create_lobby(%{title: "ranked-match", hostless: true})
      assert {:ok, _} = Lobbies.join_lobby(member, lobby)

      assert {:error, :not_host} =
               Lobbies.update_lobby_by_host(member, lobby, %{
                 "title" => "Hijacked",
                 "metadata" => %{"score" => 999},
                 "max_users" => 99,
                 "is_hidden" => true,
                 "password" => "locked-out"
               })

      reloaded = Lobbies.get_lobby(lobby.id)
      assert reloaded.title == "ranked-match"
      assert reloaded.metadata == %{}
      refute reloaded.is_hidden
      assert is_nil(reloaded.password_hash)
      refute Lobbies.can_manage_lobby?(member, lobby)

      # The server itself still can, via the unscoped call.
      assert {:ok, updated} = Lobbies.update_lobby(reloaded, %{"metadata" => %{"score" => 3}})
      assert updated.metadata == %{"score" => 3}
    end
  end

  describe "the pinned WebRTC host holds lobby authority" do
    setup do
      %{server: AccountsFixtures.user_fixture(), member: AccountsFixtures.user_fixture()}
    end

    defp hostless_lobby_hosted_by(server, title) do
      {:ok, lobby} = Lobbies.create_lobby(%{title: title, hostless: true})

      {:ok, lobby} =
        Gamend.Signaling.configure(lobby, enabled: true, topology: :star, host_id: server.id)

      lobby
    end

    test "it may update and move a hostless lobby it is not a member of", %{server: server} do
      lobby = hostless_lobby_hosted_by(server, "matchmade")
      assert server.lobby_id == nil

      assert Lobbies.can_manage_lobby?(server, lobby)

      assert {:ok, updated} =
               Lobbies.update_lobby_by_host(server, lobby, %{"metadata" => %{"round" => 2}})

      assert updated.metadata == %{"round" => 2}

      assert {:ok, moved} = Lobbies.transition_state_by_host(server, updated, "playing")
      assert moved.state == "playing"
    end

    test "it may kick from that lobby, and a plain member may not", %{
      server: server,
      member: member
    } do
      lobby = hostless_lobby_hosted_by(server, "kickable")
      other = AccountsFixtures.user_fixture()
      assert {:ok, _} = Lobbies.join_lobby(member, lobby)
      assert {:ok, _} = Lobbies.join_lobby(other, lobby)

      # Regression: this guard used to read `host_id != caller and not hostless`,
      # which never fires on a hostless lobby — every member could kick.
      refute Lobbies.can_manage_lobby?(member, lobby)
      assert {:error, :not_host} = Lobbies.kick_user(member, lobby, other)
      assert Gamend.Accounts.get_user(other.id).lobby_id == lobby.id

      assert {:ok, _} = Lobbies.kick_user(server, lobby, other)
      assert is_nil(Gamend.Accounts.get_user(other.id).lobby_id)
    end

    test "a hostless lobby with no pinned host still has no authority", %{member: member} do
      other = AccountsFixtures.user_fixture()
      {:ok, lobby} = Lobbies.create_lobby(%{title: "ownerless", hostless: true})
      assert {:ok, _} = Lobbies.join_lobby(member, lobby)
      assert {:ok, _} = Lobbies.join_lobby(other, lobby)

      refute Lobbies.can_manage_lobby?(member, lobby)
      assert {:error, :not_host} = Lobbies.transition_state_by_host(member, lobby, "playing")
      assert {:error, :not_host} = Lobbies.update_lobby_by_host(member, lobby, %{"title" => "x"})

      # The plain matchmaking case of the kick regression: the old guard read
      # `host_id != caller and not hostless`, which never fired here at all.
      assert {:error, :not_host} = Lobbies.kick_user(member, lobby, other)
      assert Gamend.Accounts.get_user(other.id).lobby_id == lobby.id
    end

    test "pinning it in a host-managed lobby does not unseat the host", %{
      server: server,
      member: host
    } do
      {:ok, lobby} = Lobbies.create_lobby(%{title: "co-managed", host_id: host.id})

      {:ok, lobby} =
        Gamend.Signaling.configure(lobby, enabled: true, topology: :star, host_id: server.id)

      assert Lobbies.can_manage_lobby?(host, lobby)
      assert Lobbies.can_manage_lobby?(server, lobby)
    end
  end

  describe "host_id may be a user who is not seated in the lobby" do
    # What lets a headless server own a matchmaking lobby without a new column
    # and without a new field on the wire: set it as `host_id` after creation.
    # `create_lobby` is the path that seats the host and refuses one already
    # seated elsewhere; `update_lobby/2` does neither.
    test "a server hosts many lobbies at once, seated in none" do
      server = AccountsFixtures.user_fixture()
      player = AccountsFixtures.user_fixture()

      {:ok, a} = Lobbies.create_lobby(%{title: "a", hostless: true})
      {:ok, b} = Lobbies.create_lobby(%{title: "b", hostless: true})
      assert {:ok, _} = Lobbies.join_lobby(player, a)

      {:ok, a} = Lobbies.update_lobby(a, %{"hostless" => false, "host_id" => server.id})
      {:ok, b} = Lobbies.update_lobby(b, %{"hostless" => false, "host_id" => server.id})

      assert Accounts.get_user(server.id).lobby_id == nil
      assert Lobbies.can_manage_lobby?(server, a)
      assert Lobbies.can_manage_lobby?(server, b)

      # and consumes no slot
      assert Lobbies.get_lobby_members(a) |> Enum.map(& &1.id) == [player.id]
    end

    # `update_lobby_by_host/3` takes only the fields a host owns. It used to pass
    # attrs straight through to a changeset that casts `host_id`, `hostless` and
    # `password_hash`, so a host could hand the lobby to a non-member, write the
    # password hash unhashed, or set `hostless` — which makes `can_manage_lobby?/2`
    # false for everyone and leaves the lobby permanently unmanageable.
    test "a host cannot rewrite ownership, hostless or the password hash" do
      host = AccountsFixtures.user_fixture()
      server = AccountsFixtures.user_fixture()
      {:ok, lobby} = Lobbies.create_lobby(%{title: "transfer", host_id: host.id})

      assert {:ok, moved} =
               Lobbies.update_lobby_by_host(host, lobby, %{
                 "host_id" => server.id,
                 "hostless" => true,
                 "password_hash" => "not-a-hash",
                 "title" => "renamed"
               })

      # The field it does own still applies.
      assert moved.title == "renamed"

      assert moved.host_id == host.id
      refute moved.hostless
      assert moved.password_hash == lobby.password_hash
      assert Lobbies.can_manage_lobby?(host, moved)
      refute Lobbies.can_manage_lobby?(server, moved)
    end

    test "a host setting a password gets it hashed, not stored verbatim" do
      host = AccountsFixtures.user_fixture()
      {:ok, lobby} = Lobbies.create_lobby(%{title: "secret", host_id: host.id})

      assert {:ok, updated} =
               Lobbies.update_lobby_by_host(host, lobby, %{"password" => "hunter22"})

      assert is_binary(updated.password_hash)
      refute updated.password_hash == "hunter22"
    end

    test "a member leaving does not take the host seat from it" do
      server = AccountsFixtures.user_fixture()
      player = AccountsFixtures.user_fixture()

      {:ok, lobby} = Lobbies.create_lobby(%{title: "stable", hostless: true})
      assert {:ok, _} = Lobbies.join_lobby(player, lobby)
      {:ok, lobby} = Lobbies.update_lobby(lobby, %{"hostless" => false, "host_id" => server.id})

      # handle_host_transfer only fires for the host's own departure, and a
      # non-member host never departs.
      assert {:ok, _} = Lobbies.leave_lobby(player)
      assert Lobbies.get_lobby(lobby.id).host_id == server.id
    end
  end

  # A seat is the player's own row, so the seat write is the guard, made against
  # the database. A check made earlier, or a lobby's lock, let one player into two
  # lobbies at once (appsinacup/gamend#60, #61, #62).
  describe "one lobby seat per player" do
    # Two creates for one host both passed a read of the host, both inserted,
    # and the lobby that lost the seat was left with nobody in it. Here the
    # host is seated between this create's insert and its seat. That seat lands
    # inside this transaction and rolls back with it; what counts is the answer
    # and that no lobby is left behind.
    test "create refuses a host seated after its lobby was inserted" do
      host = AccountsFixtures.user_fixture()
      {:ok, elsewhere} = Lobbies.create_lobby(%{title: "elsewhere", hostless: true})

      result =
        after_first_read("lobbies", fn -> seat_directly(host, elsewhere) end, fn ->
          Lobbies.create_lobby(%{title: "second", host_id: host.id})
        end)

      assert result == {:error, :already_in_lobby}
      assert [elsewhere.id] == Enum.map(Gamend.Repo.all(Lobbies.Lobby), & &1.id)
    end

    # A join reads the player before it waits on the lobby's lock, and a join to
    # another lobby takes another lock.
    test "join refuses a player seated elsewhere after it read them" do
      host = AccountsFixtures.user_fixture()
      player = AccountsFixtures.user_fixture()
      {:ok, elsewhere} = Lobbies.create_lobby(%{title: "elsewhere", hostless: true})
      {:ok, lobby} = Lobbies.create_lobby(%{title: "target", host_id: host.id})

      result =
        after_first_read("users", fn -> seat_directly(player, elsewhere) end, fn ->
          Lobbies.join_lobby(player, lobby)
        end)

      assert result == {:error, :already_in_lobby}
      assert seated(player).lobby_id == elsewhere.id
      assert Enum.map(Lobbies.get_lobby_members(lobby), & &1.id) == [host.id]
    end

    # The second of two joins to the same lobby rewrote the same seat and still
    # broadcast `user_joined`, ran `after_lobby_join` and counted the
    # "lobby_joined" quest event again.
    test "a second join to the same lobby is refused, not counted twice" do
      host = AccountsFixtures.user_fixture()
      player = AccountsFixtures.user_fixture()
      {:ok, lobby} = Lobbies.create_lobby(%{title: "twice", host_id: host.id})

      result =
        after_first_read("users", fn -> {:ok, _} = Lobbies.join_lobby(player, lobby) end, fn ->
          Lobbies.join_lobby(player, lobby)
        end)

      assert result == {:error, :already_in_lobby}

      assert Enum.sort(Enum.map(Lobbies.get_lobby_members(lobby), & &1.id)) ==
               Enum.sort([host.id, player.id])
    end

    test "claim_seat/2 answers why it did not seat" do
      player = AccountsFixtures.user_fixture()
      {:ok, a} = Lobbies.create_lobby(%{title: "a", hostless: true})
      {:ok, b} = Lobbies.create_lobby(%{title: "b", hostless: true})

      assert {:ok, %{lobby_id: a_id}} = Lobbies.claim_seat(player.id, a.id)
      assert a_id == a.id
      assert {:error, :already_in_lobby} = Lobbies.claim_seat(player.id, b.id)
      assert {:error, :not_found} = Lobbies.claim_seat(Ecto.UUID.generate(), b.id)
      assert seated(player).lobby_id == a.id
    end
  end

  defp seated(user), do: Gamend.Repo.get!(Accounts.User, user.id)

  defp seat_directly(user, lobby) do
    user |> seated() |> Ecto.Changeset.change(lobby_id: lobby.id) |> Gamend.Repo.update!()
  end

  # Runs `act` the first time this process reads `source`, between the read and
  # whatever `call` does with it; fails unless it ran.
  defp after_first_read(source, act, call) do
    pid = self()
    handler = {__MODULE__, :after_first_read, System.unique_integer()}

    :telemetry.attach(
      handler,
      [:gamend, :repo, :query],
      fn _event, _measurements, meta, _config ->
        if self() == pid and meta[:source] == source and !Process.get(handler) do
          Process.put(handler, true)
          act.()
        end
      end,
      nil
    )

    try do
      result = call.()
      assert Process.get(handler), "nothing read #{source}"
      result
    after
      :telemetry.detach(handler)
    end
  end
end
