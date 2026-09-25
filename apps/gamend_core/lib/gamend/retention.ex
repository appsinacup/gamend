defmodule Gamend.Retention do
  @moduledoc """
  Periodically prunes old rows from unbounded tables.

  Retention is configured per table via `Gamend.Settings` (group `:retention`,
  env vars `GAMEND_RETENTION_*`); `0` or unset keeps data forever:

  - `GAMEND_RETENTION_CHAT_MESSAGES_DAYS` — `chat_messages` older than N days
  - `GAMEND_RETENTION_NOTIFICATIONS_DAYS` — `notifications` older than N days
  - `GAMEND_RETENTION_PAYMENT_EVENTS_DAYS` — payment provider webhook events older
    than N days (purchases/entitlements are never pruned)
  - `GAMEND_RETENTION_LOBBY_SNAPSHOTS_DAYS` — lobby snapshots, events and their
    content blobs. Unlike the others this defaults to 30 rather than "keep
    forever": snapshots hold user metadata, and the window is what bounds that
    exposure. Runs flagged anomalous keep
    `GAMEND_RETENTION_LOBBY_SNAPSHOTS_FLAGGED_DAYS` instead (default 90).
  - Client log sessions (`Gamend.ClientLogs`), on their own settings rather
    than a `GAMEND_RETENTION_*` var: `retention_days` (14) and
    `retention_flagged_days` (90), keyed off `last_seen_at`. This prunes the
    index over client logs, not the lines — those live in the host's log store
    on its own retention.
  - `GAMEND_RETENTION_PUSH_TOKENS_DAYS` — push tokens untouched (registered, used,
    or disabled) for N days. Defaults to 270 — Google's stale-token guidance
    — so the table tracks live devices, not install history.
  - `GAMEND_RETENTION_INVITES_DAYS` — resolved group/party invites and join requests,
    N days after resolution (default 30). Pending rows are never pruned.
  - `GAMEND_RETENTION_MATCHMAKING_TICKETS_HOURS` — tickets older than N hours
    (default 24), in any status.
  - `GAMEND_RETENTION_TOURNAMENTS_DAYS` / `GAMEND_RETENTION_LEDGER_DAYS` — finished
    tournaments and the wallet/inventory ledgers. Both default to `0`: they
    are history an operator may be required to keep.
  - `GAMEND_RETENTION_ACTIVITY_DAYS` — `user_activity_days` rows (one per user per
    UTC day seen, behind DAU and D1/D7/D30) older than N days. Defaults to
    `0`; the table grows by at most one row per active user per day, and a
    window shorter than the analytics cohort span (60 days) blanks the
    retention numbers.
  - `GAMEND_RETENTION_ANONYMOUS_USERS_DAYS` (90) — device-only accounts inactive
    for N days. `GAMEND_RETENTION_UNCONFIRMED_USERS_DAYS` (30) — email accounts
    whose address was never confirmed, inactive for N days.
  - `GAMEND_RETENTION_ABANDONED_LOBBY_MINUTES` (15) — lobbies nobody has been seen in
    for N minutes, in minutes rather than days. The same window releases a lobby
    seat held by a long-offline player. A party everyone abandoned is disbanded
    on its own window, `GAMEND_RETENTION_ABANDONED_PARTY_MINUTES` (15).

  Expired IP bans, OAuth sessions older than a day, user tokens past their own
  context's validity, personal API tokens that can no longer authenticate
  (expired, or older than their owner's last credential change), login
  lockouts whose window and lock have run out, accounts past the deletion date
  their owner's request set (`GAMEND_AUTH_DELETION_GRACE_DAYS`), and stored
  avatars whose owner no longer exists are always
  removed (independent of the env vars above). Deletes are idempotent, so
  running on several instances at once is harmless; each class is batched and
  failure-isolated, and emits `[:gamend, :retention, :pruned]` telemetry with
  its count.

  ## Classes a host or plugin adds

  A host application and a plugin have tables of their own, and the rule that
  an unbounded table needs a retention class applies to them too. Register one
  and it runs, is failure-isolated, and emits telemetry exactly like core's:

      Gamend.Retention.register_class(:forge_builds, &Forge.Builds.prune/0)

  The function takes no arguments and answers how many rows it deleted.
  Registering the same name twice replaces the first, so a module can call this
  at every boot without accumulating duplicates.
  """

  use GenServer

  import Ecto.Query

  require Logger

  alias Gamend.Accounts
  alias Gamend.Accounts.{ApiTokens, LoginLockouts, User, UserToken}
  alias Gamend.ClientLogs
  alias Gamend.ClientLogs.Session, as: ClientSession
  alias Gamend.ClientLogs.SessionLobby
  alias Gamend.Lobbies
  alias Gamend.Lobbies.Lobby
  alias Gamend.LobbySnapshots.{Blob, Event, Snapshot}
  alias Gamend.Parties
  alias Gamend.Parties.Party
  alias Gamend.Payments.{Entitlement, Purchase}
  alias Gamend.Repo
  alias Gamend.Storage

  # First run shortly after boot, then every `interval_hours`.
  @initial_delay_ms :timer.minutes(5)

  # The classes that free live game state: a seat, a lobby, a party. Their
  # windows are minutes long, so they also run on a short cycle of their own
  # (`live_interval_seconds`). Swept only with everything else, every six hours,
  # a 15-minute window let a disconnected player sit on `already_in_lobby` and
  # a dead lobby stay listed for up to six hours longer than it said.
  @live_classes [
    :offline_lobby_memberships,
    :offline_party_memberships,
    :abandoned_parties,
    :lobbies
  ]

  # OAuth sessions are ephemeral handshake state (seconds-to-minutes of use);
  # always prune stale rows so the table can't grow unbounded.
  @oauth_session_ttl_days 1

  # Rows deleted per statement come from `batch_size`. The sweep runs against a
  # live database: on SQLite one large DELETE holds the write lock long enough
  # to stall gameplay writes, and on Postgres it bloats a single transaction.

  # How long a stored avatar is left alone before "its owner does not exist" is
  # read as orphaned rather than as a write still in progress.
  @orphan_avatar_grace_minutes 60

  # Ceiling on how much of the `avatars/` prefix one sweep walks (`batch_size` per
  # page). A run that hits it says so and resumes from the start at the next sweep.
  @orphan_avatar_max_pages 20

  # Invites and join requests are only garbage once they stop being actionable.
  @resolved_statuses ~w(accepted declined rejected cancelled expired)

  @invite_schemas [
    Gamend.Groups.GroupInvite,
    Gamend.Groups.GroupJoinRequest,
    Gamend.Parties.PartyInvite
  ]

  @ledger_schemas [Gamend.Economy.LedgerEntry, Gamend.Inventory.LedgerEntry]

  # Tournaments whose bracket can no longer change.
  @finished_tournament_states ~w(finished cancelled)

  @never_run %{last_run_at: nil, duration_ms: nil, results: %{}}

  # A manual sweep deletes in batches across every class; the default 5s call
  # timeout would give up on a backlog it is perfectly capable of clearing.
  @run_now_timeout_ms :timer.minutes(5)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Process.send_after(self(), :prune, @initial_delay_ms)
    schedule_live()
    {:ok, @never_run}
  end

  @doc """
  What the last sweep did, for the admin page. Falls back to "never run" when
  the sweeper is not supervised (tests, or an instance with it disabled).
  """
  @spec status() :: %{
          last_run_at: DateTime.t() | nil,
          duration_ms: non_neg_integer() | nil,
          results: %{atom() => non_neg_integer()}
        }
  def status do
    GenServer.call(__MODULE__, :status)
  catch
    :exit, _reason -> @never_run
  end

  @doc """
  Sweeps now instead of waiting for the next cycle, and records the run like a
  scheduled one. Runs inside the GenServer so a manual run and the timer can
  never overlap.
  """
  @spec run_now() :: %{atom() => non_neg_integer()}
  def run_now, do: GenServer.call(__MODULE__, :prune, @run_now_timeout_ms)

  @impl true
  def handle_call(:status, _from, state), do: {:reply, state, state}

  def handle_call(:prune, _from, _state) do
    state = sweep()
    {:reply, state.results, state}
  end

  @impl true
  def handle_info(:prune, _state) do
    state = sweep()
    Process.send_after(self(), :prune, sweep_interval_ms())
    {:noreply, state}
  end

  # Not recorded as the last run: `status/0` describes a full sweep, and this
  # one touches four classes. Each class still emits its own telemetry.
  def handle_info(:prune_live, state) do
    _ = prune_live()
    schedule_live()
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @doc false
  # Milliseconds between full sweeps: `interval_hours`, at least one.
  @spec sweep_interval_ms() :: pos_integer()
  def sweep_interval_ms, do: :timer.hours(max(config(:interval_hours), 1))

  # 0 folds the live classes back into the full sweep only.
  defp schedule_live do
    case config(:live_interval_seconds) do
      seconds when is_integer(seconds) and seconds > 0 ->
        Process.send_after(self(), :prune_live, :timer.seconds(seconds))

      _off ->
        :ok
    end
  end

  defp sweep do
    started = System.monotonic_time(:millisecond)
    results = prune_all()

    %{
      last_run_at: DateTime.utc_now(:second),
      duration_ms: System.monotonic_time(:millisecond) - started,
      results: results
    }
  end

  @doc """
  Register a pruning class owned by a host application or a plugin.

  Core's own classes are a fixed list in `prune_all/0`, which left a host with
  no way to bound its own tables: `CONTRIBUTING.md` requires every unbounded
  table to have a class or a stated reason it is bounded, and a fork could not
  comply. Registering by name rather than appending means a module can call
  this on every boot — the second registration replaces the first instead of
  pruning twice.
  """
  @spec register_class(atom(), (-> non_neg_integer())) :: :ok
  def register_class(class, fun) when is_atom(class) and is_function(fun, 0) do
    Application.put_env(:gamend_core, __MODULE__, put_class(class, fun))
  end

  @doc "Undoes `register_class/2`."
  @spec unregister_class(atom()) :: :ok
  def unregister_class(class) when is_atom(class) do
    Application.put_env(:gamend_core, __MODULE__, drop_class(class))
  end

  @doc "Classes registered on top of core's own."
  @spec registered_classes() :: %{atom() => (-> non_neg_integer())}
  def registered_classes do
    :gamend_core |> Application.get_env(__MODULE__, []) |> Keyword.get(:classes, %{})
  end

  defp put_class(class, fun) do
    config = Application.get_env(:gamend_core, __MODULE__, [])

    Keyword.put(config, :classes, Map.put(registered_classes(), class, fun))
  end

  defp drop_class(class) do
    config = Application.get_env(:gamend_core, __MODULE__, [])

    Keyword.put(config, :classes, Map.delete(registered_classes(), class))
  end

  @doc """
  Runs all configured pruning steps once. Returns a map of deleted row
  counts per table.
  """
  @spec prune_all() :: %{atom() => non_neg_integer()}
  def prune_all do
    results =
      core_classes()
      # A host's classes cannot silently shadow one of core's: a name collision
      # would drop core's pruning and leave the table growing, which is the
      # failure this module exists to prevent.
      |> Map.merge(Map.drop(registered_classes(), Map.keys(core_classes())))
      |> Map.new(&run_class/1)

    pruned = results |> Map.values() |> Enum.sum()

    if pruned > 0 do
      Logger.info("retention pruned rows: #{inspect(results)}")
    end

    results
  end

  @doc """
  Runs only the classes that free live game state: offline lobby and party
  seats, abandoned parties, abandoned lobbies. What the short cycle
  (`live_interval_seconds`) runs between full sweeps.
  """
  @spec prune_live() :: %{atom() => non_neg_integer()}
  def prune_live do
    results = Map.new(Map.take(core_classes(), @live_classes), &run_class/1)
    pruned = results |> Map.values() |> Enum.sum()

    if pruned > 0 do
      Logger.info("retention released live state: #{inspect(results)}")
    end

    results
  end

  # Core's own classes. Separate from `prune_all/0` so a registered class can be
  # checked against them by name.
  defp core_classes do
    %{
      chat_messages: fn ->
        prune_older_than(Gamend.Chat.Message, config(:chat_messages_days))
      end,
      notifications: fn ->
        prune_older_than(Gamend.Notifications.Notification, config(:notifications_days))
      end,
      payment_events: fn ->
        prune_older_than(Gamend.Payments.ProviderEvent, config(:payment_events_days))
      end,
      oauth_sessions: fn ->
        prune_older_than(Gamend.OAuthSession, @oauth_session_ttl_days)
      end,
      expired_ip_bans: &prune_expired_ip_bans/0,
      expired_user_tokens: &prune_expired_user_tokens/0,
      login_lockouts: fn -> delete_in_batches(LoginLockouts.expired_query()) end,
      scheduled_deletions: &delete_due_accounts/0,
      dead_api_tokens: &prune_dead_api_tokens/0,
      lobby_snapshots: &prune_lobby_snapshots/0,
      client_sessions: &prune_client_sessions/0,
      lobby_snapshot_blobs: &prune_lobby_snapshot_blobs/0,
      offline_lobby_memberships: &release_offline_lobby_memberships/0,
      offline_party_memberships: &release_offline_party_memberships/0,
      abandoned_parties: &disband_abandoned_parties/0,
      lobbies: &prune_lobbies/0,
      resolved_invites: &prune_resolved_invites/0,
      matchmaking_tickets: &prune_stale_tickets/0,
      finished_tournaments: &prune_finished_tournaments/0,
      ledger_entries: &prune_ledgers/0,
      activity_days: fn ->
        prune_older_than(Gamend.Analytics.ActivityDay, config(:activity_days))
      end,
      quest_periods: &Gamend.Quests.prune_old_periods/0,
      quest_reward_recoveries: &Gamend.Quests.recover_pending_rewards/0,
      push_tokens: &prune_push_tokens/0,
      anonymous_users: &prune_anonymous_users/0,
      unconfirmed_users: &prune_unconfirmed_users/0,
      inactive_user_warnings: &warn_inactive_users/0,
      inactive_users: &prune_inactive_users/0,
      orphaned_avatars: &prune_orphaned_avatars/0
    }
  end

  defp prune_older_than(_schema, days) when not is_integer(days) or days <= 0, do: 0

  defp prune_older_than(schema, days) do
    cutoff = DateTime.add(DateTime.utc_now(:second), -days, :day)

    {count, _} = Repo.delete_all(from(r in schema, where: r.inserted_at < ^cutoff))
    count
  end

  # Lobby snapshots and events expire together, per run rather than per row: a
  # run is flagged if *any* of its snapshots is, and a flagged run keeps its
  # events too. Retention is not just housekeeping here — snapshots hold user
  # metadata and KV, and an account deletion cannot reach data embedded in
  # JSONB, so this window is the mechanism that actually bounds that exposure.
  defp prune_lobby_snapshots do
    days = config(:lobby_snapshots_days)

    if is_integer(days) and days > 0 do
      # Never shorter than the normal window, or flagged runs would expire first
      # — the opposite of the point.
      flagged_days = max(config(:lobby_snapshots_flagged_days), days)

      cutoff = cutoff(days)
      flagged_cutoff = cutoff(flagged_days)

      # Outer window first: it applies to every run, flagged included.
      prune_snapshots_before(flagged_cutoff, :all) +
        prune_snapshots_before(cutoff, :unflagged_runs)
    else
      0
    end
  end

  defp prune_snapshots_before(cutoff, scope) do
    events = from(e in Event, where: e.inserted_at < ^cutoff)
    snapshots = from(s in Snapshot, where: s.inserted_at < ^cutoff)

    {event_count, _} = Repo.delete_all(scope_to_unflagged(events, scope))
    {snapshot_count, _} = Repo.delete_all(scope_to_unflagged(snapshots, scope))

    event_count + snapshot_count
  end

  defp scope_to_unflagged(query, :all), do: query

  defp scope_to_unflagged(query, :unflagged_runs) do
    from r in query,
      as: :row,
      where:
        not exists(
          from s in Snapshot,
            where: s.lobby_id == parent_as(:row).lobby_id and s.flagged,
            select: 1
        )
  end

  # Client log sessions, on the same flagged/unflagged split as lobby snapshots
  # and for the same reason: a session that errored is the one someone will
  # come back to, and it is worth outliving the ordinary window.
  #
  # By `last_seen_at`, not `inserted_at` — a session is a run, and a long one
  # should not start expiring from the moment it began.
  #
  # This prunes the *index*, not the log lines. Those live in the host's log
  # store on its own retention, so a shorter window here loses the ability to
  # find a session, not the ability to read one whose id you already have.
  defp prune_client_sessions do
    days = ClientLogs.resolved_config(:retention_days)

    if is_integer(days) and days > 0 do
      # Never shorter than the normal window, or flagged sessions would expire
      # first — the opposite of the point.
      flagged_days = max(ClientLogs.resolved_config(:retention_flagged_days) || days, days)

      prune_client_sessions_before(cutoff(flagged_days), :all) +
        prune_client_sessions_before(cutoff(days), :unflagged)
    else
      0
    end
  end

  defp prune_client_sessions_before(cutoff, scope) do
    query = from(s in ClientSession, where: s.last_seen_at < ^cutoff)

    query =
      case scope do
        :all -> query
        :unflagged -> from(s in query, where: s.flagged == false)
      end

    # Collect the ids first: the lobby rows are keyed by the client-generated
    # session id, not by a foreign key, so nothing cascades.
    ids = Repo.all(from(s in query, select: s.client_session_id))

    if ids == [] do
      0
    else
      {lobby_count, _} =
        Repo.delete_all(from(l in SessionLobby, where: l.client_session_id in ^ids))

      {session_count, _} =
        Repo.delete_all(from(s in ClientSession, where: s.client_session_id in ^ids))

      lobby_count + session_count
    end
  end

  # Safe to prune by age only because the writer touches last_referenced_at on
  # every reference. The window is the flagged one, so a blob outlives the
  # longest-lived snapshot that could still point at it.
  defp prune_lobby_snapshot_blobs do
    days = config(:lobby_snapshots_days)

    if is_integer(days) and days > 0 do
      cutoff = cutoff(max(config(:lobby_snapshots_flagged_days), days))

      {count, _} = Repo.delete_all(from(b in Blob, where: b.last_referenced_at < ^cutoff))
      count
    else
      0
    end
  end

  defp cutoff(days), do: DateTime.add(DateTime.utc_now(:second), -days, :day)

  # updated_at is the staleness signal: every register/rotate/delivery/disable
  # touches it, so pruning by it removes exactly the tokens nothing has needed
  # for the whole window — disabled rows included.
  defp prune_push_tokens do
    days = config(:push_tokens_days)

    if is_integer(days) and days > 0 do
      cutoff = cutoff(days)

      {count, _} =
        Repo.delete_all(from(t in Gamend.Push.PushToken, where: t.updated_at < ^cutoff))

      count
    else
      0
    end
  end

  # ── Accounts ────────────────────────────────────────────
  #
  # Iterate `Accounts.delete_user/1` rather than `delete_all`: deleting a user
  # disbands their party, hands over their groups, drops their storage prefix
  # and fires `after_user_deleted`, none of which a DELETE reaches.
  #
  # Never swept at any age: admins, and anyone holding a purchase or
  # entitlement.

  defp prune_anonymous_users do
    case config(:anonymous_users_days) do
      days when is_integer(days) and days > 0 ->
        :anonymous |> deletable_users(days) |> delete_users()

      _ ->
        0
    end
  end

  # An address nobody ever proved they own is not an identity worth keeping: a
  # sign-up costs one request, and without this the email tier is the one a
  # bot can fill forever. Keyed off activity, not age, because API sign-up
  # signs the account in unconfirmed — a player who is still playing keeps it.
  defp prune_unconfirmed_users do
    case config(:unconfirmed_users_days) do
      days when is_integer(days) and days > 0 ->
        :unconfirmed |> deletable_users(days) |> delete_users()

      _ ->
        0
    end
  end

  defp prune_inactive_users do
    case config(:inactive_users_days) do
      days when is_integer(days) and days > 0 ->
        :identified
        |> deletable_users(days)
        |> Enum.filter(&warned?/1)
        |> delete_users()

      _ ->
        0
    end
  end

  # Warns accounts approaching the cutoff, not past it, so the notice arrives
  # `inactive_users_warn_days` before the deletion date.
  defp warn_inactive_users do
    days = config(:inactive_users_days)
    warn_days = config(:inactive_users_warn_days)

    if is_integer(days) and days > 0 and is_integer(warn_days) and warn_days > 0 do
      :identified
      |> deletable_users(max(days - warn_days, 0))
      |> Enum.reject(&(is_nil(&1.email) or warned?(&1)))
      |> Enum.count(&enqueue_warning(&1, days))
    else
      0
    end
  end

  # Only a warning issued *after* the user's last activity counts, or someone
  # warned a year ago who has signed in since would be deleted with no fresh
  # notice. Accounts with no address cannot be warned, so the cutoff is it.
  defp warned?(%User{email: nil}), do: true

  defp warned?(%User{} = user) do
    case user.metadata do
      %{"retention_warned_at" => warned_at} when is_binary(warned_at) ->
        case DateTime.from_iso8601(warned_at) do
          {:ok, at, _} -> DateTime.compare(at, last_active_at(user)) == :gt
          _ -> false
        end

      _ ->
        config(:inactive_users_warn_days) in [0, nil]
    end
  end

  defp enqueue_warning(user, days) do
    job = Accounts.InactivityNotifier.new(%{"user_id" => user.id, "delete_after_days" => days})

    match?({:ok, _}, Oban.insert(job))
  end

  defp last_active_at(%User{last_seen_at: nil, inserted_at: inserted_at}), do: inserted_at
  defp last_active_at(%User{last_seen_at: last_seen_at}), do: last_seen_at

  # `last_seen_at` is null for an account that never connected; fall back to
  # `inserted_at`, or a bot that registers and never returns is unreachable.
  defp deletable_users(kind, days) do
    cutoff = cutoff(days)

    from(u in User,
      where: coalesce(u.last_seen_at, u.inserted_at) < ^cutoff,
      where: not u.is_admin,
      where: u.id not in subquery(from(p in Purchase, select: p.user_id)),
      where: u.id not in subquery(from(e in Entitlement, select: e.user_id)),
      where: ^identity_condition(kind),
      limit: ^batch()
    )
    |> Repo.all()
  end

  # One dynamic, not chained `or_where` — that ORs against everything before it
  # and would quietly hand back admins and paying users.
  defp identity_condition(:anonymous) do
    Enum.reduce(User.identity_fields(), dynamic(true), fn field, acc ->
      dynamic([u], ^acc and is_nil(field(u, ^field)))
    end)
  end

  # Email is the only identity, and it was never confirmed. An account that
  # also holds a provider id can be recovered through it, so it is left alone.
  defp identity_condition(:unconfirmed) do
    unconfirmed = dynamic([u], not is_nil(u.email) and is_nil(u.confirmed_at))

    Enum.reduce(User.identity_fields() -- [:email], unconfirmed, fn field, acc ->
      dynamic([u], ^acc and is_nil(field(u, ^field)))
    end)
  end

  defp identity_condition(:identified) do
    Enum.reduce(User.identity_fields(), dynamic(false), fn field, acc ->
      dynamic([u], ^acc or not is_nil(field(u, ^field)))
    end)
  end

  defp delete_users(users) do
    Enum.count(users, fn user -> match?({:ok, _}, Accounts.delete_user(user)) end)
  end

  # Accounts their owners deleted, once `auth.deletion_grace_days` has run out.
  # No exemptions: the owner asked. A batch a sweep, like the other user sweeps.
  defp delete_due_accounts do
    from(u in Accounts.due_deletions_query(), limit: ^batch())
    |> Repo.all()
    |> delete_users()
  end

  # Object storage neither cascades nor takes part in the deletion transaction.
  # `Accounts.delete_user/1` drops the `avatars/<user_id>/` prefix itself, but
  # anything that writes an object for an account that is already gone leaves
  # bytes no code path can ever reach again: an avatar mirror whose download was
  # still in flight when the account was deleted, a deletion that raised before
  # reaching the cleanup, or a row deleted by a build older than that cleanup.
  # Nothing else lists the prefix, so an object that survives once survives
  # forever — and an avatar is personal data, which makes "forever" the wrong
  # answer regardless of how it got there.
  #
  # Only keys whose owner segment parses as a user id are considered, and only
  # after `@orphan_avatar_grace_minutes`, so an object mid-write is never
  # mistaken for an orphan.
  #
  # Walked a page at a time so each pass asks the database about at most `batch_size`
  # ids. Both backends list in key order, so a single page would only ever see
  # the users whose ids sort first and an orphan past it would never be reached;
  # the offset advances by what the page left behind, since deleting from the
  # current page shifts everything after it back.
  defp prune_orphaned_avatars do
    cutoff = DateTime.add(DateTime.utc_now(:second), -@orphan_avatar_grace_minutes, :minute)

    sweep_avatar_page(0, 0, @orphan_avatar_max_pages, cutoff)
  end

  defp sweep_avatar_page(offset, deleted, pages_left, cutoff) do
    page = Storage.list_objects(prefix: "avatars/", offset: offset, limit: batch())
    removed = delete_ownerless_avatars(page, cutoff)

    cond do
      length(page) < batch() ->
        deleted + removed

      pages_left <= 1 ->
        Logger.info("retention stopped scanning avatars at #{offset + length(page)} objects")
        deleted + removed

      true ->
        # What this page left in place is what the next offset has to skip.
        sweep_avatar_page(
          offset + length(page) - removed,
          deleted + removed,
          pages_left - 1,
          cutoff
        )
    end
  end

  defp delete_ownerless_avatars(page, cutoff) do
    candidates =
      page
      |> Enum.filter(&settled?(&1, cutoff))
      |> Enum.flat_map(fn %{key: key} ->
        case avatar_owner_id(key) do
          {:ok, owner_id} -> [{owner_id, key}]
          :error -> []
        end
      end)

    live = live_owner_ids(candidates)

    candidates
    |> Enum.reject(fn {owner_id, _key} -> MapSet.member?(live, owner_id) end)
    |> Enum.count(fn {_owner_id, key} -> Storage.delete(key) == :ok end)
  end

  defp live_owner_ids([]), do: MapSet.new()

  defp live_owner_ids(candidates) do
    owner_ids = candidates |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

    from(u in User, where: u.id in ^owner_ids, select: u.id)
    |> Repo.all()
    |> MapSet.new()
  end

  # A backend that cannot report `last_modified` reports nil; treat that as "not
  # settled" rather than deleting an object on no information at all.
  defp settled?(%{last_modified: %DateTime{} = at}, cutoff), do: DateTime.before?(at, cutoff)
  defp settled?(_object, _cutoff), do: false

  defp avatar_owner_id("avatars/" <> rest) do
    case String.split(rest, "/", parts: 2) do
      [owner, _object] -> Ecto.UUID.cast(owner)
      _no_object -> :error
    end
  end

  defp avatar_owner_id(_key), do: :error

  defp prune_expired_ip_bans do
    now = DateTime.utc_now(:second)

    {count, _} =
      Repo.delete_all(
        from(b in Gamend.IpBans.IpBan,
          where: not is_nil(b.expires_at) and b.expires_at < ^now
        )
      )

    count
  end

  # Releases the seat of a player who has been offline past the window while
  # their lobby is still alive. `prune_lobbies` below only fires once EVERY
  # member has gone quiet, so without this a single player who disconnects and
  # never returns keeps `users.lobby_id` set for as long as their teammates
  # keep playing - and `join_lobby/3` and `create_lobby/2` both refuse with
  # `:already_in_lobby`, so that player is locked out of starting or joining
  # anything until the old lobby happens to die.
  #
  # Deliberately the same window as the abandoned-lobby sweep: releasing
  # sooner would drop the last member that makes a paused lobby look alive to
  # `prune_lobbies`, letting it delete a game under players who are merely
  # disconnected.
  #
  # Through `leave_lobby/1` rather than a bulk update, so host migration, ready
  # checks, lobby-scoped KV, cache invalidation and broadcasts all still run.
  defp release_offline_lobby_memberships do
    minutes = config(:abandoned_lobby_minutes)

    if minutes > 0, do: do_release_offline_lobby_memberships(minutes), else: 0
  end

  defp do_release_offline_lobby_memberships(minutes) do
    cutoff = DateTime.add(DateTime.utc_now(:second), -minutes, :minute)

    from(u in User,
      where: not is_nil(u.lobby_id),
      where: u.is_online == false,
      where: is_nil(u.last_seen_at) or u.last_seen_at <= ^cutoff,
      order_by: [asc: u.id],
      limit: ^batch()
    )
    |> Repo.all()
    |> Enum.count(&release_membership/1)
  end

  defp release_membership(%User{} = user) do
    match?({:ok, _}, Lobbies.leave_lobby(user))
  rescue
    error ->
      Logger.error(
        "retention failed to release lobby membership for #{user.id}: #{Exception.message(error)}"
      )

      false
  end

  # A party outlives its members' sessions: nothing clears `users.party_id` on
  # disconnect (deliberately - a player who reconnects rejoins their party), so
  # a group that stops playing leaves the party row and every member's
  # `party_id` set forever. Disband once every member has been gone past the
  # same window the lobby rules use.
  #
  # Same window, same reason as the lobby rules: silence is the only signal,
  # and a party whose members are merely disconnected must survive long enough
  # for them to come back.
  defp disband_abandoned_parties do
    minutes = config(:abandoned_party_minutes)

    if minutes > 0, do: do_disband_abandoned_parties(minutes), else: 0
  end

  defp do_disband_abandoned_parties(minutes) do
    cutoff = DateTime.add(DateTime.utc_now(:second), -minutes, :minute)

    from(p in Party,
      as: :party,
      where:
        not exists(
          from(u in User,
            where:
              u.party_id == parent_as(:party).id and
                (u.is_online or u.last_seen_at > ^cutoff),
            select: 1
          )
        ),
      order_by: [asc: p.id],
      limit: ^batch()
    )
    |> Repo.all()
    |> Enum.count(&disband_party/1)
  end

  # Release the party seat of a player who has been gone too long, the way
  # `release_offline_lobby_memberships` does for lobbies.
  #
  # Without it a party outlived its leader indefinitely: the sweep above only
  # fires once EVERY member is quiet, so one crew member still playing kept a
  # party alive around a host who had left hours ago - and only the leader can
  # steer or open a ready check, so the rest were held in a party that could do
  # nothing but be left manually.
  #
  # Through `leave_party/1` rather than a bulk update, so the existing rules
  # decide what leaving means: a departing LEADER disbands the party (there is
  # no host migration here, unlike lobbies), any other member is just removed,
  # and ready checks, cache invalidation and broadcasts all still run.
  defp release_offline_party_memberships do
    minutes = config(:abandoned_party_minutes)

    if minutes > 0, do: do_release_offline_party_memberships(minutes), else: 0
  end

  defp do_release_offline_party_memberships(minutes) do
    cutoff = DateTime.add(DateTime.utc_now(:second), -minutes, :minute)

    from(u in User,
      where: not is_nil(u.party_id),
      where: u.is_online == false,
      where: is_nil(u.last_seen_at) or u.last_seen_at <= ^cutoff,
      order_by: [asc: u.id],
      limit: ^batch()
    )
    |> Repo.all()
    |> Enum.count(&release_party_membership/1)
  end

  defp release_party_membership(%User{} = user) do
    match?({:ok, _}, Parties.leave_party(user))
  rescue
    error ->
      Logger.error(
        "retention failed to release party membership for #{user.id}: #{Exception.message(error)}"
      )

      false
  end

  # An empty party (every member already gone) is abandoned by the same rule -
  # the NOT EXISTS above matches it too, so it is cleaned up here as well.
  defp disband_party(%Party{} = party) do
    match?({:ok, _}, Parties.disband(party))
  rescue
    error ->
      Logger.error("retention failed to disband party #{party.id}: #{Exception.message(error)}")
      false
  end

  # The one class that is not "delete rows older than N", and the one where
  # getting it wrong deletes a live game. A lobby is reaped only when nobody in
  # it has been SEEN for `GAMEND_RETENTION_ABANDONED_LOBBY_MINUTES` - and the lobby
  # itself has not been touched in that time.
  #
  # "Seen" is `last_seen_at`, never the `is_online` flag on its own: connected
  # sockets refresh last_seen every few minutes, so a live player is always
  # inside the window, while a hard server stop leaves every connected user
  # frozen at is_online=true with nothing to clear it until the presence
  # sweeper's next pass. Trusting the flag let an 11-hour-old solo run survive
  # a restart and rejoin the player into a game from the day before.
  #
  # Being over is not a reason to delete: a game that ends a match knows it
  # ended and can delete the lobby itself. Silence is the only signal core can
  # read on its own, so it is the only one it acts on. Disconnecting does not
  # clear `users.lobby_id`, so "no members" is not what abandonment looks like
  # in practice - every player having gone quiet is.
  defp prune_lobbies do
    minutes = config(:abandoned_lobby_minutes)

    if minutes > 0, do: reap_lobbies(abandoned_lobbies_query(minutes), 0), else: 0
  end

  defp abandoned_lobbies_query(minutes) do
    cutoff = DateTime.add(DateTime.utc_now(:second), -minutes, :minute)

    from(l in Lobby,
      as: :lobby,
      where: l.updated_at < ^cutoff,
      where:
        not exists(
          from(u in User,
            where:
              u.lobby_id == parent_as(:lobby).id and
                u.last_seen_at > ^cutoff,
            select: 1
          )
        ),
      order_by: [asc: l.id]
    )
  end

  defp reap_lobbies(query, acc) do
    lobbies = Repo.all(from(l in query, limit: ^batch()))
    deleted = Enum.count(lobbies, &reap_lobby/1)

    cond do
      deleted == 0 -> acc
      length(lobbies) < batch() -> acc + deleted
      true -> reap_lobbies(query, acc + deleted)
    end
  end

  # Through the context rather than a raw delete, so KV cascades, hooks and
  # broadcasts all still fire for a reaped lobby.
  defp reap_lobby(lobby) do
    match?({:ok, _}, Lobbies.delete_lobby(lobby))
  rescue
    error ->
      Logger.error("retention failed to delete lobby #{lobby.id}: #{Exception.message(error)}")
      false
  end

  # One class raising must not cost the whole sweep: every other table still
  # gets pruned, and the failure is logged rather than swallowed.
  defp run_class({class, fun}) do
    count = fun.()
    :telemetry.execute([:gamend, :retention, :pruned], %{count: count}, %{class: class})
    {class, count}
  rescue
    error ->
      Logger.error("retention class #{class} failed: #{Exception.message(error)}")
      {class, 0}
  end

  # Both adapters reject `DELETE ... LIMIT`, so each pass selects a bounded set
  # of ids and deletes those.
  defp delete_in_batches(queryable, acc \\ 0) do
    ids = Repo.all(from(r in exclude(queryable, :select), select: r.id, limit: ^batch()))

    if ids == [] do
      acc
    else
      {count, _} = Repo.delete_all(from(r in queryable, where: r.id in ^ids))

      if length(ids) < batch(), do: acc + count, else: delete_in_batches(queryable, acc + count)
    end
  end

  # Token contexts expire on different clocks, so the window lives in
  # `UserToken` and this inverts it. Nothing to configure: keeping a token past
  # its validity is dead weight, not a policy choice.
  defp prune_expired_user_tokens, do: delete_in_batches(UserToken.expired_query())

  # A personal API token past its expiry, or made before its owner's last
  # password or email change, can never authenticate again. Same reasoning as
  # above: nothing to configure.
  defp prune_dead_api_tokens, do: delete_in_batches(ApiTokens.dead_query())

  # Resolved invites and join requests are a log of past social interactions;
  # pending ones are live UI and are never touched. updated_at is when the row
  # was resolved.
  defp prune_resolved_invites do
    days = config(:invites_days)

    if days > 0 do
      cutoff = cutoff(days)

      Enum.reduce(@invite_schemas, 0, fn schema, acc ->
        query =
          from(r in schema, where: r.status in @resolved_statuses and r.updated_at < ^cutoff)

        acc + delete_in_batches(query)
      end)
    else
      0
    end
  end

  # A ticket is ephemeral queue state in every status: matched ones have long
  # since produced their lobby, and a queued ticket this old belongs to a
  # session that will never match.
  defp prune_stale_tickets do
    hours = config(:matchmaking_tickets_hours)

    if hours > 0 do
      cutoff = DateTime.add(DateTime.utc_now(:second), -hours, :hour)
      delete_in_batches(from(t in Gamend.Matchmaking.Ticket, where: t.inserted_at < ^cutoff))
    else
      0
    end
  end

  # Entries, matches and bracket rows cascade from the tournament row.
  defp prune_finished_tournaments do
    days = config(:tournaments_days)

    if days > 0 do
      cutoff = cutoff(days)

      query =
        from(t in Gamend.Tournaments.Tournament,
          where: t.state in @finished_tournament_states and t.updated_at < ^cutoff
        )

      delete_in_batches(query)
    else
      0
    end
  end

  # Opt-in only: these are the audit trail behind every balance, and a wallet
  # whose history is gone cannot be reconciled or disputed.
  defp prune_ledgers do
    days = config(:ledger_days)

    if days > 0 do
      cutoff = cutoff(days)

      Enum.reduce(@ledger_schemas, 0, fn schema, acc ->
        acc + delete_in_batches(from(e in schema, where: e.inserted_at < ^cutoff))
      end)
    else
      0
    end
  end

  # Defaults live in the declaration, not only in `config/host_runtime.exs`:
  # that file's retention block is inside the prod-only branch, so anything
  # documented as a default would silently be "keep forever" in dev and in
  # every host app that never sets the vars.
  use Gamend.Settings.Provider,
    app: :gamend_core,
    group: :retention,
    label: "Retention"

  setting(:chat_messages_days, :integer,
    default: 0,
    doc: "Delete chat messages older than N days. 0 keeps forever."
  )

  setting(:notifications_days, :integer,
    default: 0,
    doc: "Delete notifications older than N days. 0 keeps forever."
  )

  setting(:payment_events_days, :integer,
    default: 0,
    doc: "Delete payment provider webhook events older than N days. Purchases are never pruned."
  )

  setting(:lobby_snapshots_days, :integer,
    default: 30,
    doc: "Delete lobby snapshots, events and blobs older than N days."
  )

  setting(:lobby_snapshots_flagged_days, :integer,
    default: 90,
    doc: "Longer window for snapshots of runs flagged anomalous."
  )

  setting(:push_tokens_days, :integer,
    default: 270,
    doc: "Delete push tokens untouched for N days. Defaults to Google's stale-token guidance."
  )

  setting(:abandoned_lobby_minutes, :integer,
    default: 15,
    doc:
      "Delete lobbies nobody has been seen in for N minutes, and release the " <>
        "seat of a player offline that long in a lobby still in use. 0 disables both."
  )

  setting(:abandoned_party_minutes, :integer,
    default: 15,
    doc: "Disband parties nobody has been seen in for N minutes. 0 disables."
  )

  setting(:invites_days, :integer,
    default: 30,
    doc: "Delete resolved invites and join requests N days after resolution."
  )

  setting(:matchmaking_tickets_hours, :integer,
    default: 24,
    doc: "Delete matchmaking tickets older than N hours, in any status."
  )

  setting(:tournaments_days, :integer,
    default: 0,
    doc: "Delete finished tournaments older than N days. 0 keeps forever."
  )

  setting(:anonymous_users_days, :integer,
    default: 90,
    doc:
      "Delete device-only accounts inactive for N days. 0 keeps forever. These accounts " <>
        "cost one unauthenticated request to create, so they are the tier that actually " <>
        "needs a sweep."
  )

  setting(:unconfirmed_users_days, :integer,
    default: 30,
    doc:
      "Delete email accounts that never confirmed their address and have been inactive " <>
        "for N days. 0 keeps forever. Accounts that also have a provider login are kept."
  )

  setting(:inactive_users_days, :integer,
    default: 0,
    doc:
      "Delete accounts with a real identity after N days of inactivity. 0 (the default) " <>
        "keeps forever - deleting a player who comes back is worse than the storage. " <>
        "730 matches what Google and Microsoft use if you turn it on."
  )

  setting(:inactive_users_warn_days, :integer,
    default: 30,
    doc:
      "Email a warning this many days before an inactive account is deleted. 0 deletes " <>
        "with no warning. Accounts with no email address cannot be warned."
  )

  setting(:ledger_days, :integer,
    default: 0,
    doc: "Delete wallet/inventory ledger entries older than N days. 0 keeps forever."
  )

  setting(:activity_days, :integer,
    default: 0,
    doc:
      "Delete per-user daily activity rows (DAU / D1-D7-D30 source) older than N days. " <>
        "0 keeps forever. Below 60 the admin retention cohorts go blank."
  )

  setting(:interval_hours, :integer,
    default: 6,
    doc: "Hours between full retention sweeps. The first runs five minutes after boot."
  )

  setting(:live_interval_seconds, :integer,
    default: 60,
    doc:
      "Seconds between sweeps of the classes that free live state: offline lobby and " <>
        "party seats, abandoned parties, abandoned lobbies. 0 leaves them to the full sweep."
  )

  setting(:batch_size, :integer,
    default: 500,
    doc:
      "Rows deleted per statement. Lower it if a sweep stalls gameplay writes on SQLite, " <>
        "where each statement holds the write lock."
  )

  defp config(key), do: Gamend.Settings.get(__MODULE__, key)

  defp batch, do: max(config(:batch_size), 1)
end
