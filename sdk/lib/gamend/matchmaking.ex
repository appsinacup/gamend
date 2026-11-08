defmodule Gamend.Matchmaking do
  @moduledoc ~S"""
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


  **Note:** This is an SDK stub. Calling these functions will raise an error.
  The actual implementation runs on the Gamend.
  """

  @doc ~S"""
    Associates claimed tickets with their created lobby: all of them, or none
    (`{:error, :not_found}`) when the lobby is gone or a ticket is no longer
    held by the claim that matched it.
    
  """
  @spec assign_lobby([Gamend.Matchmaking.Ticket.t()], Ecto.UUID.t()) :: :ok | {:error, :not_found}
  def assign_lobby(_tickets, _lobby_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Matchmaking.assign_lobby/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Cancels the user's queued tickets. Returns how many were cancelled.
    
    A party queues as a unit, so it leaves as one: cancelling any member's ticket
    cancels the whole party's. Any member may do this — only the leader can queue,
    but nobody should be stuck in a queue they cannot leave.
    
    A match waiting for its accept is declined for the user (see *Accept*), so
    the others go back in the queue at once rather than at its deadline.
    
  """
  @spec cancel(Ecto.UUID.t()) :: non_neg_integer()
  def cancel(_user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Matchmaking.cancel/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Cancels one ticket by id, whoever owns it — for admins clearing a stuck
    ticket. Returns `{:error, :not_found}` for an unknown, malformed or
    already-resolved id.
    
  """
  @spec cancel_ticket(Ecto.UUID.t()) ::
          {:ok, Gamend.Matchmaking.Ticket.t()} | {:error, :not_found}
  def cancel_ticket(_ticket_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Matchmaking.cancel_ticket/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
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
  @spec claim([Gamend.Matchmaking.Ticket.t()]) ::
          {:ok, [Gamend.Matchmaking.Ticket.t()]} | :conflict
  def claim(_tickets) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Matchmaking.claim/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Counts tickets matching the same filters as `list_tickets/1`.
  """
  @spec count_tickets(keyword()) :: non_neg_integer()
  def count_tickets(_opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Matchmaking.count_tickets/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    The user's current queued ticket, or nil.
  """
  @spec current_ticket(Ecto.UUID.t()) :: Gamend.Matchmaking.Ticket.t() | nil
  def current_ticket(_user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Matchmaking.current_ticket/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Cancels claimed tickets whose owner could not be seated in the lobby.
    Unlike `requeue/1` these do not go back in the queue — a user who cannot
    join a lobby (banned, already in one) would fail again on every tick.
    
  """
  @spec discard([Gamend.Matchmaking.Ticket.t()], String.t()) :: :ok
  def discard(_tickets, _reason \\ "unseated") do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Matchmaking.discard/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Fetches a ticket by id, or nil when the id is unknown or malformed.
  """
  @spec get_ticket(Ecto.UUID.t()) :: Gamend.Matchmaking.Ticket.t() | nil
  def get_ticket(_ticket_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Matchmaking.get_ticket/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
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
  @spec join(Gamend.Accounts.User.t(), map(), pos_integer() | nil, pos_integer() | nil) ::
          {:ok, Gamend.Matchmaking.Ticket.t()} | {:error, Ecto.Changeset.t() | atom()}
  def join(_user, _match_params, _min_players \\ nil, _max_players \\ nil) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Matchmaking.join/4 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    All queued tickets grouped by `match_params`, oldest first within a group.
    
    Read straight from the database: the queue changes on every join and the
    sweep runs seconds apart, so caching here would only ever serve stale rows.
    
  """
  @spec list_queued_by_params() :: %{required(map()) => [Gamend.Matchmaking.Ticket.t()]}
  def list_queued_by_params() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        %{}

      _ ->
        raise "Gamend.Matchmaking.list_queued_by_params/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Lists tickets for the admin views, newest first.
    
    Options: `:status`, `:user_id`, `:page`, `:page_size`.
    
  """
  @spec list_tickets(keyword()) :: [Gamend.Matchmaking.Ticket.t()]
  def list_tickets(_opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Matchmaking.list_tickets/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
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
  def prune_offline() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Matchmaking.prune_offline/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Returns claimed tickets to the queue (lobby creation failed).
  """
  @spec requeue([Gamend.Matchmaking.Ticket.t()], boolean()) :: :ok
  def requeue(_tickets, _notify? \\ false) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Matchmaking.requeue/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Whether `tickets` can be one match: at most one lobby with other players in
    it, and no more players than the lobby it would be seated in has seats.
    
  """
  @spec seatable?([Gamend.Matchmaking.Ticket.t()]) :: boolean()
  def seatable?(_tickets) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :erlang.phash2(make_ref(), 2) == 0

      _ ->
        raise "Gamend.Matchmaking.seatable?/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    The players a ticket brings: its lobby's members for a backfill ticket, else 1.
  """
  @spec size(Gamend.Matchmaking.Ticket.t() | map()) :: pos_integer()
  def size(_ticket) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Matchmaking.size/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Queue statistics for the admin dashboard and the public stats endpoint:
    counts by status, plus the depth of each distinct queued `match_params`.
    
  """
  @spec stats() :: %{
          queued: non_neg_integer(),
          matched: non_neg_integer(),
          cancelled: non_neg_integer(),
          queues: [%{params: map(), waiting: non_neg_integer()}]
        }
  def stats() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Matchmaking.stats/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    The lobby a match is seated in: the one of its lobbies with other players
    in it, else its oldest ticket's. nil when no ticket fills a lobby (a new
    lobby is made). Reads `size` as `with_lobbies/1` set it.
    
  """
  @spec target_ticket([Gamend.Matchmaking.Ticket.t()]) :: Gamend.Matchmaking.Ticket.t() | nil
  def target_ticket(_tickets) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Matchmaking.target_ticket/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    `tickets` with each backfill ticket's lobby read: `size` its members,
    `capacity` its seats. A ticket whose holder no longer hosts the lobby it
    named fills nothing (`lobby_id` nil): it is seated as any other.
    
  """
  @spec with_lobbies([Gamend.Matchmaking.Ticket.t()]) :: [Gamend.Matchmaking.Ticket.t()]
  def with_lobbies(_tickets) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Matchmaking.with_lobbies/1 is a stub - only available at runtime on Gamend"
    end
  end
end
