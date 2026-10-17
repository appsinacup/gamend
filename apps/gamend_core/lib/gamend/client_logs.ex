defmodule Gamend.ClientLogs do
  @moduledoc """
  Logs from the game client, put where the server's own logs already are.

  A client uploads batches of entries; each one is re-emitted through `Logger`
  and leaves by whatever path the host already uses — stdout, the rotating file
  (`GamendWeb.FileLogHandler`), the admin ring buffer, and from there whatever
  aggregator scrapes them. `client_sessions` holds one row per run as the index
  over that: who, which build, which lobbies, how many errors.

  ## Why not a table of log lines

  Because the interesting question is never "show me this client's logs" — it
  is "show me what the client and the server were both doing at 14:03". Putting
  the lines in a second store means answering that with a join across two
  systems, forever. Putting them in the same stream means answering it with one
  query, and a log aggregator indexes and compresses them for a fraction of
  what a Postgres row each would cost.

  So the only durable rows here are per *session*, which is a few per player
  per day rather than a few hundred.

  ## The correlation key

  Every emitted line carries a logfmt prefix naming its session, user, lobby
  and screen:

      [client] session=0f1e… user=9ab3… level=info cat=game lobby=77c1… screen=race seq=42 | Game starting

  In the *message*, deliberately, not only in `Logger` metadata. Metadata reaches
  stdout only for the keys a host lists in its `:default_formatter` config, and
  a feature that silently stops correlating because a host never copied a config
  line is worse than a slightly longer line. Metadata is set as well, for the
  structured filters on the admin page.

  A grep for `session=<id>` therefore returns client *and* server lines
  interleaved, in any log store, with no configuration. The same id reaches
  server-side lines through `GamendWeb.Plugs.ClientSession`, which stamps it
  from the `x-gamend-session` header.

  ## Levels

  Client levels are carried as `level=` in the line, not as the `Logger` level.
  The two mean different things: the `Logger` level governs how chatty the
  *server* is, and hosts routinely purge `debug` at compile time in production
  (`compile_time_purge_matching`). Routing a client `debug` entry through
  `Logger.debug/1` would mean asking a client for verbose capture and then
  dropping it on arrival, in exactly the builds where it is hardest to
  reproduce. Client `warn` and `error` map to their `Logger` equivalents so
  existing alerting sees them; everything below maps to `Logger.info`.

  One consequence worth knowing before wondering where the logs went: a host
  running `Logger` at `:warning` drops every client line below `warn`, because
  the primary level filter runs before any handler. Collecting client `info`
  requires the server's own level to be `:info` or lower. The admin page says so
  rather than showing an empty list — see `logger_level_blocks_collection?/0`.

  Disabled by default; see `enabled?/0`.
  """

  import Ecto.Query

  require Logger

  alias Gamend.ClientLogs.Session
  alias Gamend.ClientLogs.SessionLobby
  alias Gamend.Repo

  @levels ~w(trace debug info warn error)

  # Caps. A client that misbehaves — or is hostile — must not be able to turn
  # one request into unbounded work or an unbounded log bill.
  @max_entries_per_batch 200
  @max_message_bytes 2_000
  @max_category_bytes 64
  @max_screen_bytes 64

  @doc """
  Whether ingest is currently accepting batches.

  Checked before any work, so the endpoint costs one config read when off.
  """
  @spec enabled?() :: boolean()
  def enabled?, do: config(:enabled) == true

  @doc """
  Whether the host's own `Logger` level is discarding client entries before
  they reach any handler.

  Collection is configured in two places that know nothing about each other —
  `level` here, and the server's `Logger` level — and the failure mode when
  they disagree is an empty page rather than an error. Worth answering rather
  than leaving to be rediscovered.
  """
  @spec logger_level_blocks_collection?() :: boolean()
  def logger_level_blocks_collection? do
    enabled?() and config(:level) in ["trace", "debug", "info"] and
      Logger.compare_levels(Logger.level(), :info) == :gt
  end

  @doc """
  The capture policy a client should apply, served to it at startup.

  Clients gate their own uploads on this: the floor level, plus per-category
  overrides so a noisy category can be silenced (or a quiet one opened up)
  without shipping a build. `"off"` for a category drops it entirely.

      %{enabled: true, level: "info", categories: %{"perf" => "off"}, batch_max: 200}
  """
  @spec capture_policy() :: map()
  def capture_policy do
    %{
      enabled: enabled?(),
      level: config(:level),
      categories: category_levels(),
      batch_max: @max_entries_per_batch,
      message_max_bytes: @max_message_bytes
    }
  end

  # Configured as `perf:off,network:warn` — a flat list, because a setting has
  # to survive a round trip through an environment variable and a nested map
  # does not.
  defp category_levels do
    config(:category_levels)
    |> List.wrap()
    |> Enum.flat_map(fn pair ->
      case String.split(pair, ":", parts: 2) do
        [category, level] ->
          category = String.trim(category)
          level = level |> String.trim() |> String.downcase()
          if category != "" and level in ["off" | @levels], do: [{category, level}], else: []

        _ ->
          []
      end
    end)
    |> Map.new()
  end

  @doc """
  Accept one batch from a client.

  `attrs` is the decoded request body: a `"session"` map describing the run and
  an `"entries"` list. `opts` carries what the server knows and the client does
  not get to assert — `:user_id` from the bearer token.

  Returns `{:ok, summary}`, or `{:error, reason}` where reason is one of
  `:disabled`, `:invalid`, or `:forbidden` (the session id belongs to someone
  else — see `bind_owner/2`).

  Emitting never fails the caller: an entry that cannot be normalized is
  dropped and counted, because a malformed line in a diagnostic batch is not
  worth a 500 to a client that is probably already having a bad time.
  """
  @spec ingest(map(), keyword()) :: {:ok, map()} | {:error, atom()}
  def ingest(attrs, opts \\ []) when is_map(attrs) and is_list(opts) do
    if enabled?() do
      do_ingest(attrs, opts)
    else
      {:error, :disabled}
    end
  end

  defp do_ingest(attrs, opts) do
    user_id = Keyword.get(opts, :user_id)
    session_attrs = Map.get(attrs, "session", %{})
    raw_entries = Map.get(attrs, "entries", [])

    with {:ok, session_id} <- session_id(session_attrs),
         {:ok, session} <- upsert_session(session_id, session_attrs, user_id) do
      entries =
        raw_entries
        |> Enum.take(@max_entries_per_batch)
        |> Enum.map(&normalize_entry/1)
        |> Enum.reject(&is_nil/1)

      Enum.each(entries, &emit(&1, session))

      {:ok, record_batch(session, entries, length(raw_entries))}
    end
  end

  # ── Session ────────────────────────────────────────────────────────────────

  defp session_id(attrs) do
    case Map.get(attrs, "client_session_id") do
      id when is_binary(id) and byte_size(id) >= 8 and byte_size(id) <= 128 -> {:ok, id}
      _ -> {:error, :invalid}
    end
  end

  defp upsert_session(session_id, attrs, user_id) do
    case Repo.get_by(Session, client_session_id: session_id) do
      nil -> create_session(session_id, attrs, user_id)
      %Session{} = session -> bind_owner(session, user_id)
    end
  end

  defp create_session(session_id, attrs, user_id) do
    now = DateTime.utc_now()

    params = %{
      client_session_id: session_id,
      user_id: user_id,
      device_id: string(attrs, "device_id"),
      platform: platform(attrs),
      app_version: string(attrs, "app_version"),
      build: build(attrs),
      locale: string(attrs, "locale"),
      started_at: started_at(attrs, now),
      last_seen_at: now,
      meta: meta(attrs)
    }

    %Session{}
    |> Session.changeset(params)
    |> Repo.insert()
    |> case do
      {:ok, session} ->
        {:ok, session}

      {:error, %Ecto.Changeset{errors: errors}} ->
        # Another node inserted the same session between our lookup and this
        # write. Not an error — re-read and carry on through the owner check.
        if Keyword.has_key?(errors, :client_session_id) do
          case Repo.get_by(Session, client_session_id: session_id) do
            nil -> {:error, :invalid}
            session -> bind_owner(session, user_id)
          end
        else
          {:error, :invalid}
        end
    end
  end

  # A session is claimable once. The id is generated by the client, so without
  # this anyone who learns another player's session id could write into their
  # timeline — which is worse than useless, because the whole point of the
  # feature is that you trust what you read there.
  #
  # An anonymous session that later logs in is the one legitimate ownership
  # change: it is the same run, and dropping the pre-login half would discard
  # exactly the auth logs someone is most likely to be chasing.
  defp bind_owner(%Session{user_id: nil} = session, user_id) when is_binary(user_id) do
    session
    |> Ecto.Changeset.change(user_id: user_id)
    |> Repo.update()
    |> case do
      {:ok, session} -> {:ok, session}
      {:error, _} -> {:ok, session}
    end
  end

  defp bind_owner(%Session{user_id: owner} = session, user_id)
       when is_nil(user_id) or owner == user_id,
       do: {:ok, session}

  defp bind_owner(%Session{}, _user_id), do: {:error, :forbidden}

  # ── Entries ────────────────────────────────────────────────────────────────

  defp normalize_entry(entry) when is_map(entry) do
    message = entry |> Map.get("message") |> to_message()

    if message == "" do
      nil
    else
      %{
        seq: integer(entry, "seq"),
        at: at(entry),
        level: level(entry),
        category: entry |> Map.get("category") |> clamp(@max_category_bytes, "general"),
        screen: entry |> Map.get("screen") |> clamp(@max_screen_bytes, ""),
        lobby_id: entry |> Map.get("lobby_id") |> clamp(128, ""),
        message: message
      }
    end
  end

  defp normalize_entry(_), do: nil

  defp to_message(message) when is_binary(message) do
    message
    |> truncate_bytes(@max_message_bytes)
    |> single_line()
    |> strip_control_chars()
    |> scrub()
    |> String.trim()
  end

  defp to_message(_), do: ""

  # The cap is named in bytes, so measure bytes. `String.slice/3` counts
  # graphemes, so a message of 4-byte codepoints was 8 KB against a 2 KB
  # limit — four times the intended log volume per entry.
  defp truncate_bytes(value, max) do
    if byte_size(value) <= max do
      value
    else
      # Cut on a codepoint boundary so the result stays valid UTF-8.
      value |> binary_part(0, max) |> String.chunk(:valid) |> List.first() || ""
    end
  end

  # ANSI escapes and other C0/C1 controls, out.
  #
  # `single_line/1` removed `\r` and `\n`, but `\e` is not whitespace and
  # survived into the rotating file and `journalctl` — where an escape sequence
  # can move the cursor, clear the screen, or overwrite the line above, letting
  # a client forge what looks like a preceding server line for whoever reads it.
  defp strip_control_chars(value) do
    String.replace(value, ~r/[\x00-\x08\x0B-\x1F\x7F-\x9F]/u, "")
  end

  # One entry, one line. Everything downstream — `grep session=`, the rotating
  # file, a line-oriented aggregator — reads a newline as the start of a new
  # event, and that "event" would carry no `[client] session=` prefix: a client
  # could write what looks like a server line. Folded onto one line with the
  # indentation collapsed, a stack trace still reads.
  defp single_line(value), do: String.replace(value, ~r/\s*[\r\n]+\s*/, " ")

  # Client messages are written at ~100 call sites by people not thinking about
  # where the string ends up. Something will eventually interpolate a token into
  # one; redact the shapes that are unmistakable rather than pretend it cannot
  # happen. Not a substitute for not logging secrets — a backstop for when
  # someone does.
  @jwt ~r/\beyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\b/
  @assigned ~r/\b(token|password|passwd|secret|api_key|apikey|authorization)\b(\s*[=:]\s*)("?)[^\s",}]+\3/i

  defp scrub(message) do
    message
    |> String.replace(@jwt, "[redacted-jwt]")
    |> String.replace(@assigned, "\\1\\2[redacted]")
  end

  defp level(entry) do
    case Map.get(entry, "level") do
      level when level in @levels -> level
      _ -> "info"
    end
  end

  # The client's clock, kept as sent. It is not trustworthy — phone clocks
  # drift and users change them — which is exactly why it is worth keeping
  # next to the server's own receive time rather than being normalized away.
  defp at(entry) do
    case Map.get(entry, "at") do
      unix when is_number(unix) and unix > 0 ->
        case DateTime.from_unix(round(unix * 1000), :millisecond) do
          {:ok, dt} -> dt
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp emit(entry, %Session{} = session) do
    metadata = [
      source: :client,
      client_session: session.client_session_id,
      client_user_id: session.user_id,
      client_level: entry.level,
      client_category: entry.category,
      client_lobby_id: entry.lobby_id,
      client_screen: entry.screen,
      client_seq: entry.seq,
      client_at: entry.at,
      client_platform: session.platform,
      client_app_version: session.app_version
    ]

    Logger.log(logger_level(entry.level), fn -> line(entry, session) end, metadata)
  end

  # See the "Levels" section of the moduledoc: only warn/error map through, so
  # a host purging `debug` in production does not silently discard the verbose
  # capture it just asked a client for.
  defp logger_level("error"), do: :error
  defp logger_level("warn"), do: :warning
  defp logger_level(_), do: :info

  defp line(entry, %Session{} = session) do
    [
      "[client] session=",
      session.client_session_id,
      field("user", session.user_id),
      " level=",
      entry.level,
      " cat=",
      entry.category,
      field("lobby", entry.lobby_id),
      field("screen", entry.screen),
      field("seq", entry.seq),
      " | ",
      entry.message
    ]
  end

  defp field(_key, nil), do: []
  defp field(_key, ""), do: []
  defp field(key, value), do: [" ", key, "=", to_string(value)]

  # ── Counters ───────────────────────────────────────────────────────────────

  # Counters move in the database, not read-modify-write in Elixir: two nodes
  # can be flushing batches for the same session at once and a read-modify-write
  # would lose one of them.
  #
  # Split across statements rather than fused with `GREATEST`/array fragments,
  # because those are Postgres-only and the engine's default adapter is SQLite.
  defp record_batch(%Session{} = session, entries, received_count) do
    now = DateTime.utc_now()
    levels = Enum.frequencies_by(entries, & &1.level)
    warns = Map.get(levels, "warn", 0)
    errors = Map.get(levels, "error", 0)
    accepted = length(entries)

    seqs = entries |> Enum.map(& &1.seq) |> Enum.reject(&is_nil/1)
    max_seq = Enum.max(seqs, fn -> 0 end)
    dropped = dropped(session, seqs) + (received_count - accepted)

    # A session that logged an error is worth keeping past the ordinary
    # retention window, so flagging is a side effect of the counts rather than
    # something an operator has to remember to do.
    set = [last_seen_at: now, updated_at: now]
    set = if errors > 0, do: [{:flagged, true} | set], else: set

    {_count, _} =
      Session
      |> where([s], s.id == ^session.id)
      |> Repo.update_all(
        inc: [
          entry_count: accepted,
          warn_count: warns,
          error_count: errors,
          dropped_count: dropped
        ],
        set: set
      )

    advance_max_seq(session, max_seq)
    record_lobbies(session, entries)

    %{
      accepted: accepted,
      dropped: dropped,
      errors: errors,
      client_session_id: session.client_session_id
    }
  end

  # Forward only. The `where` is what makes this safe against a concurrent
  # batch: an out-of-order flush carrying a lower sequence matches no row and
  # silently does nothing, instead of winding the high-water mark backwards and
  # making the next batch look like it dropped entries.
  defp advance_max_seq(_session, max_seq) when max_seq <= 0, do: :ok

  defp advance_max_seq(%Session{} = session, max_seq) do
    {_count, _} =
      Session
      |> where([s], s.id == ^session.id and s.max_seq < ^max_seq)
      |> Repo.update_all(set: [max_seq: max_seq])

    :ok
  end

  defp record_lobbies(%Session{} = session, entries) do
    now = DateTime.utc_now()

    rows =
      entries
      |> Enum.map(& &1.lobby_id)
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.uniq()
      |> Enum.map(
        &%{
          id: Gamend.UUIDv7.generate(),
          client_session_id: session.client_session_id,
          lobby_id: &1,
          inserted_at: now
        }
      )

    if rows != [] do
      Repo.insert_all(SessionLobby, rows, on_conflict: :nothing)
    end

    :ok
  end

  # A gap between the highest sequence we have seen and the lowest in this
  # batch means the client's ring buffer overran, or a batch never arrived.
  # Without this a lossy session is indistinguishable from a quiet one, and
  # "there is nothing in the logs" is the wrong conclusion to draw from it.
  defp dropped(%Session{max_seq: max_seq}, seqs) do
    case Enum.min(seqs, fn -> nil end) do
      nil -> 0
      first when first > max_seq + 1 -> first - max_seq - 1
      _ -> 0
    end
  end

  # ── Reading ────────────────────────────────────────────────────────────────

  @doc """
  Sessions, newest activity first.

  Options: `:user_id`, `:platform`, `:build`, `:app_version`, `:lobby_id`,
  `:errors_only`, `:query` (matches session id or device id), `:since`,
  `:until`, `:page`, `:page_size`.
  """
  @spec list_sessions(keyword()) :: [Session.t()]
  def list_sessions(opts \\ []) do
    Session
    |> filter_sessions(opts)
    |> order_by([s], desc: s.last_seen_at)
    |> Gamend.Query.page(opts)
    |> preload(:user)
    |> Repo.all()
  end

  @doc "How many sessions match `opts`, for the pager."
  @spec count_sessions(keyword()) :: non_neg_integer()
  def count_sessions(opts \\ []) do
    Session
    |> filter_sessions(opts)
    |> select([s], count(s.id))
    |> Repo.one()
    |> Kernel.||(0)
  end

  @doc "One session by its client-generated id."
  @spec get_session(String.t()) :: Session.t() | nil
  def get_session(client_session_id) when is_binary(client_session_id) do
    Session
    |> Repo.get_by(client_session_id: client_session_id)
    |> Repo.preload(:user)
  end

  @doc """
  Lobbies this session was in, oldest first.

  The link back to the server's own view of the same runs: each id addresses a
  `lobby_snapshots` timeline, so a client-side symptom and the server-side
  state that produced it are one click apart.
  """
  @spec session_lobby_ids(String.t()) :: [String.t()]
  def session_lobby_ids(client_session_id) when is_binary(client_session_id) do
    SessionLobby
    |> where([l], l.client_session_id == ^client_session_id)
    |> order_by([l], asc: l.inserted_at)
    |> select([l], l.lobby_id)
    |> Repo.all()
  end

  @doc """
  Mark a session as worth keeping (or not), exempting it from the ordinary
  retention window.
  """
  @spec set_flagged(String.t(), boolean()) :: :ok
  def set_flagged(client_session_id, flagged?) when is_binary(client_session_id) do
    {_count, _} =
      Session
      |> where([s], s.client_session_id == ^client_session_id)
      |> Repo.update_all(set: [flagged: flagged?, updated_at: DateTime.utc_now()])

    :ok
  end

  defp filter_sessions(query, opts) do
    Enum.reduce(opts, query, fn
      {:user_id, id}, q when is_binary(id) -> where(q, [s], s.user_id == ^id)
      {:platform, p}, q when is_binary(p) and p != "" -> where(q, [s], s.platform == ^p)
      {:build, b}, q when is_binary(b) and b != "" -> where(q, [s], s.build == ^b)
      {:app_version, v}, q when is_binary(v) and v != "" -> where(q, [s], s.app_version == ^v)
      {:lobby_id, id}, q when is_binary(id) and id != "" -> in_lobby(q, id)
      {:errors_only, true}, q -> where(q, [s], s.error_count > 0)
      {:flagged_only, true}, q -> where(q, [s], s.flagged == true)
      {:since, %DateTime{} = t}, q -> where(q, [s], s.last_seen_at >= ^t)
      {:until, %DateTime{} = t}, q -> where(q, [s], s.last_seen_at <= ^t)
      {:query, term}, q when is_binary(term) and term != "" -> search(q, term)
      _, q -> q
    end)
  end

  defp in_lobby(query, lobby_id) do
    in_lobby =
      from(l in SessionLobby, where: l.lobby_id == ^lobby_id, select: l.client_session_id)

    where(query, [s], s.client_session_id in subquery(in_lobby))
  end

  # `LOWER(...) LIKE` rather than `ilike`: SQLite has no `ILIKE`, and its own
  # `LIKE` is ASCII-case-insensitive while Postgres's is not — so neither
  # operator means the same thing on both adapters, and lowering both sides is
  # the only form that does.
  defp search(query, term) do
    like = "%#{term |> String.replace(~r/[%_\\]/, "") |> String.downcase()}%"

    where(
      query,
      [s],
      like(fragment("LOWER(?)", s.client_session_id), ^like) or
        like(fragment("LOWER(?)", s.device_id), ^like)
    )
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  defp string(attrs, key) do
    case Map.get(attrs, key) do
      value when is_binary(value) -> String.slice(value, 0, 128)
      _ -> ""
    end
  end

  defp platform(attrs) do
    value = attrs |> string("platform") |> String.downcase()
    if value in Session.platforms(), do: value, else: "unknown"
  end

  defp build(attrs) do
    value = attrs |> string("build") |> String.downcase()
    if value in Session.builds(), do: value, else: "release"
  end

  defp started_at(attrs, now) do
    case Map.get(attrs, "started_at") do
      unix when is_number(unix) and unix > 0 ->
        case DateTime.from_unix(round(unix * 1000), :millisecond) do
          {:ok, dt} -> dt
          _ -> now
        end

      _ ->
        now
    end
  end

  # Free-form device facts (model, GPU, screen size). Capped in width and
  # depth so a client cannot use it as unbounded storage.
  defp meta(attrs) do
    case Map.get(attrs, "meta") do
      map when is_map(map) ->
        map
        |> Enum.take(32)
        |> Map.new(fn {k, v} -> {to_string(k) |> String.slice(0, 64), scalar(v)} end)

      _ ->
        %{}
    end
  end

  defp scalar(value) when is_binary(value), do: String.slice(value, 0, 256)
  defp scalar(value) when is_number(value) or is_boolean(value), do: value
  defp scalar(value), do: value |> inspect() |> String.slice(0, 256)

  defp integer(attrs, key) do
    case Map.get(attrs, key) do
      n when is_integer(n) -> n
      _ -> nil
    end
  end

  defp clamp(value, max, _default) when is_binary(value),
    do: value |> String.slice(0, max) |> single_line()

  defp clamp(_value, _max, default), do: default

  # ── Settings ───────────────────────────────────────────────────────────────

  use Gamend.Settings.Provider,
    app: :gamend_core,
    group: :client_logs,
    label: "Client logs"

  setting(:enabled, :boolean,
    default: false,
    doc:
      "Accept log batches from game clients and re-emit them into the server's own logs, indexed at /admin/logs."
  )

  setting(:level, :string,
    default: "info",
    doc:
      "Lowest client level to collect: trace, debug, info, warn or error. Clients gate their own uploads on this."
  )

  setting(:category_levels, :list,
    default: [],
    doc:
      "Per-category level overrides as category:level pairs, e.g. perf:off,network:warn. Overrides the floor for that category only; off drops it entirely."
  )

  setting(:retention_days, :integer,
    default: 14,
    doc: "Delete client sessions after N days of inactivity. 0 keeps them forever."
  )

  setting(:retention_flagged_days, :integer,
    default: 90,
    doc: "Retention for sessions marked flagged (any session that logged an error)."
  )

  @doc """
  The resolved value of a config key, for tests and diagnostics.

  Exposed so resolution can be asserted against the real code path rather than
  a copy of it.
  """
  @spec resolved_config(atom()) :: term()
  def resolved_config(key) when is_atom(key), do: config(key)

  defp config(key), do: Gamend.Settings.get(__MODULE__, key)
end
