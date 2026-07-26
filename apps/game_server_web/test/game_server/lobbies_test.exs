defmodule GameServer.LobbiesTest do
  use GameServer.DataCase

  alias GameServer.Accounts
  alias GameServer.AccountsFixtures
  alias GameServer.KV
  alias GameServer.Lobbies

  describe "lobbies and memberships" do
    defmodule CaptureHook do
      use GameServerWeb.TestSupport.NoopHooks

      @impl true
      def after_lobby_join(_user, lobby) do
        if pid = Application.get_env(:game_server, :hooks_test_pid) do
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
      {:ok, _} = GameServer.Friends.block_user(host, other.id)

      {:ok, lobby} = Lobbies.create_lobby(%{title: "blocked-room", host_id: host.id})

      assert {:error, :blocked} = Lobbies.join_lobby(other, lobby)
    end

    test "bypass_lock is not a way around a block", %{host: host, other: other} do
      # `other` is the blocker here, so this also covers the reverse direction
      {:ok, _} = GameServer.Friends.block_user(other, host.id)

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
               Lobbies.kick_user(host, lobby, %GameServer.Accounts.User{id: Ecto.UUID.generate()})

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
      orig = Application.get_env(:game_server_core, :hooks_module)

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

      Application.put_env(:game_server_core, :hooks_module, DenyJoinHook)

      on_exit(fn -> Application.put_env(:game_server_core, :hooks_module, orig) end)

      {:ok, lobby} = Lobbies.create_lobby(%{title: "deny-room", host_id: host.id})
      assert {:error, {:hook_rejected, :banned}} = Lobbies.join_lobby(other, lobby)
    end

    test "create_membership invokes hook without doing DB checkouts in child task", %{
      host: host,
      other: other
    } do
      orig = Application.get_env(:game_server_core, :hooks_module)
      orig_pid = Application.get_env(:game_server, :hooks_test_pid)

      on_exit(fn ->
        Application.put_env(:game_server_core, :hooks_module, orig)
        Application.put_env(:game_server, :hooks_test_pid, orig_pid)
      end)

      # register our capture hook and give it the pid so it can notify us
      Application.put_env(:game_server_core, :hooks_module, CaptureHook)
      Application.put_env(:game_server, :hooks_test_pid, self())

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

      reloaded = GameServer.Repo.get(GameServer.Accounts.User, other.id)
      assert reloaded.lobby_id == matched.id
    end

    test "quick_join creates a new lobby when none matches", %{other: other} do
      # ensure there are no existing matching lobbies
      assert {:ok, lobby} = Lobbies.quick_join(other, "my-quick-room", 5, %{mode: "coop"})

      assert lobby.title == "my-quick-room"
      assert lobby.max_users == 5
      assert lobby.metadata == %{"mode" => "coop"} or lobby.metadata == %{mode: "coop"}

      reloaded = GameServer.Repo.get(GameServer.Accounts.User, other.id)
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

      reloaded = GameServer.Repo.get(GameServer.Accounts.User, other.id)
      assert reloaded.lobby_id == lobby.id
    end

    test "quick_join generates a unique title when caller omits title (nil)", %{other: other} do
      assert {:ok, lobby} = Lobbies.quick_join(other, nil, 4, %{mode: "coop"})

      # generated title should be present and non-blank
      assert lobby.title != nil
      assert lobby.title |> to_string() |> String.trim() != ""

      reloaded = GameServer.Repo.get(GameServer.Accounts.User, other.id)
      assert reloaded.lobby_id == lobby.id
    end

    test "quick_join generates a unique title when caller provides blank title (empty string)", %{
      other: other
    } do
      assert {:ok, lobby} = Lobbies.quick_join(other, "", 3, %{})

      assert lobby.title != nil
      assert lobby.title |> to_string() |> String.trim() != ""

      reloaded = GameServer.Repo.get(GameServer.Accounts.User, other.id)
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

      reloaded = GameServer.Repo.get(GameServer.Accounts.User, other.id)
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
      assert Lobbies.can_edit_lobby?(host, lobby)
    end

    test "a non-host member may not", %{host: host, member: member} do
      {:ok, lobby} = Lobbies.create_lobby(%{title: "member-edits", host_id: host.id})
      assert {:ok, _} = Lobbies.join_lobby(member, lobby)

      assert {:error, :not_host} =
               Lobbies.update_lobby_by_host(member, lobby, %{"title" => "Hijacked"})

      assert Lobbies.get_lobby(lobby.id).title == "member-edits"
      refute Lobbies.can_edit_lobby?(member, lobby)
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
      refute Lobbies.can_edit_lobby?(member, lobby)

      # The server itself still can, via the unscoped call.
      assert {:ok, updated} = Lobbies.update_lobby(reloaded, %{"metadata" => %{"score" => 3}})
      assert updated.metadata == %{"score" => 3}
    end
  end
end
