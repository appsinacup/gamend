defmodule Gamend.LockHoldTest do
  @moduledoc """
  A plugin's `before_*` hook runs outside the lock of the write it gates.

  Inside it, the hook held the lock and, on SQLite, the database's only
  connection for up to its timeout: repeated wrong lobby passwords from one
  player (a bcrypt check each) stalled every request in the server. Each hook
  here probes the lock its caller would take, without waiting: it is free
  only if the caller has not taken it yet.
  """
  use Gamend.DataCase, async: false

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.{Groups, KV, Lobbies, Repo}
  alias Gamend.Hooks.Default
  alias Gamend.Payments.Entitlement

  defmodule ProbeHooks do
    use Gamend.TestSupport.NoopHooks

    def probe(namespace, id) do
      key = {{Gamend.Lock.Local, {namespace, id}}, make_ref()}
      free = :global.set_lock(key, [node()], 0)
      if free, do: :global.del_lock(key, [node()])
      send(Application.get_env(:gamend_core, :lock_probe_pid), {:lock_free, namespace, free})
    end

    @impl true
    def before_lobby_join(user, lobby, opts) do
      probe(:lobby, lobby.id)
      {:ok, {user, lobby, opts}}
    end

    @impl true
    def before_group_join(user, group, opts) do
      probe(:group, group.id)
      {:ok, {user, group, opts}}
    end

    @impl true
    def before_lobby_update(lobby, attrs) do
      probe(:lobby, lobby.id)
      {:ok, attrs}
    end

    @impl true
    def before_user_update(user, attrs) do
      probe("user_payment_metadata", user.id)
      {:ok, attrs}
    end
  end

  # Writes a key between the unlocked read and the locked write, as a
  # concurrent merge would, the first time it is asked.
  defmodule RacingMergeHooks do
    use Gamend.TestSupport.NoopHooks

    @impl true
    def before_lobby_update(lobby, attrs) do
      if :persistent_term.get({__MODULE__, :raced}, false) == false do
        :persistent_term.put({__MODULE__, :raced}, true)

        Gamend.Repo.update_all(
          from(l in Gamend.Lobbies.Lobby, where: l.id == ^lobby.id),
          set: [metadata: Map.put(lobby.metadata || %{}, "theirs", 1)]
        )
      end

      {:ok, attrs}
    end
  end

  setup do
    hooks = Application.get_env(:gamend_core, :hooks_module)
    Application.put_env(:gamend_core, :hooks_module, ProbeHooks)
    Application.put_env(:gamend_core, :lock_probe_pid, self())

    on_exit(fn ->
      Application.put_env(:gamend_core, :hooks_module, hooks)
      Application.delete_env(:gamend_core, :lock_probe_pid)
    end)

    host = AccountsFixtures.user_fixture()
    %{host: host, player: AccountsFixtures.user_fixture()}
  end

  test "lobby join: the hook and the password check run before the lock", %{
    host: host,
    player: player
  } do
    {:ok, lobby} =
      Lobbies.create_lobby(%{title: "locked-room", host_id: host.id, password: "secret"})

    # Argon2id, as account passwords: ~24ms a check rather than bcrypt's ~250ms.
    assert "$argon2id$" <> _ = lobby.password_hash

    assert {:error, :invalid_password} = Lobbies.join_lobby(player, lobby, %{password: "wrong"})
    assert_received {:lock_free, :lobby, true}

    assert {:ok, _} = Lobbies.join_lobby(player, lobby, %{password: "secret"})
    assert_received {:lock_free, :lobby, true}
  end

  test "lobby join: a full lobby is refused without asking the hook", %{
    host: host,
    player: player
  } do
    # The host is seated by creating it.
    {:ok, lobby} = Lobbies.create_lobby(%{title: "tiny", host_id: host.id, max_users: 1})

    assert {:error, :full} = Lobbies.join_lobby(player, lobby)
    refute_received {:lock_free, :lobby, _}
  end

  test "group join: the hook runs before the lock", %{host: host, player: player} do
    {:ok, group} = Groups.create_group(host.id, %{title: "open-group", type: "public"})

    assert {:ok, _member} = Groups.join_group(player.id, group.id)
    assert_received {:lock_free, :group, true}
  end

  test "lobby metadata merge: the hook runs before the lock", %{host: host} do
    {:ok, lobby} = Lobbies.create_lobby(%{title: "meta", host_id: host.id})

    assert {:ok, merged} = Lobbies.merge_metadata(lobby, %{"mine" => 1})
    assert merged.metadata["mine"] == 1
    assert_received {:lock_free, :lobby, true}
  end

  test "lobby metadata merge: a concurrent write starts it over, and both keys survive", %{
    host: host
  } do
    Application.put_env(:gamend_core, :hooks_module, RacingMergeHooks)
    on_exit(fn -> :persistent_term.erase({RacingMergeHooks, :raced}) end)
    {:ok, lobby} = Lobbies.create_lobby(%{title: "raced", host_id: host.id})

    assert {:ok, merged} = Lobbies.merge_metadata(lobby, %{"mine" => 1})
    assert merged.metadata == %{"mine" => 1, "theirs" => 1}
  end

  test "payment metadata: the hook runs before the lock", %{player: player} do
    entitlement = %Entitlement{
      id: Ecto.UUID.generate(),
      user_id: player.id,
      key: "vip",
      status: "active"
    }

    assert :ok = Default.after_entitlement_changed(entitlement)
    assert_received {:lock_free, "user_payment_metadata", true}

    metadata = Repo.get!(User, player.id).metadata
    assert get_in(metadata, ["payments", "entitlements", "vip"]) == true
  end

  test "lobby delete clears its KV in one statement", %{host: host} do
    {:ok, lobby} = Lobbies.create_lobby(%{title: "kv-room", host_id: host.id})

    for key <- ~w(a b c), do: {:ok, _} = KV.put(key, %{"v" => key}, %{}, lobby_id: lobby.id)

    assert {:ok, _} = Lobbies.delete_lobby(lobby)
    assert KV.delete_lobby_entries(lobby.id) == 0
    assert :error = KV.get("a", lobby_id: lobby.id)
  end

  test "Lock.exclusive holds no transaction while its function runs" do
    # Each write inside commits by itself: the tournament tick used to hold one
    # transaction, and every row it touched, across all due tournaments.
    assert {:ok, false} = Gamend.Lock.exclusive("lock_hold_test", "tick", &Repo.in_transaction?/0)
  end
end
