defmodule Gamend.Bans.Cache do
  @moduledoc """
  Node-local hot path for `Gamend.Bans`: every active ban in ETS, keyed by its
  target (`Gamend.Bans.Ban.target/4`, `{kind, subject, scope}`), read on each
  request an IP ban covers and each chat message a mute covers.

  The database is the source of truth; this mirrors it, and PubSub carries each
  change to the other instances, where `Gamend.Bans.Sync` applies it (and loads
  the table at boot). An entry past its end is dropped as it is read, so a ban
  never outlives its expiry whether or not anything sweeps.
  """

  alias Gamend.Bans
  alias Gamend.Bans.Ban

  @ban "ban"

  @table :bans
  @topic "bans"

  @doc "PubSub topic on which ban changes are broadcast."
  @spec topic() :: String.t()
  def topic, do: @topic

  @doc "Ensure the ETS table exists (called once at app startup)."
  @spec init_table() :: :ok
  def init_table do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    end

    :ok
  end

  @doc "Whether `target` has an active ban on this node."
  @spec active?(tuple()) :: boolean()
  def active?(target) do
    init_table()
    key = target

    case :ets.lookup(@table, key) do
      [{^key, :infinity}] ->
        true

      [{^key, %DateTime{} = expires_at}] ->
        if DateTime.after?(expires_at, DateTime.utc_now()) do
          true
        else
          :ets.delete(@table, key)
          false
        end

      [] ->
        false
    end
  end

  @doc "Mirror a ban locally and on the other instances."
  @spec put(Ban.t()) :: :ok
  def put(%Ban{expires_at: expires_at} = ban) do
    key = Ban.target(ban)
    apply_put(key, expires_at)
    broadcast({:bans, :put, {key, expires_at}, Node.self()})
  end

  @doc "Remove a target's ban locally and on the other instances."
  @spec delete(tuple()) :: :ok
  def delete(target) do
    key = target
    apply_delete(key)
    broadcast({:bans, :deleted, key, Node.self()})
  end

  @doc """
  The active bans on this node, of one kind or all, as
  `[{kind, subject, expires_at | :infinity}]`: no query, for counts on a page.
  """
  @spec list(Ban.kind() | nil) :: [{Ban.kind(), String.t(), DateTime.t() | :infinity}]
  def list(only_kind \\ nil) do
    init_table()
    now = DateTime.utc_now()

    for {{kind, subject, _scope}, expires_at} <- :ets.tab2list(@table),
        only_kind in [nil, kind],
        expires_at == :infinity or DateTime.after?(expires_at, now),
        do: {kind, subject, expires_at}
  end

  @doc """
  Load every active ban from the database into ETS, replacing what was there.

  Called at boot by `Gamend.Bans.Sync`.
  """
  @spec load_persisted() :: :ok
  def load_persisted do
    bans = Bans.list_active()
    init_table()
    :ets.delete_all_objects(@table)
    Enum.each(bans, &apply_put(Ban.target(&1), &1.expires_at))
  end

  @doc """
  Apply a change that originated on another instance.

  Only touches ETS — the originating instance already persisted it.
  """
  @spec apply_remote(atom(), term()) :: :ok
  def apply_remote(:put, {key, expires_at}), do: apply_put(key, expires_at)
  def apply_remote(:deleted, key), do: apply_delete(key)
  def apply_remote(_event, _payload), do: :ok

  defp apply_put(key, expires_at) do
    init_table()
    :ets.insert(@table, {key, expires_at || :infinity})
    :ok
  end

  defp apply_delete(key) do
    init_table()
    :ets.delete(@table, key)
    :ok
  end

  # Best-effort: a ban still applies on this node when PubSub is unavailable.
  defp broadcast(message), do: Gamend.Broadcast.best_effort(@topic, message, @ban)
end
