defmodule Gamend.Matchmaking do
  @moduledoc """
  Public API for the built-in matchmaking system.

  Matchmaking is ticket-based. Each call to `join/4` creates a ticket in the
  database. The periodic `Gamend.Matchmaking.Worker` groups queued tickets
  that share the same `match_params` and creates a hidden lobby for each match.

  Tickets are the source of truth; there is no cached queue. The sweep reads
  them directly through the `(status, queued_at)` index, and the worker
  serializes the sweep cluster-wide so only one instance forms matches at a
  time.

  ## Liveness

  A queued ticket only means something while its owner can still be pulled
  into a lobby. Two things keep the queue honest:

    * `UserChannel.terminate/2` cancels the user's tickets when their socket
      closes, and
    * `prune_offline/0` sweeps tickets whose owner the database no longer
      considers online — the safety net for tickets created over HTTP by a
      client that never opened a socket.
  """

  import Ecto.Query

  alias Gamend.Accounts.User
  alias Gamend.Limits
  alias Gamend.Matchmaking.Constants
  alias Gamend.Matchmaking.Ticket
  alias Gamend.Matchmaking.Worker
  alias Gamend.Repo

  @doc """
  Adds a user — or their whole party — to the matchmaking queue.

  `match_params` is a map of arbitrary string keys and values, for example
  `%{"mode" => "deathmatch", "map" => "dust2"}`. Only tickets with exactly the
  same parameters are matched together.

  `min_players` and `max_players` can be passed to override the defaults.

  ## Parties

  A user in a party cannot queue alone: only the leader may queue, and doing so
  creates one ticket per member sharing the party's id. Those tickets are
  matched as an indivisible unit. Because only the leader queues, every member's
  ticket carries the same limits by construction — there is no way for members
  to disagree about `min_players`/`max_players`.

  Returns the caller's own ticket. Fails with:

    * `{:error, :not_party_leader}` — a member tried to queue
    * `{:error, :party_too_large}` — the party cannot fit in `max_players`
    * `{:error, :party_has_blocked_pair}` — two members have blocked each other
    * `{:error, :already_queued}` — the caller or a party member is queued
  """
  @spec join(User.t(), map(), pos_integer() | nil, pos_integer() | nil) ::
          {:ok, Ticket.t()} | {:error, Ecto.Changeset.t() | atom()}
  def join(%User{} = user, match_params, min_players \\ nil, max_players \\ nil) do
    proposed = %{
      "match_params" => normalize_params(match_params),
      "min_players" => min_players || default_min_players(),
      "max_players" => max_players || default_max_players()
    }

    # The client proposes; the game decides. A hook may rewrite the params
    # (stamping a server-computed skill band) or refuse the join outright.
    # The hook runs *before* the guard, so the write is the last thing that
    # happens rather than being separated from its check by up to a minute of
    # plugin time. The partial unique index
    # (`matchmaking_tickets_one_queued_per_user`) closes the remaining window.
    with {:ok, members} <- resolve_queue_group(user, proposed),
         {:ok, attrs} <- run_join_hook(user, proposed),
         :ok <- ensure_none_queued(members) do
      case insert_tickets(user, members, attrs) do
        {:error, %Ecto.Changeset{errors: errors}} = error ->
          if Keyword.has_key?(errors, :user_id), do: {:error, :already_queued}, else: error

        result ->
          result
      end
    end
  end

  # A ticket that leaves its size out gets the server's
  # (`GAMEND_LIMITS_MATCHMAKING_DEFAULT_*_PLAYERS`).
  defp default_min_players, do: Limits.get(:matchmaking_default_min_players)
  defp default_max_players, do: Limits.get(:matchmaking_default_max_players)

  defp run_join_hook(user, proposed) do
    case Gamend.Hooks.internal_call(:before_matchmaking_join, [user, proposed]) do
      {:ok, attrs} when is_map(attrs) -> {:ok, attrs}
      {:ok, _other} -> {:ok, proposed}
      {:error, reason} -> {:error, reason}
    end
  end

  # Solo queuers are a group of one. A party queues as a whole, leader only, and
  # only if it can actually fit in a match — a 5-player party in a 4-player mode
  # would otherwise sit in the queue forever.
  defp resolve_queue_group(%User{party_id: nil} = user, _proposed), do: {:ok, [user]}

  defp resolve_queue_group(%User{} = user, proposed) do
    if Gamend.Parties.can_manage_party?(user, user.party_id) do
      members = Gamend.Parties.get_party_members(user.party_id)
      max = Map.get(proposed, "max_players") || default_max_players()

      cond do
        length(members) > max ->
          {:error, :party_too_large}

        party_has_blocked_pair?(members) ->
          {:error, :party_has_blocked_pair}

        true ->
          {:ok, members}
      end
    else
      {:error, :not_party_leader}
    end
  end

  # An invite cannot put a blocked pair in a party, but blocking someone you are
  # already partied with can — and that is the usual moment to block anyone.
  # Such a party is unseatable: the lobby would be built and then rejected by
  # `Lobbies.join_lobby/2`, silently dropping a member from the queue. Refuse up
  # front so the leader is told instead.
  defp party_has_blocked_pair?(members) do
    members
    |> Enum.map(& &1.id)
    |> Gamend.Friends.blocked_pairs()
    |> Enum.any?()
  end

  # One queued ticket per user. Without this a double join matches a user with
  # themselves: the lobby is created, the second seat fails, and the whole match
  # is discarded.
  defp ensure_none_queued(members) do
    ids = Enum.map(members, & &1.id)

    if Repo.exists?(where(queued(), [t], t.user_id in ^ids)) do
      {:error, :already_queued}
    else
      :ok
    end
  end

  defp insert_tickets(%User{} = caller, members, attrs) do
    now = DateTime.utc_now()

    base = %{
      status: Constants.status_queued(),
      match_params: normalize_params(Map.get(attrs, "match_params", %{})),
      min_players: Map.get(attrs, "min_players") || default_min_players(),
      max_players: Map.get(attrs, "max_players") || default_max_players(),
      timeout_ms: Limits.get(:matchmaking_timeout_ms),
      queued_at: now,
      party_id: caller.party_id
    }

    result =
      Gamend.AfterCommit.transaction(fn ->
        Enum.reduce_while(members, [], fn member, acc ->
          %Ticket{}
          |> Ticket.changeset(Map.put(base, :user_id, member.id))
          |> Repo.insert()
          |> case do
            {:ok, ticket} -> {:cont, [{member, ticket} | acc]}
            {:error, changeset} -> {:halt, Repo.rollback(changeset)}
          end
        end)
      end)

    with {:ok, inserted} <- result do
      # Hooks fire outside the transaction — never dispatch inside one.
      Enum.each(inserted, fn {member, ticket} ->
        Gamend.Async.run(fn ->
          Gamend.Hooks.internal_call(:after_matchmaking_join, [member, ticket])
        end)
      end)

      # This ticket may be the one that completes a bucket, so ask for a sweep
      # instead of waiting out the tick. The worker coalesces and runs it in its
      # own process; nothing here blocks on matching.
      Worker.nudge()

      {:ok, Enum.find_value(inserted, fn {m, t} -> if m.id == caller.id, do: t end)}
    end
  end

  @doc """
  Cancels the user's queued tickets. Returns how many were cancelled.

  A party queues as a unit, so it leaves as one: cancelling any member's ticket
  cancels the whole party's. Any member may do this — only the leader can queue,
  but nobody should be stuck in a queue they cannot leave.
  """
  @spec cancel(Ecto.UUID.t()) :: non_neg_integer()
  def cancel(user_id) when is_binary(user_id) do
    {count, _} =
      queued()
      |> where([t], t.user_id == ^user_id or t.party_id in subquery(party_ids_of(user_id)))
      |> Repo.update_all(set: cancelled_fields())

    if count > 0 do
      Gamend.Async.run(fn ->
        Gamend.Hooks.internal_call(:after_matchmaking_cancel, [user_id, count])
      end)
    end

    count
  end

  @doc """
  Cancels one ticket by id, whoever owns it — for admins clearing a stuck
  ticket. Returns `{:error, :not_found}` for an unknown, malformed or
  already-resolved id.
  """
  @spec cancel_ticket(Ecto.UUID.t()) :: {:ok, Ticket.t()} | {:error, :not_found}
  def cancel_ticket(ticket_id) do
    with %Ticket{status: status} = ticket <- Repo.get_uuid(Ticket, ticket_id),
         true <- status == Constants.status_queued() do
      ticket
      |> Ecto.Changeset.change(status: Constants.status_cancelled())
      |> Repo.update()
    else
      _ -> {:error, :not_found}
    end
  end

  @doc "The user's current queued ticket, or nil."
  @spec current_ticket(Ecto.UUID.t()) :: Ticket.t() | nil
  def current_ticket(user_id) when is_binary(user_id) do
    queued()
    |> where([t], t.user_id == ^user_id)
    |> order_by([t], desc: t.queued_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc "Fetches a ticket by id, or nil when the id is unknown or malformed."
  @spec get_ticket(Ecto.UUID.t()) :: Ticket.t() | nil
  def get_ticket(ticket_id) do
    case Repo.get_uuid(Ticket, ticket_id) do
      nil -> nil
      ticket -> Repo.preload(ticket, :user)
    end
  end

  @doc """
  Lists tickets for the admin views, newest first.

  Options: `:status`, `:user_id`, `:page`, `:page_size`.
  """
  @spec list_tickets(keyword()) :: [Ticket.t()]
  def list_tickets(opts \\ []) do
    opts
    |> tickets_query()
    |> order_by([t], desc: t.queued_at)
    |> paginate(opts)
    |> preload(:user)
    |> Repo.all()
  end

  @doc "Counts tickets matching the same filters as `list_tickets/1`."
  @spec count_tickets(keyword()) :: non_neg_integer()
  def count_tickets(opts \\ []) do
    opts |> tickets_query() |> Repo.aggregate(:count, :id)
  end

  @doc """
  All queued tickets grouped by `match_params`, oldest first within a group.

  Read straight from the database: the queue changes on every join and the
  sweep runs seconds apart, so caching here would only ever serve stale rows.
  """
  @spec list_queued_by_params() :: %{map() => [Ticket.t()]}
  def list_queued_by_params do
    queued()
    |> order_by([t], asc: t.queued_at)
    |> preload(:user)
    |> Repo.all()
    |> Enum.group_by(& &1.match_params)
  end

  @doc """
  Atomically claims a formed match: flips its tickets from queued to matched.

  Runs inside the sweep's cluster lock, before any lobby exists (the lobby is
  created outside the lock because `Lobbies` fires hooks and broadcasts, which
  must not run inside a transaction). The `status == queued` guard makes the
  claim atomic: if any ticket was cancelled since it was read, nothing is
  claimed and `:conflict` is returned.
  """
  @spec claim([Ticket.t()]) :: :ok | :conflict
  def claim(tickets) do
    ids = Enum.map(tickets, & &1.id)
    now = DateTime.utc_now()

    {count, _} =
      queued()
      |> where([t], t.id in ^ids)
      |> Repo.update_all(
        set: [status: Constants.status_matched(), matched_at: now, updated_at: now]
      )

    if count == length(ids) do
      :ok
    else
      # Partial claim: revert whatever we flipped and let the next tick retry.
      _ = requeue(tickets)
      :conflict
    end
  end

  @doc "Returns claimed tickets to the queue (lobby creation failed)."
  @spec requeue([Ticket.t()]) :: :ok
  def requeue(tickets) do
    ids = Enum.map(tickets, & &1.id)

    Ticket
    |> where([t], t.id in ^ids and t.status == ^Constants.status_matched())
    |> where([t], is_nil(t.match_id))
    |> Repo.update_all(
      set: [
        status: Constants.status_queued(),
        matched_at: nil,
        updated_at: DateTime.utc_now()
      ]
    )

    :ok
  end

  @doc """
  Cancels claimed tickets whose owner could not be seated in the lobby.
  Unlike `requeue/1` these do not go back in the queue — a user who cannot
  join a lobby (banned, already in one) would fail again on every tick.
  """
  @spec discard([Ticket.t()]) :: :ok
  def discard(tickets) do
    ids = Enum.map(tickets, & &1.id)

    Ticket
    |> where([t], t.id in ^ids and t.status == ^Constants.status_matched())
    |> where([t], is_nil(t.match_id))
    |> Repo.update_all(set: cancelled_fields())

    :ok
  end

  @doc "Associates already-claimed tickets with their created lobby."
  @spec assign_lobby([Ticket.t()], Ecto.UUID.t()) :: :ok
  def assign_lobby(tickets, lobby_id) do
    ids = Enum.map(tickets, & &1.id)

    Ticket
    |> where([t], t.id in ^ids)
    |> Repo.update_all(set: [match_id: lobby_id, updated_at: DateTime.utc_now()])

    :ok
  end

  @doc """
  Cancels queued tickets whose owner has been offline past the grace period.

  Reads `users.is_online` — the flag the user channel maintains — instead of
  taking a caller-supplied id list, so it stays correct on any node. Going
  offline is not enough on its own: the player must have been gone longer than
  `matchmaking_offline_grace_ms`, so a brief disconnect does not cost a queue
  position. A player who queued over HTTP and never opened a socket has no
  `last_seen_at`, so their `queued_at` starts the same grace period.

  A party is matched as a unit, so it is pruned as one: if any member times
  out, the whole party leaves the queue. Returns how many tickets were
  cancelled.
  """
  @spec prune_offline() :: non_neg_integer()
  def prune_offline do
    cutoff =
      DateTime.add(DateTime.utc_now(), -Limits.get(:matchmaking_offline_grace_ms), :millisecond)

    stale =
      from(t in Ticket,
        join: u in User,
        on: u.id == t.user_id,
        where:
          t.status == ^Constants.status_queued() and u.is_online == false and
            coalesce(u.last_seen_at, t.queued_at) < ^cutoff,
        select: {t.id, t.party_id}
      )
      |> Repo.all()

    if stale == [] do
      0
    else
      {ids, party_ids} = Enum.unzip(stale)
      party_ids = party_ids |> Enum.reject(&is_nil/1) |> Enum.uniq()

      {count, _} =
        queued()
        |> where([t], t.id in ^ids or t.party_id in ^party_ids)
        |> Repo.update_all(set: cancelled_fields())

      count
    end
  end

  @doc """
  Queue statistics for the admin dashboard and the public stats endpoint:
  counts by status, plus the depth of each distinct queued `match_params`.
  """
  @spec stats() :: %{
          queued: non_neg_integer(),
          matched: non_neg_integer(),
          cancelled: non_neg_integer(),
          queues: [%{params: map(), waiting: non_neg_integer()}]
        }
  def stats do
    by_status =
      from(t in Ticket, group_by: t.status, select: {t.status, count(t.id)})
      |> Repo.all()
      |> Map.new()

    queues =
      list_queued_by_params()
      |> Enum.map(fn {params, tickets} -> %{params: params, waiting: length(tickets)} end)
      |> Enum.sort_by(& &1.waiting, :desc)

    %{
      queued: Map.get(by_status, Constants.status_queued(), 0),
      matched: Map.get(by_status, Constants.status_matched(), 0),
      cancelled: Map.get(by_status, Constants.status_cancelled(), 0),
      queues: queues
    }
  end

  # ── internals ─────────────────────────────────────────────────────────────

  defp queued, do: where(Ticket, [t], t.status == ^Constants.status_queued())

  # The party ids this user currently has a queued ticket under (at most one).
  # Used to widen a cancel from one member to the whole party unit.
  defp party_ids_of(user_id) do
    queued()
    |> where([t], t.user_id == ^user_id and not is_nil(t.party_id))
    |> select([t], t.party_id)
  end

  defp cancelled_fields,
    do: [status: Constants.status_cancelled(), updated_at: DateTime.utc_now()]

  defp tickets_query(opts) do
    Ticket
    |> filter_status(Keyword.get(opts, :status))
    |> Gamend.Query.filter_user(Keyword.get(opts, :user_id))
  end

  defp filter_status(query, status) when is_binary(status) and status != "",
    do: where(query, [t], t.status == ^status)

  defp filter_status(query, _status), do: query

  # Pagination is opt-in; an unwindowed read is still bounded.
  defp paginate(query, opts), do: Gamend.Query.maybe_page(query, opts)

  defp normalize_params(params) when is_map(params) do
    Map.new(params, fn {k, v} -> {to_string(k), to_string(v)} end)
  end

  defp normalize_params(_params), do: %{}
end
