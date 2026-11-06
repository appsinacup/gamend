defmodule Gamend.Presence do
  @moduledoc """
  Cluster-wide tracking of who is connected where.

  Backed by `Phoenix.Presence`, so entries are tied to process liveness and
  replicated between nodes by CRDT: a node that dies takes its entries with it,
  with no sweeper to notice. That is the property node-local ETS and database
  flags both lack.

  Used for signaling room membership and lobby spectators. Not for anything
  queried in SQL — presence lives in memory and cannot be joined against a
  table — and not for anything durable, since a full cluster restart empties it.

  During a netsplit each side sees only its own members until they heal.

  ## Reads

  Read through `keys/1` and `last_socket?/1`, never `list/1` or
  `get_by_key/2`. phoenix_pubsub 2.4 answers those two with a call to the
  topic's shard whose reply is its whole state, a tag for every presence on
  it, which the caller then filters: at 2,000 players each call copied ~1 MB
  and queued behind every other on the one shard process, and a thousand
  disconnects at once ran a 1 GB server out of memory. These read the shard's
  protected table instead, only the topic asked for. Unlike the two they
  replace they keep the entries of a replica that just went down, until the
  tracker removes them.
  """
  use Phoenix.Presence,
    otp_app: :gamend_core,
    pubsub_server: Gamend.PubSub

  alias Phoenix.Tracker.Shard
  alias Phoenix.Tracker.State

  # Connected users are spread over this many topics rather than tracked on one.
  #
  # `Phoenix.Tracker` shards its work by topic, so a single "users" topic pins
  # every presence diff in the cluster to one shard no matter how large
  # :pool_size is, and puts every connected user in one CRDT state. Bucketing
  # by user id is what lets the pool actually spread.
  #
  # Compile-time constant on purpose: every node must bucket identically, so
  # this is not configurable (a rolling deploy that changed it would split the
  # tracker). :pool_size is configurable and carries the same constraint —
  # see `config :gamend_core, Gamend.Presence, pool_size: n`, which needs a
  # full restart rather than a rolling one.
  @users_buckets 64

  @doc "Topic this user is tracked on."
  @spec users_topic(Ecto.UUID.t()) :: String.t()
  def users_topic(user_id), do: "users:#{:erlang.phash2(user_id, @users_buckets)}"

  @doc "Number of topics connected users are spread over."
  @spec users_buckets() :: pos_integer()
  def users_buckets, do: @users_buckets

  @doc """
  The distinct keys tracked on `topic`, as strings and sorted: the keys of
  `list/1`, without its copy (*Reads*). Cluster-wide.
  """
  @spec keys(String.t()) :: [String.t()]
  def keys(topic) when is_binary(topic) do
    topic
    |> shard()
    |> State.tracked_values(topic, [])
    |> Enum.map(fn {key, _meta} -> to_string(key) end)
    |> Enum.sort()
    |> Enum.dedup()
  end

  @doc """
  The entries tracked on `topic`, `{key, meta}`, one per tracked process (two
  tabs of one player are two). `keys/1` with the meta, read the same way
  (*Reads*). Cluster-wide.
  """
  @spec entries(String.t()) :: [{String.t(), map()}]
  def entries(topic) when is_binary(topic) do
    topic
    |> shard()
    |> State.tracked_values(topic, [])
    |> Enum.map(fn {key, meta} -> {to_string(key), meta} end)
  end

  @doc """
  Whether `user_id` has a socket tracked other than `pid`'s. Exact whether or
  not `pid`'s own entry is still there, so a process watching a socket that
  has already gone can ask it too (`Gamend.Accounts.Online`).
  """
  @spec other_socket?(Ecto.UUID.t(), pid()) :: boolean()
  def other_socket?(user_id, pid) when is_pid(pid) do
    topic = users_topic(user_id)

    topic
    |> shard()
    |> State.tracked_key(topic, user_id, [])
    |> Enum.any?(fn {other, _meta} -> other != pid end)
  end

  @doc """
  Whether the calling process holds this user's only tracked socket.

  Cluster-wide, unlike the per-node registry count it replaces.
  """
  @spec last_socket?(Ecto.UUID.t()) :: boolean()
  def last_socket?(user_id) do
    topic = users_topic(user_id)

    # Every disconnect asks this (*Reads*). An entry of a replica that just
    # went down reads as another socket, so that user stays online until the
    # stale sweeper marks them offline.
    length(State.tracked_key(shard(topic), topic, user_id, [])) <= 1
  end

  # The shard's table is named for the shard, found as `Phoenix.Tracker` finds it.
  defp shard(topic), do: Shard.name_for_topic(__MODULE__, topic, pool_size())

  # The tracker's own record of its shard count, as `Phoenix.Tracker` reads it.
  defp pool_size do
    [{:pool_size, size}] = :ets.lookup(__MODULE__, :pool_size)
    size
  end

  # Deliberately no `handle_metas/4` here. Writing `users.is_online` from the
  # tracker process means a database hiccup exits the tracker and takes every
  # room's presence with it. The channel owns that write instead, using
  # `last_socket?/1` to get the cluster-wide answer.
end
