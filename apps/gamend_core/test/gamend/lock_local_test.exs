defmodule Gamend.LockLocalTest do
  @moduledoc """
  `Gamend.Lock.Local`: callers on one key wait in line and are served in the
  order they asked.

  It was `:global.trans`, whose waiters retry after a random sleep that
  doubles up to 8 s. The lock then sat free while every waiter slept: fifty
  callers on one key took five times as long as running them one after another,
  and the slowest waited seconds for a section that takes milliseconds.
  """
  use ExUnit.Case, async: false

  alias Gamend.Lock.Local
  alias Gamend.Lock.Queue

  setup do
    assert Queue.running?()
    %{key: {:lock_local_test, System.unique_integer([:positive])}}
  end

  test "callers are served in the order they asked", %{key: key} do
    test = self()
    holder = hold(key)

    waiters =
      for n <- 1..8 do
        pid = spawn_link(fn -> Local.trans_on_node(key, fn -> send(test, {:served, n}) end) end)
        wait_until_queued(pid)
        pid
      end

    release(holder)

    for n <- 1..length(waiters), do: assert_receive({:served, ^n}, 1_000)
  end

  test "a holder that dies passes the key on", %{key: key} do
    test = self()
    holder = hold(key)
    waiter = spawn_link(fn -> Local.trans_on_node(key, fn -> send(test, :served) end) end)
    wait_until_queued(waiter)

    Process.unlink(holder)
    Process.exit(holder, :kill)

    assert_receive :served, 1_000
  end

  test "a waiter that dies leaves the line", %{key: key} do
    test = self()
    holder = hold(key)

    gone = spawn(fn -> Local.trans_on_node(key, fn -> send(test, :wrong) end) end)
    wait_until_queued(gone)
    next = spawn_link(fn -> Local.trans_on_node(key, fn -> send(test, :served) end) end)
    wait_until_queued(next)

    Process.exit(gone, :kill)
    release(holder)

    assert_receive :served, 1_000
    refute_received :wrong
  end

  test "a raise inside the section releases the key", %{key: key} do
    assert_raise RuntimeError, fn -> Local.trans_on_node(key, fn -> raise "boom" end) end
    assert Local.trans_on_node(key, fn -> :free end) == :free
  end

  test "the same process takes the same key again without waiting", %{key: key} do
    assert Local.trans(key, fn -> Local.trans(key, fn -> :inner end) end) == :inner

    assert Local.trans_on_node(key, fn -> Local.trans_on_node(key, fn -> :inner end) end) ==
             :inner
  end

  test "one holder at a time, and the line moves as fast as the sections do", %{key: key} do
    table = :ets.new(:lock_local_test, [:public, :set])
    :ets.insert(table, [{:inside, 0}, {:peak, 0}, {:busy_us, 0}])

    {wall_us, waits} =
      :timer.tc(fn ->
        1..40
        |> Task.async_stream(
          fn _ ->
            for _ <- 1..10 do
              {wait_us, :ok} =
                :timer.tc(fn ->
                  Local.trans(key, fn ->
                    inside = :ets.update_counter(table, :inside, 1)
                    if inside > peak(table), do: :ets.insert(table, {:peak, inside})
                    {busy, _} = :timer.tc(fn -> spin(500) end)
                    :ets.update_counter(table, :busy_us, busy)
                    :ets.update_counter(table, :inside, -1)
                    :ok
                  end)
                end)

              wait_us
            end
          end,
          max_concurrency: 40,
          timeout: :infinity
        )
        |> Enum.flat_map(fn {:ok, waits} -> waits end)
      end)

    assert peak(table) == 1
    [{:busy_us, busy_us}] = :ets.lookup(table, :busy_us)

    # In line, the 400 sections run back to back: no wait is longer than all of
    # them together, and the whole run is close to their sum.
    assert Enum.max(waits) <= busy_us + 200_000,
           "the slowest caller waited #{div(Enum.max(waits), 1000)} ms for #{div(busy_us, 1000)} ms of work"

    assert wall_us <= 2 * busy_us + 200_000,
           "400 sections of #{div(busy_us, 1000)} ms in all took #{div(wall_us, 1000)} ms"
  end

  # A process holding `key` until `release/1`.
  defp hold(key) do
    test = self()

    holder =
      spawn_link(fn ->
        Local.trans_on_node(key, fn ->
          send(test, :held)

          receive do
            :release -> :ok
          end
        end)
      end)

    assert_receive :held, 1_000
    holder
  end

  defp release(holder), do: send(holder, :release)

  # Blocked in its call to the queue, so it is in line.
  defp wait_until_queued(pid, tries \\ 200) do
    case Process.info(pid, :current_function) do
      {:current_function, {:gen, :do_call, 4}} ->
        :ok

      _ when tries > 0 ->
        Process.sleep(5)
        wait_until_queued(pid, tries - 1)

      other ->
        flunk("#{inspect(pid)} never queued: #{inspect(other)}")
    end
  end

  defp peak(table), do: :ets.lookup_element(table, :peak, 2)

  # Busy for about `us` microseconds without sleeping, so the section's length
  # does not depend on the timer resolution.
  defp spin(us) do
    deadline = System.monotonic_time(:microsecond) + us
    spin_until(deadline)
  end

  defp spin_until(deadline) do
    if System.monotonic_time(:microsecond) < deadline, do: spin_until(deadline), else: :ok
  end
end
