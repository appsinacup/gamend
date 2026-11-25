defmodule GamendWeb.ConnectionTracker do
  @moduledoc """
  Tracks active WebSocket channel and WebRTC peer connections using a `Registry`
  with `:duplicate` keys.

  Each channel process registers itself on join via `register/2`. Because
  `Registry` links to the registering process, entries are automatically
  removed when the process terminates — no manual cleanup needed.

  ## Connection types

  - `:ws_socket`       — raw WebSocket connections (1 per client)
  - `:user_channel`    — authenticated user WebSocket channels
  - `:lobby_channel`   — per-lobby channels (members + spectators)
  - `:lobbies_channel` — global lobbies listing channel
  - `:group_channel`   — per-group channels
  - `:groups_channel`  — global groups listing channel
  - `:party_channel`   — per-party channels
  - `:live_view`       — active LiveView connections (browser tabs)
  - `:webrtc_peer`     — active WebRTC DataChannel peers
  """

  @registry __MODULE__.Registry
  # One key per process, so a count is the table's size: what the
  # server-wide caps read on every new socket and sign-in, without walking
  # every connection on the node.
  @sockets __MODULE__.Sockets
  @logins __MODULE__.Logins

  @doc """
  Returns the child spec of the registries: the typed one, and the two
  counted ones behind `count_all_ws_sockets/0` and `count_logins/0`.
  Add this to your supervision tree before the Endpoint.
  """
  def child_spec(_opts) do
    children = [
      Registry.child_spec(keys: :duplicate, name: @registry),
      Supervisor.child_spec(Registry.child_spec(keys: :unique, name: @sockets), id: @sockets),
      Supervisor.child_spec(Registry.child_spec(keys: :unique, name: @logins), id: @logins)
    ]

    %{
      id: __MODULE__,
      type: :supervisor,
      start: {Supervisor, :start_link, [children, [strategy: :one_for_one]]}
    }
  end

  @doc """
  Registers the calling process under the given connection `type`.
  Optional `metadata` map is stored alongside the registration.

  Returns `{:ok, pid}` or `{:error, term}`.
  No-op if the registry hasn't been started yet.
  """
  def register(type, metadata \\ %{}) do
    Registry.register(@registry, type, metadata)
  rescue
    ArgumentError -> {:error, :registry_not_started}
  end

  @doc """
  Registers a raw WebSocket under both the `:ws_socket` type (for counts and
  the admin runtime page) and a per-user key.

  The per-user key is what the connection limit is counted from: scanning the
  `:ws_socket` duplicate key returns every socket on the node, which made each
  new connection O(all sockets) and a connection storm O(n^2).
  """
  def register_ws_socket(user_id, metadata) do
    _ = register(:ws_socket, metadata)
    _ = register({:ws_socket, user_id}, %{})

    try do
      _ = Registry.register(@sockets, self(), nil)
    rescue
      ArgumentError -> :ok
    end

    :ok
  end

  @doc """
  Counts this user's live WebSocket connections on this node.
  """
  def count_ws_sockets(user_id) do
    @registry |> Registry.lookup({:ws_socket, user_id}) |> length()
  rescue
    ArgumentError -> 0
  end

  @doc "Counts every live WebSocket connection on this node, whoever's."
  def count_all_ws_sockets do
    Registry.count(@sockets)
  rescue
    ArgumentError -> 0
  end

  @doc """
  Marks the calling request process as a sign-in in flight, until
  `finish_login/0` or the process ends. `GamendWeb.Plugs.LoginGate`.
  """
  def start_login do
    _ = Registry.register(@logins, self(), nil)
    :ok
  rescue
    ArgumentError -> :ok
  end

  @doc "The calling process's sign-in is answered."
  def finish_login do
    Registry.unregister(@logins, self())
  rescue
    ArgumentError -> :ok
  end

  @doc "Sign-ins being served on this node now."
  def count_logins do
    Registry.count(@logins)
  rescue
    ArgumentError -> 0
  end

  @doc """
  Registers a user channel under the `:user_channel` type, which the admin
  connections page counts.

  There is no per-user registration: "does this user have any other socket?"
  on disconnect is `Gamend.Presence.last_socket?/1`, which sees the whole
  cluster rather than one node (see `GamendWeb.UserChannel.terminate/2`), so
  a channel join pays for no registry write without a reader.
  """
  def register_user_channel(user_id) do
    _ = register(:user_channel, %{user_id: user_id})
    :ok
  end

  @doc """
  Returns the count of processes registered under `type`.
  Returns 0 if the registry hasn't been started yet.
  """
  def count(type) do
    Registry.count_match(@registry, type, :_)
  rescue
    ArgumentError -> 0
  end

  @doc """
  Returns a list of `{pid, metadata}` tuples for all processes registered
  under the given `type`.
  """
  def list_registered(type) do
    Registry.lookup(@registry, type)
  rescue
    ArgumentError -> []
  end

  @doc """
  Returns all connection types and their registered processes.
  """
  def all_registered do
    types = [
      :ws_socket,
      :user_channel,
      :lobby_channel,
      :lobbies_channel,
      :group_channel,
      :groups_channel,
      :party_channel,
      :webrtc_peer,
      :live_view
    ]

    Map.new(types, fn type -> {type, list_registered(type)} end)
  end

  @doc """
  Returns a map with counts for every tracked connection type plus totals.
  In a clustered environment, this only counts connections on the local node.
  Use `cluster_counts/0` for aggregated counts across all nodes.
  """
  def all_counts do
    ws_sockets = count(:ws_socket)
    user = count(:user_channel)
    lobby = count(:lobby_channel)
    lobbies = count(:lobbies_channel)
    group = count(:group_channel)
    groups = count(:groups_channel)
    party = count(:party_channel)
    webrtc = count(:webrtc_peer)
    live_views = count(:live_view)

    total_channels = user + lobby + lobbies + group + groups + party

    %{
      ws_sockets: ws_sockets,
      user_channels: user,
      lobby_channels: lobby,
      lobbies_channels: lobbies,
      group_channels: group,
      groups_channels: groups,
      party_channels: party,
      webrtc_peers: webrtc,
      live_views: live_views,
      total_channels: total_channels,
      total_connections: ws_sockets + live_views + webrtc
    }
  end

  @doc """
  Returns aggregated connection counts across all connected nodes in the cluster.
  Falls back to local-only counts if the cluster has a single node.
  """
  def cluster_counts do
    nodes = [node() | Node.list()]

    if length(nodes) == 1 do
      all_counts()
    else
      results =
        :erpc.multicall(nodes, __MODULE__, :all_counts, [], 5_000)
        |> Enum.flat_map(fn
          {:ok, counts} -> [counts]
          _ -> []
        end)

      Enum.reduce(
        results,
        %{
          ws_sockets: 0,
          user_channels: 0,
          lobby_channels: 0,
          lobbies_channels: 0,
          group_channels: 0,
          groups_channels: 0,
          party_channels: 0,
          webrtc_peers: 0,
          live_views: 0,
          total_channels: 0,
          total_connections: 0
        },
        fn counts, acc ->
          Map.merge(acc, counts, fn _k, v1, v2 -> v1 + v2 end)
        end
      )
    end
  end

  @doc """
  Returns BEAM system statistics useful for the admin dashboard.
  """
  def system_stats do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    memory = :erlang.memory()

    %{
      process_count: :erlang.system_info(:process_count),
      process_limit: :erlang.system_info(:process_limit),
      port_count: :erlang.system_info(:port_count),
      port_limit: :erlang.system_info(:port_limit),
      memory_total_mb: Float.round(memory[:total] / 1_048_576, 1),
      memory_processes_mb: Float.round(memory[:processes] / 1_048_576, 1),
      memory_ets_mb: Float.round(memory[:ets] / 1_048_576, 1),
      uptime_seconds: div(uptime_ms, 1000),
      schedulers: :erlang.system_info(:schedulers_online),
      otp_release: to_string(:erlang.system_info(:otp_release)),
      node: node(),
      cluster_size: 1 + length(Node.list())
    }
  end
end
