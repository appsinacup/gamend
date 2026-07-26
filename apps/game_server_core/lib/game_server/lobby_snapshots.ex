defmodule GameServer.LobbySnapshots do
  @moduledoc """
  Durable record of how a lobby's state evolved during a run.

  A lobby *is* a run — each level quick-joins a fresh lobby — so `lobby_id` is
  the correlation key and needs no separate id. A timeline reads
  `snapshot N -> [events] -> snapshot N+1`: snapshots record *what* changed,
  events record *why*.

  Two entry points, both cheap for callers:

  - `capture_lobby/3` at a mutation entry point (hook completion, game-loop
    message, lobby teardown).
  - `record_event/4` where a decision is worth explaining.

  Both enqueue into `GameServer.LobbySnapshots.Writer` rather than writing
  inline — call sites live in the serialized game loop, where a DB round trip
  shows up as gameplay stutter.

  Disabled by default; see `enabled?/0`.
  """

  import Ecto.Query

  require Logger

  alias GameServer.LobbySnapshots.{Blob, Event, Snapshot, Writer}
  alias GameServer.Repo

  @doc """
  Whether capture is currently on.

  Checked before any gathering work, so leaving call sites in hot paths costs a
  single `Application.get_env` when off.
  """
  @spec enabled?() :: boolean()
  def enabled?, do: config(:enabled, false) == true

  @doc """
  Capture the current state of a lobby, attributing it to `trigger`.

  `trigger` names what caused the mutation — `"hook:finish_boat_game"`,
  `"timer:scheduled_collision"`, `"lobby:deleted"`. Options:

  - `:sync` — gather inline instead of off the caller's process. Required when
    the state is about to disappear (lobby teardown), where an async gather
    would race the delete and capture nothing.
  - `:flagged` — mark the run as anomalous, exempting it from the default
    retention sweep. Set this when the mutation errored.
  - `:user_id` — attribution for the mutation.

  Returns `:ok` regardless; capture must never fail a caller's real work.
  """
  @spec capture_lobby(String.t(), String.t(), keyword()) :: :ok
  def capture_lobby(lobby_id, trigger, opts \\ [])

  def capture_lobby(lobby_id, trigger, opts)
      when is_binary(lobby_id) and is_binary(trigger) and is_list(opts) do
    if enabled?() do
      gather = fn -> enqueue_capture(lobby_id, trigger, opts) end

      if Keyword.get(opts, :sync, false) do
        gather.()
      else
        GameServer.Async.run(gather)
      end
    end

    :ok
  end

  def capture_lobby(_lobby_id, _trigger, _opts), do: :ok

  @doc """
  Record a decision that happened within the current snapshot interval.

  `payload` carries the fields that explain the decision — a snapshot can show
  `speed: 100 -> 50`, but only an event carries the `gap` that caused it.
  """
  @spec record_event(String.t(), String.t(), map(), keyword()) :: :ok
  def record_event(lobby_id, kind, payload \\ %{}, opts \\ [])

  def record_event(lobby_id, kind, payload, opts)
      when is_binary(lobby_id) and is_binary(kind) and is_map(payload) and is_list(opts) do
    if enabled?() do
      Writer.enqueue_event(%{
        lobby_id: lobby_id,
        kind: kind,
        payload: jsonable(payload),
        user_id: Keyword.get(opts, :user_id)
      })
    end

    :ok
  end

  def record_event(_lobby_id, _kind, _payload, _opts), do: :ok

  # Event payloads are arbitrary plugin terms, and the column is jsonb. A single
  # tuple or pid in one payload would fail encoding at insert time and take the
  # writer's whole batch with it, so unrepresentable terms are coerced here
  # rather than trusted. Sanitising in core means every plugin gets this, not
  # just the one that happened to think about it.
  defp jsonable(term) when is_map(term) and not is_struct(term) do
    Map.new(term, fn {k, v} -> {jsonable_key(k), jsonable(v)} end)
  end

  defp jsonable(%mod{} = term) when mod in [DateTime, NaiveDateTime, Date, Time], do: term
  defp jsonable(%_{} = term), do: term |> Map.from_struct() |> jsonable()
  defp jsonable(term) when is_list(term), do: Enum.map(term, &jsonable/1)
  defp jsonable(term) when is_tuple(term), do: term |> Tuple.to_list() |> jsonable()
  defp jsonable(term) when is_number(term) or is_boolean(term) or is_nil(term), do: term
  defp jsonable(term) when is_atom(term), do: term

  defp jsonable(term) when is_binary(term) do
    # Binaries need not be text — a raw packet fragment in a debug payload would
    # otherwise fail JSON encoding.
    if String.valid?(term), do: term, else: inspect(term)
  end

  defp jsonable(term), do: inspect(term)

  defp jsonable_key(key) when is_binary(key), do: key
  defp jsonable_key(key) when is_atom(key), do: Atom.to_string(key)
  defp jsonable_key(key), do: inspect(key)

  @coverage_prefix "coverage:"

  @doc """
  Record that a mutation happened somewhere capture cannot see.

  A plugin calls this from a tripwire that detects state being written outside
  the chokepoints capture hangs off — polyglot's `warn_if_unserialized_write/1`
  is the first. Such a write is *by definition* a mutation missing from the
  snapshots, so this is the system reporting its own blind spots.

  Stored as an ordinary event, deliberately: a gap is most useful read in the
  timeline where it happened, next to the snapshots that are consequently
  incomplete. The admin view also lists them across lobbies.
  """
  @spec record_coverage_gap(String.t(), String.t(), map()) :: :ok
  def record_coverage_gap(lobby_id, source, details \\ %{})

  def record_coverage_gap(lobby_id, source, details)
      when is_binary(lobby_id) and is_binary(source) and is_map(details) do
    record_event(lobby_id, @coverage_prefix <> source, details)
  end

  def record_coverage_gap(_lobby_id, _source, _details), do: :ok

  @doc "Coverage gaps across all lobbies, newest first."
  @spec list_coverage_gaps(keyword()) :: [Event.t()]
  def list_coverage_gaps(opts \\ []) when is_list(opts) do
    limit = Keyword.get(opts, :limit, 50)
    pattern = @coverage_prefix <> "%"

    Repo.all(
      from e in Event,
        where: like(e.kind, ^pattern),
        order_by: [desc: e.inserted_at, desc: e.id],
        limit: ^limit
    )
  end

  @doc "Whether an event kind marks a coverage gap rather than a game decision."
  @spec coverage_gap?(Event.t() | String.t()) :: boolean()
  def coverage_gap?(%Event{kind: kind}), do: coverage_gap?(kind)
  def coverage_gap?(kind) when is_binary(kind), do: String.starts_with?(kind, @coverage_prefix)

  @doc """
  Capture after a hook completed, attributing it to the hook's caller.

  Core cannot read a lobby out of a hook's arguments — they are plugin-defined —
  and the only context it injects is the caller. So this resolves the caller's
  *current* lobby and captures against that, skipping entirely when the caller
  is absent or not in one. A hook that mutates lobby state on behalf of someone
  outside it is invisible here and needs `capture_lobby/3` at its own chokepoint.

  Everything including the caller lookup happens off the hook's process, so a
  hook call pays one `Application.get_env` when capture is disabled and one task
  spawn when it is on.
  """
  @spec capture_hook(atom() | String.t(), term(), term()) :: :ok
  def capture_hook(name, caller, result) do
    if enabled?() do
      flagged = match?({:error, _}, result)

      GameServer.Async.run(fn ->
        case caller_lobby_id(caller) do
          nil ->
            :ok

          lobby_id ->
            enqueue_capture(lobby_id, "hook:#{name}",
              flagged: flagged,
              user_id: caller_id(caller)
            )
        end
      end)
    end

    :ok
  end

  # Re-read rather than trusting the caller struct's lobby_id: the struct was
  # resolved before the hook ran, so a hook that joined a lobby would otherwise
  # capture nil. The read is cached (Accounts.get_user/1), and it runs off the
  # hook path.
  defp caller_lobby_id(caller) do
    case caller_id(caller) do
      nil -> nil
      id -> with %{lobby_id: lobby_id} <- GameServer.Accounts.get_user(id), do: lobby_id
    end
  end

  defp caller_id(%{id: id}) when is_binary(id), do: id
  defp caller_id(id) when is_binary(id), do: id
  defp caller_id(_), do: nil

  ## Gathering

  defp enqueue_capture(lobby_id, trigger, opts) do
    case gather_sections(lobby_id) do
      sections when map_size(sections) > 0 ->
        Writer.enqueue_snapshot(%{
          lobby_id: lobby_id,
          trigger: trigger,
          sections: hash_sections(sections),
          flagged: Keyword.get(opts, :flagged, false),
          user_id: Keyword.get(opts, :user_id)
        })

      _ ->
        # Lobby already gone and nothing left to read — a capture that lost the
        # race with teardown. Nothing to record.
        :ok
    end
  rescue
    e ->
      Logger.warning("lobby_snapshots: gather failed lobby_id=#{lobby_id} #{inspect(e)}")
      :ok
  end

  # Hashed here rather than in the writer: the writer is one process serving
  # every lobby, so CPU spent inside it serializes everyone else's captures.
  # This runs on the calling (already off-hot-path) process instead.
  defp hash_sections(sections) do
    Map.new(sections, fn {name, content} -> {name, {content_hash(content), content}} end)
  end

  # Deterministic term encoding rather than JSON: map key order is not
  # guaranteed stable across encodes, and identical content must hash
  # identically or dedup silently stops working.
  defp content_hash(content) do
    :sha256
    |> :crypto.hash(:erlang.term_to_binary(content, [:deterministic]))
    |> binary_part(0, 16)
    |> Base.encode16(case: :lower)
  end

  @doc """
  Read every section of a lobby's current state, as raw (unhashed) content.

  Public so plugins can reuse the same view of a lobby that capture records.
  """
  @spec gather_sections(String.t()) :: %{String.t() => map() | list()}
  def gather_sections(lobby_id) when is_binary(lobby_id) do
    case GameServer.Lobbies.get_lobby(lobby_id) do
      nil ->
        # KV outlives the lobby row only until the delete commits, so a
        # teardown capture can still find entries worth keeping. Nothing left to
        # read means nothing to record, and enqueue_capture skips it.
        case kv_lobby(lobby_id) do
          [] -> %{}
          entries -> %{"kv_lobby" => entries}
        end

      lobby ->
        members = members(lobby_id)

        # Every section is emitted, empty ones included. Omitting an empty
        # section would make "emptied" indistinguishable from "unchanged", and
        # since state_at resolves each section from its latest occurrence, the
        # stale value would linger for the rest of the run. Empty sections cost
        # one deduped blob across the whole table.
        %{
          "lobby" => lobby_section(lobby),
          "lobby_metadata" => lobby.metadata || %{},
          "members" => members,
          "kv_lobby" => kv_lobby(lobby_id),
          "kv_user" => kv_user(lobby_id, members)
        }
    end
  end

  defp lobby_section(lobby) do
    Map.take(lobby, [
      :id,
      :title,
      :host_id,
      :hostless,
      :max_users,
      :is_hidden,
      :is_locked,
      :slowdown,
      :inserted_at,
      :updated_at
    ])
  end

  # Ids and in-lobby state only. No username, email or profile fields: account
  # deletion cannot reach data embedded in JSONB, so the way to keep a deleted
  # user's details out of snapshots is to never store them. The admin view joins
  # display names at read time, so a deleted user renders as a bare id.
  defp members(lobby_id) do
    Repo.all(
      from u in GameServer.Accounts.User,
        where: u.lobby_id == ^lobby_id,
        order_by: u.inserted_at,
        select: %{id: u.id, metadata: u.metadata, is_online: u.is_online}
    )
  end

  defp kv_lobby(lobby_id) do
    [lobby_id: lobby_id, page_size: config(:max_kv_entries, 200)]
    |> GameServer.KV.list_entries()
    |> Enum.map(&kv_entry_section/1)
  end

  # Bounded by a configured key list rather than dumping every key the user
  # owns: user-scoped KV is the widest privacy exposure in a snapshot, and the
  # default of `[]` captures none of it.
  defp kv_user(_lobby_id, members) do
    case config(:user_kv_keys, []) do
      [] ->
        []

      keys ->
        page_size = config(:max_kv_entries, 200)

        Enum.flat_map(members, fn %{id: user_id} ->
          # `KV.list_entries/1` takes ONE `:key` — a substring LIKE filter, not
          # a list. Passing the configured list raised FunctionClauseError in
          # `normalize_key_filter/1` and failed the whole gather, so every run
          # with `user_kv_keys` set recorded nothing. Query per key and merge.
          keys
          |> Enum.flat_map(fn key ->
            GameServer.KV.list_entries(user_id: user_id, key: key, page_size: page_size)
          end)
          # A key can match several filters (`word_stats` and `word_stats:en`),
          # and the same entry must not be captured twice.
          |> Enum.uniq_by(&{&1.key, &1.user_id, &1.lobby_id})
          |> Enum.map(&kv_entry_section/1)
        end)
    end
  end

  defp kv_entry_section(entry) do
    Map.take(entry, [:key, :user_id, :lobby_id, :value, :metadata, :updated_at])
  end

  ## Reads

  @doc """
  Reconstruct full state as of a given snapshot.

  For each section, take the latest occurrence at or before that snapshot.
  Sections are stored whole, so this is a lookup — never a merge.
  """
  @spec state_at(Snapshot.t()) :: %{String.t() => term()}
  def state_at(%Snapshot{} = snapshot) do
    hashes =
      Repo.all(
        from s in Snapshot,
          where: s.lobby_id == ^snapshot.lobby_id,
          where: {s.inserted_at, s.id} <= {^snapshot.inserted_at, ^snapshot.id},
          order_by: [asc: s.inserted_at, asc: s.id],
          select: s.section_hashes
      )
      |> Enum.reduce(%{}, &Map.merge(&2, &1))

    blobs = load_blobs(Map.values(hashes))

    Map.new(hashes, fn {section, hash} -> {section, Map.get(blobs, hash)} end)
  end

  @doc """
  A lobby's snapshots in order, each with the events that followed it.

  Reads as `snapshot -> [events] -> snapshot -> [events]`. An event belongs to
  the interval opened by the latest snapshot at or before it; events preceding
  the first snapshot land in `:prologue`.

  `index` is a 1-based display number derived here rather than stored — nothing
  has to hand out sequence numbers at write time for this to be stable.
  """
  @spec timeline(String.t()) :: %{prologue: [Event.t()], intervals: [map()]}
  def timeline(lobby_id) when is_binary(lobby_id) do
    snapshots = list_snapshots(lobby_id)
    events = list_events(lobby_id)

    {prologue, rest} =
      case snapshots do
        [] -> {events, []}
        [first | _] -> Enum.split_while(events, &before?(&1, first))
      end

    intervals =
      snapshots
      |> Enum.with_index(1)
      |> assign_events(rest, [])

    %{prologue: prologue, intervals: intervals}
  end

  defp assign_events([], _events, acc), do: Enum.reverse(acc)

  defp assign_events([{snapshot, index} | tail], events, acc) do
    # Everything up to the next snapshot belongs to this one's interval.
    {mine, rest} =
      case tail do
        [] -> {events, []}
        [{next, _} | _] -> Enum.split_while(events, &before?(&1, next))
      end

    assign_events(tail, rest, [%{snapshot: snapshot, index: index, events: mine} | acc])
  end

  defp before?(%Event{} = event, %Snapshot{} = snapshot) do
    {event.inserted_at, event.id} < {snapshot.inserted_at, snapshot.id}
  end

  @doc "Load blob content for a list of hashes, as a hash => content map."
  @spec load_blobs([String.t()]) :: %{String.t() => map() | list()}
  def load_blobs(hashes) when is_list(hashes) do
    hashes = Enum.uniq(hashes)

    Repo.all(from b in Blob, where: b.hash in ^hashes, select: {b.hash, b.content})
    # Unwrap the storage envelope the writer adds so list-shaped sections
    # (`members`, `kv_lobby`) survive a :map column.
    |> Map.new(fn {hash, content} -> {hash, Map.get(content, "v")} end)
  end

  @doc """
  Field-level differences between two snapshots' state.

  Returns `%{section => [%{path: ["a", "b"], from: term, to: term}]}`, with
  unchanged sections omitted entirely. Paths are flattened, so a field buried in
  nested maps reads as `["boat_adventure", "effects", "speed_reduced"]` rather
  than requiring the reader to walk two nested objects to spot it.

  This is the point of the whole system: a value that reverts between snapshots
  should be visible at a glance rather than reconstructed by hand.
  """
  @spec diff(Snapshot.t(), Snapshot.t()) :: %{String.t() => [map()]}
  def diff(%Snapshot{} = from, %Snapshot{} = to) do
    before_state = state_at(from)
    after_state = state_at(to)

    # Only sections whose hash actually moved can contain changes, so this skips
    # the deep walk for everything else.
    from.section_hashes
    |> Map.merge(to.section_hashes)
    |> Map.keys()
    |> Enum.reduce(%{}, fn section, acc ->
      if Map.get(from.section_hashes, section) == Map.get(to.section_hashes, section) do
        acc
      else
        case diff_terms(Map.get(before_state, section), Map.get(after_state, section), []) do
          [] -> acc
          changes -> Map.put(acc, section, changes)
        end
      end
    end)
  end

  # `path` accumulates reversed and is flipped at the leaf, so descending a
  # level is a prepend rather than a list append.
  defp diff_terms(same, same, _path), do: []

  # A section (or nested key) that appears or disappears still diffs field by
  # field, rather than collapsing into one row holding the whole structure.
  defp diff_terms(nil, %{} = later, path), do: diff_terms(%{}, later, path)
  defp diff_terms(%{} = before, nil, path), do: diff_terms(before, %{}, path)
  defp diff_terms(nil, later, path) when is_list(later), do: diff_terms([], later, path)
  defp diff_terms(before, nil, path) when is_list(before), do: diff_terms(before, [], path)

  defp diff_terms(%{} = before, %{} = later, path) do
    before
    |> Map.keys()
    |> Enum.concat(Map.keys(later))
    |> Enum.uniq()
    |> Enum.sort_by(&to_string/1)
    |> Enum.flat_map(fn key ->
      diff_terms(Map.get(before, key), Map.get(later, key), [to_string(key) | path])
    end)
  end

  # Lists are compared positionally. `members` and `kv_*` are ordered
  # deterministically by their gatherers, so position is stable and an index in
  # the path is meaningful.
  defp diff_terms(before, later, path) when is_list(before) and is_list(later) do
    max = max(length(before), length(later))

    Enum.flat_map(0..(max - 1)//1, fn i ->
      diff_terms(Enum.at(before, i), Enum.at(later, i), ["#{i}" | path])
    end)
  end

  defp diff_terms(before, later, path) do
    [%{path: Enum.reverse(path), from: before, to: later}]
  end

  @doc "Snapshots for a lobby, oldest first."
  @spec list_snapshots(String.t()) :: [Snapshot.t()]
  def list_snapshots(lobby_id) when is_binary(lobby_id) do
    Repo.all(
      from s in Snapshot,
        where: s.lobby_id == ^lobby_id,
        order_by: [asc: s.inserted_at, asc: s.id]
    )
  end

  @doc "Events for a lobby, oldest first."
  @spec list_events(String.t()) :: [Event.t()]
  def list_events(lobby_id) when is_binary(lobby_id) do
    Repo.all(
      from e in Event,
        where: e.lobby_id == ^lobby_id,
        order_by: [asc: e.inserted_at, asc: e.id]
    )
  end

  @doc """
  Distinct lobbies that have snapshots, newest first.

  The lobby row is usually gone by the time anyone reads this, so the listing is
  built from the snapshots themselves rather than joined against `lobbies`.
  """
  @spec list_lobbies(keyword()) :: [map()]
  def list_lobbies(opts \\ []) when is_list(opts) do
    limit = Keyword.get(opts, :limit, 50)

    # A CASE expression rather than casting the boolean: Postgres refuses
    # `boolean::bigint` outright, and SQLite only tolerates it because its
    # booleans are already integers. Both accept this form.
    query =
      from s in Snapshot,
        group_by: s.lobby_id,
        order_by: [desc: max(s.inserted_at)],
        limit: ^limit,
        select: %{
          lobby_id: s.lobby_id,
          snapshots: count(s.id),
          flagged: max(fragment("CASE WHEN ? THEN 1 ELSE 0 END", s.flagged)),
          started_at: min(s.inserted_at),
          ended_at: max(s.inserted_at)
        }

    query =
      if Keyword.get(opts, :flagged_only, false) do
        from s in query, having: max(fragment("CASE WHEN ? THEN 1 ELSE 0 END", s.flagged)) == 1
      else
        query
      end

    query |> Repo.all() |> Enum.map(&%{&1 | flagged: &1.flagged == 1})
  end

  ## Config

  # Capture stays off unless deliberately enabled: snapshots embed user
  # metadata and KV, so turning it on is a privacy decision and the retention
  # window (see `GameServer.Retention`) is what bounds it.
  use GameServer.Settings.Provider,
    app: :game_server_core,
    group: :lobby_snapshots,
    label: "Lobby snapshots"

  setting(:enabled, :boolean,
    default: false,
    doc: "Record a durable per-run snapshot of lobby state, browsable at /admin/lobby_snapshots."
  )

  setting(:user_kv_keys, :list,
    default: [],
    doc:
      "User-scoped KV keys to capture. Empty captures none — the widest exposure in a snapshot."
  )

  setting(:max_kv_entries, :integer,
    default: 200,
    doc: "Cap on KV entries captured per snapshot."
  )

  @doc """
  The resolved value of a config key, for tests and diagnostics.

  Exposed so resolution can be asserted against the real code path rather than
  a copy of it.
  """
  @spec resolved_config(atom(), term()) :: term()
  def resolved_config(key, _default \\ nil) when is_atom(key), do: config(key)

  defp config(key), do: GameServer.Settings.get(__MODULE__, key)
  defp config(key, _default), do: config(key)
end
