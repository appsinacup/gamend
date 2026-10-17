defmodule Gamend.Lock.Queue do
  @moduledoc """
  The waiting line behind `Gamend.Lock.Local`: per key, one holder and the
  callers after it, served in the order they asked.

  Partitioned by key (`PartitionSupervisor`, one partition per scheduler), so
  keys spread over several processes and one busy key does not hold up the
  rest. Each partition monitors the holder and every waiter: a holder that dies
  passes the key on, and a waiter that dies leaves the line.

  Callers use `Gamend.Lock.Local`, which keeps the reentrancy, not this.
  """
  use GenServer

  @doc false
  def child_spec(_opts) do
    partition = %{id: __MODULE__, start: {GenServer, :start_link, [__MODULE__, nil]}}
    PartitionSupervisor.child_spec(child_spec: partition, name: __MODULE__)
  end

  @doc "Whether the partitions are running (they start with the host's tree)."
  @spec running?() :: boolean()
  def running?, do: Process.whereis(__MODULE__) != nil

  @doc "Blocks until the calling process holds `key`."
  @spec acquire(term()) :: :ok
  def acquire(key), do: GenServer.call(partition(key), {:acquire, key}, :infinity)

  @doc "Hands `key` to the next caller in line. A key the caller does not hold is ignored."
  @spec release(term()) :: :ok
  def release(key), do: GenServer.cast(partition(key), {:release, key, self()})

  @doc false
  # Who holds `key` now, for tests that check a lock is not held.
  @spec holder(term()) :: pid() | nil
  def holder(key), do: GenServer.call(partition(key), {:holder, key})

  defp partition(key), do: {:via, PartitionSupervisor, {__MODULE__, key}}

  @impl true
  def init(nil), do: {:ok, %{locks: %{}, refs: %{}}}

  @impl true
  def handle_call({:holder, key}, _from, state) do
    holder =
      case state.locks do
        %{^key => {pid, _ref, _waiting}} -> pid
        _free -> nil
      end

    {:reply, holder, state}
  end

  def handle_call({:acquire, key}, {pid, _tag} = from, state) do
    ref = Process.monitor(pid)
    state = put_in(state.refs[ref], key)

    case state.locks do
      %{^key => {holder, holder_ref, waiting}} ->
        waiting = :queue.in({from, pid, ref}, waiting)
        {:noreply, put_in(state.locks[key], {holder, holder_ref, waiting})}

      _free ->
        {:reply, :ok, put_in(state.locks[key], {pid, ref, :queue.new()})}
    end
  end

  @impl true
  def handle_cast({:release, key, pid}, state) do
    case state.locks do
      %{^key => {^pid, ref, waiting}} ->
        Process.demonitor(ref, [:flush])
        {:noreply, next(key, waiting, %{state | refs: Map.delete(state.refs, ref)})}

      _other ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    {key, refs} = Map.pop(state.refs, ref)
    state = %{state | refs: refs}

    case state.locks do
      # The holder died inside its section.
      %{^key => {_holder, ^ref, waiting}} ->
        {:noreply, next(key, waiting, state)}

      # A waiter died in line.
      %{^key => {holder, holder_ref, waiting}} ->
        waiting = :queue.filter(fn {_from, _pid, r} -> r != ref end, waiting)
        {:noreply, put_in(state.locks[key], {holder, holder_ref, waiting})}

      _gone ->
        {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp next(key, waiting, state) do
    case :queue.out(waiting) do
      {{:value, {from, pid, ref}}, rest} ->
        GenServer.reply(from, :ok)
        put_in(state.locks[key], {pid, ref, rest})

      {:empty, _} ->
        %{state | locks: Map.delete(state.locks, key)}
    end
  end
end
