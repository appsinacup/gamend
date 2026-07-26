defmodule GameServer.Retention do
  @moduledoc """
  Periodically prunes old rows from unbounded tables.

  Retention is configured per table in days via env vars (see
  `config/host_runtime.exs`); `0` or unset keeps data forever:

  - `RETENTION_CHAT_DAYS` — `chat_messages` older than N days
  - `RETENTION_NOTIFICATIONS_DAYS` — `notifications` older than N days
  - `RETENTION_PAYMENT_EVENTS_DAYS` — payment provider webhook events older
    than N days (purchases/entitlements are never pruned)
  - `RETENTION_LOBBY_SNAPSHOTS_DAYS` — lobby snapshots, events and their
    content blobs. Unlike the others this defaults to 30 rather than "keep
    forever": snapshots hold user metadata, and the window is what bounds that
    exposure. Runs flagged anomalous keep
    `RETENTION_LOBBY_SNAPSHOTS_FLAGGED_DAYS` instead (default 90).
  - `RETENTION_PUSH_TOKENS_DAYS` — push tokens untouched (registered, used,
    or disabled) for N days. Defaults to 270 — Google's stale-token guidance
    — so the table tracks live devices, not install history.
  - `RETENTION_INVITES_DAYS` — resolved group/party invites and join requests,
    N days after resolution (default 30). Pending rows are never pruned.
  - `RETENTION_MATCHMAKING_TICKETS_HOURS` — tickets older than N hours
    (default 24), in any status.
  - `RETENTION_TOURNAMENTS_DAYS` / `RETENTION_LEDGER_DAYS` — finished
    tournaments and the wallet/inventory ledgers. Both default to `0`: they
    are history an operator may be required to keep.
  - `RETENTION_ABANDONED_LOBBY_MINUTES` (15) — lobbies nobody has been seen in
    for N minutes, in minutes rather than days. See `prune_lobbies/0`.

  Expired IP bans, OAuth sessions older than a day, and user tokens past their
  own context's validity are always removed (independent of the env vars
  above). Deletes are idempotent, so running on several instances at once is
  harmless; each class is batched and failure-isolated, and emits
  `[:game_server, :retention, :pruned]` telemetry with its count.
  """

  use GenServer

  import Ecto.Query

  require Logger

  alias GameServer.Accounts.{User, UserToken}
  alias GameServer.Lobbies
  alias GameServer.Lobbies.Lobby
  alias GameServer.LobbySnapshots.{Blob, Event, Snapshot}
  alias GameServer.Repo

  # First run shortly after boot, then every 6 hours.
  @initial_delay_ms :timer.minutes(5)
  @interval_ms :timer.hours(6)

  # OAuth sessions are ephemeral handshake state (seconds-to-minutes of use);
  # always prune stale rows so the table can't grow unbounded.
  @oauth_session_ttl_days 1

  # Rows deleted per statement. The sweep runs against a live database: on
  # SQLite one large DELETE holds the write lock long enough to stall gameplay
  # writes, and on Postgres it bloats a single transaction.
  @batch 500

  # Invites and join requests are only garbage once they stop being actionable.
  @resolved_statuses ~w(accepted declined rejected cancelled expired)

  @invite_schemas [
    GameServer.Groups.GroupInvite,
    GameServer.Groups.GroupJoinRequest,
    GameServer.Parties.PartyInvite
  ]

  @ledger_schemas [GameServer.Economy.LedgerEntry, GameServer.Inventory.LedgerEntry]

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
    Process.send_after(self(), :prune, @interval_ms)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

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
  Runs all configured pruning steps once. Returns a map of deleted row
  counts per table.
  """
  @spec prune_all() :: %{atom() => non_neg_integer()}
  def prune_all do
    results =
      %{
        chat_messages: fn ->
          prune_older_than(GameServer.Chat.Message, config(:chat_messages_days))
        end,
        notifications: fn ->
          prune_older_than(GameServer.Notifications.Notification, config(:notifications_days))
        end,
        payment_events: fn ->
          prune_older_than(GameServer.Payments.ProviderEvent, config(:payment_events_days))
        end,
        oauth_sessions: fn ->
          prune_older_than(GameServer.OAuthSession, @oauth_session_ttl_days)
        end,
        expired_ip_bans: &prune_expired_ip_bans/0,
        expired_user_tokens: &prune_expired_user_tokens/0,
        lobby_snapshots: &prune_lobby_snapshots/0,
        lobby_snapshot_blobs: &prune_lobby_snapshot_blobs/0,
        lobbies: &prune_lobbies/0,
        resolved_invites: &prune_resolved_invites/0,
        matchmaking_tickets: &prune_stale_tickets/0,
        finished_tournaments: &prune_finished_tournaments/0,
        ledger_entries: &prune_ledgers/0,
        quest_periods: &GameServer.Quests.prune_old_periods/0,
        quest_reward_recoveries: &GameServer.Quests.recover_pending_rewards/0,
        push_tokens: &prune_push_tokens/0
      }
      |> Map.new(fn {class, fun} -> {class, run_class(class, fun)} end)

    pruned = results |> Map.values() |> Enum.sum()

    if pruned > 0 do
      Logger.info("retention pruned rows: #{inspect(results)}")
    end

    results
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
        Repo.delete_all(from(t in GameServer.Push.PushToken, where: t.updated_at < ^cutoff))

      count
    else
      0
    end
  end

  defp prune_expired_ip_bans do
    now = DateTime.utc_now(:second)

    {count, _} =
      Repo.delete_all(
        from(b in GameServer.IpBans.IpBan,
          where: not is_nil(b.expires_at) and b.expires_at < ^now
        )
      )

    count
  end

  # The one class that is not "delete rows older than N", and the one where
  # getting it wrong deletes a live game. A lobby is reaped only when nobody in
  # it has been seen for `RETENTION_ABANDONED_LOBBY_MINUTES` - not online, and
  # not online at any point inside the window - and the lobby itself has not
  # been touched in that time.
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
                (u.is_online or u.last_seen_at > ^cutoff),
            select: 1
          )
        ),
      order_by: [asc: l.id]
    )
  end

  defp reap_lobbies(query, acc) do
    lobbies = Repo.all(from(l in query, limit: @batch))
    deleted = Enum.count(lobbies, &reap_lobby/1)

    cond do
      deleted == 0 -> acc
      length(lobbies) < @batch -> acc + deleted
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
  defp run_class(class, fun) do
    count = fun.()
    :telemetry.execute([:game_server, :retention, :pruned], %{count: count}, %{class: class})
    count
  rescue
    error ->
      Logger.error("retention class #{class} failed: #{Exception.message(error)}")
      0
  end

  # Both adapters reject `DELETE ... LIMIT`, so each pass selects a bounded set
  # of ids and deletes those.
  defp delete_in_batches(queryable, acc \\ 0) do
    ids = Repo.all(from(r in exclude(queryable, :select), select: r.id, limit: @batch))

    if ids == [] do
      acc
    else
      {count, _} = Repo.delete_all(from(r in queryable, where: r.id in ^ids))

      if length(ids) < @batch, do: acc + count, else: delete_in_batches(queryable, acc + count)
    end
  end

  # Token contexts expire on different clocks, so the window lives in
  # `UserToken` and this inverts it. Nothing to configure: keeping a token past
  # its validity is dead weight, not a policy choice.
  defp prune_expired_user_tokens, do: delete_in_batches(UserToken.expired_query())

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
      delete_in_batches(from(t in GameServer.Matchmaking.Ticket, where: t.inserted_at < ^cutoff))
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
        from(t in GameServer.Tournaments.Tournament,
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
  use GameServer.Settings.Provider,
    app: :game_server_core,
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
    doc: "Delete lobbies nobody has been seen in for N minutes. 0 disables."
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

  setting(:ledger_days, :integer,
    default: 0,
    doc: "Delete wallet/inventory ledger entries older than N days. 0 keeps forever."
  )

  defp config(key), do: GameServer.Settings.get(__MODULE__, key)
end
