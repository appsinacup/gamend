defmodule Gamend.CacheSyncTest do
  # Writes to the shared L1 cache directly, so no async.
  use ExUnit.Case, async: false

  alias Gamend.Cache

  # The app cache runs in bypass mode during tests (levels not started), so
  # start the L1 level explicitly and exercise it directly — that is exactly
  # what Cache.Sync operates on.
  setup do
    case start_supervised(Cache.L1) do
      {:ok, _pid} -> :ok
      {:error, {{:already_started, _pid}, _spec}} -> :ok
    end

    :ok
  end

  test "invalidate/1 broadcasts the key with the originating node" do
    Phoenix.PubSub.subscribe(Gamend.PubSub, Cache.invalidation_topic())

    assert :ok = Cache.invalidate({:test, :broadcast_key})

    this_node = Node.self()
    assert_receive {:cache_invalidate, {:test, :broadcast_key}, ^this_node}
  end

  test "an event from another node evicts the key from L1" do
    Cache.L1.put({:test, :remote_key}, "value")
    assert Cache.L1.get!({:test, :remote_key}) == "value"

    send(
      Process.whereis(Gamend.Cache.Sync),
      {:cache_invalidate, {:test, :remote_key}, :"other@remote-host"}
    )

    # Synchronize with the GenServer so the message has been processed.
    _ = :sys.get_state(Gamend.Cache.Sync)

    assert Cache.L1.get!({:test, :remote_key}) == nil
  end

  test "an event from another node moves the key's generation, so a fill in flight is dropped" do
    generation = {Gamend.Cache, :generation, {:test, :remote_generation}}
    before = Cache.L1.get!(generation) || 0

    send(
      Process.whereis(Gamend.Cache.Sync),
      {:cache_invalidate, {:test, :remote_generation}, :"other@remote-host"}
    )

    _ = :sys.get_state(Gamend.Cache.Sync)

    assert Cache.L1.get!(generation) == before + 1
  end

  test "an event from this node is skipped (already deleted locally)" do
    Cache.L1.put({:test, :local_key}, "value")

    send(
      Process.whereis(Gamend.Cache.Sync),
      {:cache_invalidate, {:test, :local_key}, Node.self()}
    )

    _ = :sys.get_state(Gamend.Cache.Sync)

    assert Cache.L1.get!({:test, :local_key}) == "value"
    Cache.L1.delete({:test, :local_key})
  end

  test "bump_version/1 broadcasts the key with the originating node" do
    Phoenix.PubSub.subscribe(Gamend.PubSub, Cache.invalidation_topic())

    _ = Cache.bump_version({:test, :version_key})

    this_node = Node.self()
    assert_receive {:cache_bump_version, {:test, :version_key}, ^this_node}
  end

  test "a bump event from another node increments the L1 counter" do
    Cache.L1.put({:test, :remote_version}, 5)

    send(
      Process.whereis(Gamend.Cache.Sync),
      {:cache_bump_version, {:test, :remote_version}, :"other@remote-host"}
    )

    _ = :sys.get_state(Gamend.Cache.Sync)

    assert Cache.L1.get!({:test, :remote_version}) == 6
    Cache.L1.delete({:test, :remote_version})
  end

  test "a bump event seeds a missing counter instead of deleting it" do
    send(
      Process.whereis(Gamend.Cache.Sync),
      {:cache_bump_version, {:test, :fresh_version}, :"other@remote-host"}
    )

    _ = :sys.get_state(Gamend.Cache.Sync)

    assert Cache.L1.get!({:test, :fresh_version}) == 2
    Cache.L1.delete({:test, :fresh_version})
  end

  test "a bump event from this node is skipped (already bumped locally)" do
    Cache.L1.put({:test, :local_version}, 5)

    send(
      Process.whereis(Gamend.Cache.Sync),
      {:cache_bump_version, {:test, :local_version}, Node.self()}
    )

    _ = :sys.get_state(Gamend.Cache.Sync)

    assert Cache.L1.get!({:test, :local_version}) == 5
    Cache.L1.delete({:test, :local_version})
  end
end
