defmodule Gamend.Matchmaking do
  @moduledoc """
  Public API for the built-in matchmaking system.

  Matchmaking is ticket-based. Each call to `join/5` creates a ticket in the
  database. The periodic `Gamend.Matchmaking.Worker` groups queued tickets
  that share the same `match_params` and creates a hidden lobby for each match.

  Tickets are the source of truth; there is no cached queue. The sweep reads
  them directly through the `(status, queued_at)` index, and the worker
  serializes the sweep cluster-wide so only one instance forms matches at a
  time.

  ## Liveness

  A queued ticket only means something while its owner can still be pulled
  into a lobby. Two things keep the queue honest:

    * `Gamend.Accounts.Online.disconnected/2` cancels the user's tickets when
      their last socket closes (a game's, or a website page's), and
    * `prune_offline/0` sweeps tickets whose owner the database no longer
      considers online — the safety net for tickets created over HTTP by a
      client that never opened a socket.

  ## Events

  A ticket's player hears it on their user channel (`matchmaking:user:<id>`):
  `ticket_queued` (joined, or `requeued` after a failed accept),
  `ticket_cancelled` (with why), and `match_found` once seated; an accept is
  the `ready_check_*` events, kind `accept`.

  ## Backfill

  A lobby's host who queues fills that lobby: the ticket carries its
  `lobby_id`, and a match seats the other players there rather than in a new
  lobby. A match holds at most one lobby with other players in it, and fits
  in its seats; a player queued from a lobby of their own alone leaves it for
  the match's. With no lobby among them, a match gets a new hidden lobby, as
  before.

  ## Seating

  Once a match forms, the game's `matchmaking_seat_match/1` says where it sits
  and whether its players are asked first (`Gamend.MatchSeating`). With no
  answer, core seats it as *Backfill* says.

  ## Accept

  A seating with `accept_timeout_ms` makes a formed match ask first: a ready
  check of kind `accept` over the players holding its tickets
  (`Gamend.ReadyChecks`, subject `:matchmaking`). Nobody is seated until
  everyone accepts. A decline or the deadline fails it: whoever accepted, or
  had not answered when another declined, goes back in the queue, keeping
  their place, and the others' tickets are cancelled. Cancelling a ticket
  (`cancel/1`, a socket closing) declines the accept its holder was asked
  for. A player who declined may queue again at once (a game's Skip that
  keeps looking): their declined ticket no longer counts as queued, though it
  is cancelled only once the check settles.
  """

  import Ecto.Query

  alias Gamend.Accounts.User
  alias Gamend.Limits
  alias Gamend.Matchmaking.Broadcast
  alias Gamend.Matchmaking.Constants
  alias Gamend.Matchmaking.Ticket
  alias Gamend.Matchmaking.Worker
  alias Gamend.ReadyChecks.Check
  alias Gamend.ReadyChecks.Participant
  alias Gamend.Repo

  require Gamend.Matchmaking.CancelReason, as: CancelReason
  require Gamend.ReadyChecks.CheckKind, as: CheckKind
  require Gamend.ReadyChecks.CheckStatus, as: CheckStatus
  require Gamend.ReadyChecks.ParticipantState, as: ParticipantState

  # How long a claimed ticket, or one whose accept just settled, may wait for
  # its seat or its place back in the queue: a join meanwhile is refused.
  @held_ms 60_000

  @doc """
  Adds a user — or their whole party — to the matchmaking queue.

  `match_params` is a map of arbitrary string keys and values, for example
  `%{"mode" => "deathmatch", "map" => "dust2"}`. Only tickets with exactly the
  same parameters are matched together.

  `min_players` and `max_players` can be passed to override the defaults.

  A lobby's host queues to fill that lobby (see *Backfill*).

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
  # is discarded. A ticket matched and waiting for its accept counts too: its
  # match may still seat them.
  defp ensure_none_queued(members) do
    ids = Enum.map(members, & &1.id)

    # A matched ticket with no match yet is held: being seated, or in an
    # accept still asking, or one that just settled with its holder still in
    # (seated next, or put back in the queue). Never an old one: a seated
    # ticket loses its `match_id` when its lobby is deleted (`nilify_all`),
    # and a holder who declined or let it run out is free (*Accept*).
    now = DateTime.utc_now()
    settled_since = now |> DateTime.add(-@held_ms, :millisecond) |> DateTime.truncate(:second)
    claimed_since = DateTime.add(now, -@held_ms, :millisecond)

    asked =
      from(p in Participant,
        join: c in Check,
        on: c.id == p.ready_check_id,
        where: p.ticket_id == parent_as(:ticket).id,
        where:
          c.status == ^CheckStatus.pending() or
            (c.resolved_at > ^settled_since and
               p.state in ^[ParticipantState.ready(), ParticipantState.pending()])
      )

    any_check = from(p in Participant, where: p.ticket_id == parent_as(:ticket).id)

    waiting =
      from(t in Ticket,
        as: :ticket,
        where: t.user_id in ^ids,
        where:
          t.status == ^Constants.status_queued() or
            (t.status == ^Constants.status_matched() and is_nil(t.match_id) and
               (exists(asked) or (not exists(any_check) and t.matched_at > ^claimed_since)))
      )

    if Repo.exists?(waiting) do
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
      party_id: caller.party_id,
      lobby_id: backfill_lobby_id(caller, members)
    }

    # The caller's party was read before this; disbanded since, a ticket would
    # point at nothing, and the database refuses it.
    result =
      Repo.rescue_foreign_key(:not_found, fn ->
        Gamend.AfterCommit.transaction(fn -> insert_member_tickets(members, base) end)
      end)

    with {:ok, inserted} <- result do
      Broadcast.ticket_queued(Enum.map(inserted, &elem(&1, 1)), false)

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

  # The lobby a ticket fills: the caller's, when they queue alone as its host.
  # Read fresh, not from the cached user the request carried: a seat taken or
  # left a moment ago decides it.
  defp backfill_lobby_id(%User{id: user_id}, [_alone]) do
    with %User{lobby_id: lobby_id, party_id: nil} when is_binary(lobby_id) <-
           Repo.get(User, user_id),
         %Gamend.Lobbies.Lobby{host_id: ^user_id} <- Gamend.Lobbies.get_lobby(lobby_id) do
      lobby_id
    else
      _ -> nil
    end
  end

  defp backfill_lobby_id(_caller, _party), do: nil

  defp insert_member_tickets(members, base) do
    Enum.reduce_while(members, [], fn member, acc ->
      %Ticket{}
      |> Ticket.changeset(Map.put(base, :user_id, member.id))
      |> Repo.insert()
      |> case do
        {:ok, ticket} -> {:cont, [{member, ticket} | acc]}
        {:error, changeset} -> {:halt, Repo.rollback(changeset)}
      end
    end)
  end

  @doc """
  Cancels the user's queued tickets. Returns how many were cancelled.

  A party queues as a unit, so it leaves as one: cancelling any member's ticket
  cancels the whole party's. Any member may do this — only the leader can queue,
  but nobody should be stuck in a queue they cannot leave.

  A match waiting for its accept is declined for the user (see *Accept*), so
  the others go back in the queue at once rather than at its deadline.
  """
  @spec cancel(Ecto.UUID.t()) :: non_neg_integer()
  def cancel(user_id) when is_binary(user_id) do
    _ = decline_accept(user_id)

    {count, cancelled} =
      queued()
      |> where([t], t.user_id == ^user_id or t.party_id in subquery(party_ids_of(user_id)))
      |> select([t], map(t, [:id, :user_id]))
      |> Repo.update_all(set: cancelled_fields())

    Broadcast.ticket_cancelled(cancelled, CancelReason.left())

    if count > 0 do
      Gamend.Async.run(fn ->
        Gamend.Hooks.internal_call(:after_matchmaking_cancel, [user_id, count])
      end)
    end

    count
  end

  defp decline_accept(user_id) do
    case Gamend.ReadyChecks.for_user(user_id, :match) do
      %Check{kind: CheckKind.accept(), lobby_id: nil, party_id: nil} ->
        Gamend.ReadyChecks.respond(user_id, false)

      _ ->
        :ok
    end
  end

  @doc """
  Cancels one ticket by id, whoever owns it — for admins clearing a stuck
  ticket. Returns `{:error, :not_found}` for an unknown, malformed or
  already-resolved id.
  """
  @spec cancel_ticket(Ecto.UUID.t()) :: {:ok, Ticket.t()} | {:error, :not_found}
  def cancel_ticket(ticket_id) do
    # Cancelled only while still queued, checked by the write: a ticket read
    # queued could be matched by the sweep before the cancel landed, and the
    # cancel then took a seated player's ticket out of their match.
    with %Ticket{id: id} <- Repo.get_uuid(Ticket, ticket_id),
         {:ok, ticket} <-
           queued() |> where([t], t.id == ^id) |> Repo.compare_and_set(set: cancelled_fields()) do
      Broadcast.ticket_cancelled([ticket], CancelReason.admin())
      {:ok, ticket}
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
    |> with_lobbies()
    |> Enum.group_by(& &1.match_params)
  end

  @doc """
  `tickets` with each backfill ticket's lobby read: `size` its members,
  `capacity` its seats. A ticket whose holder no longer hosts the lobby it
  named fills nothing (`lobby_id` nil): it is seated as any other.
  """
  @spec with_lobbies([Ticket.t()]) :: [Ticket.t()]
  def with_lobbies(tickets) do
    lobby_ids = tickets |> Enum.map(& &1.lobby_id) |> Enum.reject(&is_nil/1) |> Enum.uniq()
    lobbies = lobby_rows(lobby_ids)

    Enum.map(tickets, fn ticket ->
      case Map.get(lobbies, ticket.lobby_id) do
        %{host_id: host_id, members: members, max_users: max_users}
        when host_id == ticket.user_id and members > 0 ->
          %{ticket | size: members, capacity: max_users}

        _ ->
          %{ticket | lobby_id: nil, size: 1, capacity: nil}
      end
    end)
  end

  defp lobby_rows([]), do: %{}

  defp lobby_rows(lobby_ids) do
    members =
      from(u in User,
        where: u.lobby_id in ^lobby_ids,
        group_by: u.lobby_id,
        select: {u.lobby_id, count(u.id)}
      )
      |> Repo.all()
      |> Map.new()

    from(l in Gamend.Lobbies.Lobby,
      where: l.id in ^lobby_ids,
      select: {l.id, l.host_id, l.max_users}
    )
    |> Repo.all()
    |> Map.new(fn {id, host_id, max_users} ->
      {id, %{host_id: host_id, max_users: max_users, members: Map.get(members, id, 0)}}
    end)
  end

  @doc """
  The lobby a match is seated in: the one of its lobbies with other players
  in it, else its oldest ticket's. nil when no ticket fills a lobby (a new
  lobby is made). Reads `size` as `with_lobbies/1` set it.
  """
  @spec target_ticket([Ticket.t()]) :: Ticket.t() | nil
  def target_ticket(tickets) do
    backfill =
      tickets
      |> Enum.filter(&Map.get(&1, :lobby_id))
      |> Enum.sort_by(& &1.queued_at, DateTime)

    Enum.find(backfill, &(size(&1) > 1)) || List.first(backfill)
  end

  @doc """
  Whether `tickets` can be one match: at most one lobby with other players in
  it, and no more players than the lobby it would be seated in has seats.
  """
  @spec seatable?([Ticket.t()]) :: boolean()
  def seatable?(tickets) do
    players = Enum.reduce(tickets, 0, &(size(&1) + &2))
    capacity = tickets |> target_ticket() |> then(&(&1 && Map.get(&1, :capacity)))

    Enum.count(tickets, &(Map.get(&1, :lobby_id) && size(&1) > 1)) <= 1 and
      (is_nil(capacity) or players <= capacity)
  end

  @doc "The players a ticket brings: its lobby's members for a backfill ticket, else 1."
  @spec size(Ticket.t() | map()) :: pos_integer()
  def size(ticket), do: Map.get(ticket, :size) || 1

  @doc """
  Atomically claims a formed match: flips its tickets from queued to matched.

  Runs inside the sweep's cluster lock, before any lobby exists (the lobby is
  created outside the lock because `Lobbies` fires hooks and broadcasts, which
  must not run inside a transaction). The `status == queued` guard makes the
  claim atomic: if any ticket was cancelled or claimed since it was read,
  nothing is claimed and `:conflict` is returned.

  Answers the tickets as claimed. Their `matched_at` is this claim's mark:
  `requeue/1`, `discard/1` and `assign_lobby/2` write only tickets that still
  carry it, so a claim only ever undoes or names what it holds itself.
  """
  @spec claim([Ticket.t()]) :: {:ok, [Ticket.t()]} | :conflict
  def claim(tickets) do
    ids = Enum.map(tickets, & &1.id)
    now = DateTime.utc_now()

    {count, flipped} =
      queued()
      |> where([t], t.id in ^ids)
      |> select([t], t.id)
      |> Repo.update_all(
        set: [status: Constants.status_matched(), matched_at: now, updated_at: now]
      )

    claimed = Enum.map(tickets, &%{&1 | status: Constants.status_matched(), matched_at: now})

    if count == length(ids) do
      {:ok, claimed}
    else
      # Partial claim: put back only what this claim flipped, and let the next
      # tick retry. The others were claimed by someone else. Requeueing the
      # whole group flipped them back to queued while their sweep was seating
      # them, and the next sweep claimed them a second time.
      _ = requeue(Enum.filter(claimed, &(&1.id in flipped)))
      :conflict
    end
  end

  @doc "Returns claimed tickets to the queue (lobby creation failed)."
  @spec requeue([Ticket.t()], boolean()) :: :ok
  def requeue(tickets, notify? \\ false) do
    {_count, requeued} =
      tickets
      |> held_by_claim()
      |> select([t], map(t, [:id, :user_id, :match_params, :queued_at]))
      |> Repo.update_all(
        set: [
          status: Constants.status_queued(),
          matched_at: nil,
          updated_at: DateTime.utc_now()
        ]
      )

    # Told only when its player saw it leave (a failed accept): a claim
    # refused within a sweep, or a lobby that could not be made, put it back
    # before anyone knew.
    if notify?, do: Broadcast.ticket_queued(requeued, true), else: :ok
  end

  @doc """
  Cancels claimed tickets whose owner could not be seated in the lobby.
  Unlike `requeue/1` these do not go back in the queue — a user who cannot
  join a lobby (banned, already in one) would fail again on every tick.
  """
  @spec discard([Ticket.t()], String.t()) :: :ok
  def discard(tickets, reason \\ "unseated") do
    {_count, cancelled} =
      tickets
      |> held_by_claim()
      |> select([t], map(t, [:id, :user_id]))
      |> Repo.update_all(set: cancelled_fields())

    Broadcast.ticket_cancelled(cancelled, reason)
  end

  @doc """
  Associates claimed tickets with their created lobby: all of them, or none
  (`{:error, :not_found}`) when the lobby is gone or a ticket is no longer
  held by the claim that matched it.
  """
  @spec assign_lobby([Ticket.t()], Ecto.UUID.t()) :: :ok | {:error, :not_found}
  def assign_lobby(tickets, lobby_id) do
    # Only while the lobby is there, decided in the same statement: one deleted
    # since would break the foreign key, and the raise stopped every other match
    # in the sweep. And only tickets this match's claim still holds: a ticket
    # requeued from under it is someone else's now, and naming this lobby on it
    # sent its player to a match they were never seated in.
    Gamend.AfterCommit.transaction(fn ->
      {assigned, _} =
        tickets
        |> held_by_claim()
        |> where(exists(from(l in Gamend.Lobbies.Lobby, where: l.id == ^lobby_id, select: 1)))
        |> Repo.update_all(set: [match_id: lobby_id, updated_at: DateTime.utc_now()])

      if assigned != length(tickets), do: Repo.rollback(:not_found)
    end)
    |> case do
      {:ok, _} -> :ok
      {:error, :not_found} = gone -> gone
    end
  end

  # The tickets still held by the claim that answered them: matched at its
  # mark, with no lobby named yet. A ticket never claimed (no mark) is no one's.
  defp held_by_claim(tickets) do
    held =
      tickets
      |> Enum.reject(&is_nil(&1.matched_at))
      |> Enum.group_by(& &1.matched_at, & &1.id)
      |> Enum.reduce(dynamic([t], false), fn {at, ids}, held ->
        dynamic([t], ^held or (t.id in ^ids and t.matched_at == ^at))
      end)

    from(t in Ticket,
      where: ^held,
      where: t.status == ^Constants.status_matched() and is_nil(t.match_id)
    )
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

      {count, cancelled} =
        queued()
        |> where([t], t.id in ^ids or t.party_id in ^party_ids)
        |> select([t], map(t, [:id, :user_id]))
        |> Repo.update_all(set: cancelled_fields())

      Broadcast.ticket_cancelled(cancelled, CancelReason.offline())
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
