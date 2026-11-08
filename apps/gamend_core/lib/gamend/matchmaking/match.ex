defmodule Gamend.Matchmaking.Match do
  @moduledoc """
  Creates the lobby for a claimed match and notifies the players.

  Runs *outside* the sweep's cluster lock: `Lobbies.create_lobby/1` and
  `join_lobby/2` fire plugin hooks and broadcasts, which must never run
  inside a transaction. The tickets are already claimed (status `matched`),
  so no other node can pick them up meanwhile; on failure they are requeued
  and retried on the next tick.

  Errors return tuples instead of raising, so one bad match never aborts the
  rest of the sweep.

  The game answers where a match sits and whether its players are asked
  first (`matchmaking_seat_match/1`, `Gamend.MatchSeating`). A match that asks
  is not seated here at first: `start/1` opens the accept check, and
  `accept_resolved/1` seats it once everyone accepted, or puts the ones who
  did back in the queue. With no answer, a match with a backfill ticket is
  seated in that lobby (see `Gamend.Matchmaking`, *Backfill*).
  """

  require Logger

  import Ecto.Query

  alias Gamend.Accounts.User
  alias Gamend.Lobbies
  alias Gamend.Matchmaking
  alias Gamend.Matchmaking.Broadcast
  alias Gamend.Matchmaking.Constants
  alias Gamend.Matchmaking.Ticket
  alias Gamend.MatchSeating
  alias Gamend.Parties
  alias Gamend.ReadyChecks
  alias Gamend.ReadyChecks.Check
  alias Gamend.ReadyChecks.Participant
  alias Gamend.Repo
  alias Gamend.Types

  # The sweep starts its matches one after another, and a claimed ticket is
  # held for a minute (`Gamend.Matchmaking`): a game's answer must come well
  # inside that, not take the hooks' own default of a minute.
  @seat_hook_timeout_ms 5_000

  # Who a match seats is the game's or the queue's choice, and neither a
  # lobby's hidden flag nor its lock is about them.
  @seat_opts %{bypass_hidden: true, bypass_lock: true}

  # Lost to someone taking the seat first: not the player's doing, so they
  # keep their place in the queue.
  @no_room [:full, :not_enough_space]

  @doc """
  A claimed match, begun: the game says how (`matchmaking_seat_match/1`), then
  its accept check is opened if that asks for one (`{:accepting, check_id}`),
  else it is seated at once (`seat/2`). A refusal, a hook that fails or runs
  past its time puts the tickets back in the queue.
  """
  @spec start([Types.matchmaking_ticket()]) ::
          {:ok, Ecto.UUID.t()} | {:accepting, Ecto.UUID.t()} | {:error, term()}
  def start(tickets) do
    case Gamend.Hooks.internal_call(:matchmaking_seat_match, [tickets],
           timeout_ms: @seat_hook_timeout_ms
         ) do
      {:ok, %MatchSeating{} = seating} ->
        begin(tickets, seating)

      {:ok, :default} ->
        begin(tickets, MatchSeating.default())

      {:error, reason} ->
        Logger.warning("matchmaking: seat hook gave no seating: #{inspect(reason)}")
        _ = Matchmaking.requeue(tickets)
        {:error, reason}
    end
  end

  defp begin(tickets, %MatchSeating{accept_timeout_ms: ms} = seating) when is_integer(ms),
    do: ask_accept(tickets, ms, seating)

  defp begin(tickets, %MatchSeating{} = seating), do: seat(tickets, seating)

  defp ask_accept(tickets, ms, seating) do
    first = hd(tickets)

    case ReadyChecks.open(:matchmaking, Enum.map(tickets, & &1.user_id),
           timeout_ms: ms,
           tickets: Map.new(tickets, &{&1.user_id, &1.id}),
           metadata: %{"match_params" => first.match_params},
           seating: MatchSeating.dump(seating)
         ) do
      {:ok, check} ->
        {:accepting, check.id}

      {:error, reason} ->
        # Someone is answering another check in the same lane (a lobby's
        # ready-up): the next sweep tries again.
        Logger.warning("matchmaking: accept check not opened: #{inspect(reason)}")
        _ = Matchmaking.requeue(tickets)
        {:error, reason}
    end
  end

  @doc """
  A matchmaking accept check resolved (called by `Gamend.ReadyChecks` once
  it passed or failed). Passed: the match is seated (`seat/2`). Failed: the
  tickets of whoever accepted, or had not answered yet when someone declined,
  go back in the queue, keeping their place; whoever declined or let the
  deadline pass has their ticket cancelled. Tickets no longer held by the match (an admin
  cancelled one) are left alone; a check with no tickets is not
  matchmaking's.
  """
  @spec accept_resolved(Check.t()) :: {:ok, Ecto.UUID.t()} | :ok | {:error, term()}
  def accept_resolved(%Check{id: check_id, status: status} = check) do
    answers =
      from(p in Participant,
        where: p.ready_check_id == ^check_id and not is_nil(p.ticket_id),
        select: {p.ticket_id, p.state}
      )
      |> Repo.all()
      |> Map.new()

    held =
      from(t in Ticket,
        where: t.id in ^Map.keys(answers),
        where: t.status == ^Constants.status_matched() and is_nil(t.match_id),
        preload: :user
      )
      |> Repo.all()

    cond do
      answers == %{} ->
        :ok

      status == "passed" and length(held) == map_size(answers) ->
        held |> Matchmaking.with_lobbies() |> seat(MatchSeating.load(check.seating))

      true ->
        {still_in, out} = Enum.split_with(held, &(answers[&1.id] in ["ready", "pending"]))
        _ = Matchmaking.discard(out, check.reason || "declined")
        _ = Matchmaking.requeue(still_in, true)
        Matchmaking.Worker.nudge()
        :ok
    end
  end

  @doc """
  Seats a claimed match where `seating` says: a lobby the game named, a new
  lobby with the game's settings, or by default its backfill ticket's lobby
  when it has one (`Gamend.Matchmaking.target_ticket/1`), else a new hidden,
  locked one. Records the lobby on the tickets and broadcasts `match_found`.
  """
  @spec seat([Types.matchmaking_ticket()], MatchSeating.t()) ::
          {:ok, Ecto.UUID.t()} | {:error, term()}
  def seat(tickets, %MatchSeating{lobby_id: lobby_id}) when is_binary(lobby_id) do
    fill(tickets, Lobbies.get_lobby(lobby_id))
  end

  def seat(tickets, %MatchSeating{lobby: nil} = seating) do
    case Matchmaking.target_ticket(tickets) do
      nil -> create_lobby(tickets, seating)
      target -> backfill(tickets, target)
    end
  end

  def seat(tickets, %MatchSeating{} = seating), do: create_lobby(tickets, seating)

  # ── Filling a lobby that exists ───────────────────────────────────────────

  defp backfill(tickets, target) do
    lobby = Lobbies.get_lobby(target.lobby_id)

    # Its host left it since the sweep read it: the next sweep sees the
    # tickets as they are now.
    fill(tickets, if(lobby && seated_in?(target.user_id, lobby.id), do: lobby))
  end

  defp fill(tickets, nil) do
    _ = Matchmaking.requeue(tickets)
    {:error, :lobby_gone}
  end

  defp fill(tickets, lobby) do
    {home, movers} = Enum.split_with(tickets, &seated_in?(&1.user_id, lobby.id))

    # A party goes in whole or not at all, so it is one entry here.
    entries = movers |> Enum.group_by(&(&1.party_id || &1.id)) |> Map.values()
    {seated, failed} = entries |> Enum.map(&{&1, enter(&1, lobby)}) |> split_entered()
    {no_room, refused} = Enum.split_with(failed, fn {_group, reason} -> reason in @no_room end)

    _ = refused |> group_tickets() |> Matchmaking.discard()
    _ = no_room |> group_tickets() |> Matchmaking.requeue()

    cond do
      failed == [] ->
        announce_match(tickets, lobby)

      seated == [] ->
        _ = Matchmaking.requeue(home)
        {:error, :join_failed}

      true ->
        Logger.warning(
          "matchmaking: #{length(failed)} of #{length(entries)} could not join lobby #{lobby.id}"
        )

        announce_match(home ++ List.flatten(seated), lobby)
    end
  end

  defp split_entered(results) do
    Enum.reduce(results, {[], []}, fn
      {group, {:ok, _}}, {seated, failed} -> {[group | seated], failed}
      {group, {:error, reason}}, {seated, failed} -> {seated, [{group, reason} | failed]}
    end)
  end

  defp group_tickets(failed), do: Enum.flat_map(failed, fn {group, _reason} -> group end)

  defp enter([%{party_id: nil, user_id: user_id}], lobby), do: move(user_id, lobby)

  defp enter([%{party_id: party_id} | _], lobby) do
    with %Parties.Party{leader_id: leader_id} <- Parties.get_party(party_id),
         %User{} = leader <- Repo.get(User, leader_id) do
      Parties.join_lobby_with_party(leader, lobby.id, @seat_opts)
    else
      nil -> {:error, :not_found}
    end
  end

  defp seated_in?(user_id, lobby_id) do
    Repo.exists?(from(u in User, where: u.id == ^user_id and u.lobby_id == ^lobby_id))
  end

  # A player queued from a lobby of their own alone leaves it (core deletes an
  # empty lobby) and joins the match's. One with company there stays put: the
  # matcher never pairs two lobbies with players in them.
  defp move(user_id, lobby) do
    user = Repo.get(User, user_id)

    with :ok <- room_left(lobby),
         :ok <- leave_own(user, lobby.id) do
      Lobbies.join_lobby(user, lobby, @seat_opts)
    end
  end

  # Asked before the player leaves their own lobby, which cannot be undone. A
  # refusal only: the seat is decided by `join_lobby/3`, under the lobby's lock.
  defp room_left(lobby) do
    seated = Repo.aggregate(from(u in User, where: u.lobby_id == ^lobby.id), :count)
    if seated < lobby.max_users, do: :ok, else: {:error, :full}
  end

  defp leave_own(nil, _lobby_id), do: {:error, :not_found}
  defp leave_own(%User{lobby_id: nil}, _lobby_id), do: :ok

  defp leave_own(%User{lobby_id: own} = user, _lobby_id) do
    alone? = not Repo.exists?(from(u in User, where: u.lobby_id == ^own and u.id != ^user.id))

    if alone? do
      with {:ok, _} <- Lobbies.leave_lobby(user), do: :ok
    else
      {:error, :already_in_lobby}
    end
  end

  # ── A new lobby for the match ─────────────────────────────────────────────

  defp create_lobby(tickets, seating) do
    case tickets
         |> hd()
         |> then(&MatchSeating.lobby_attrs(seating, &1))
         |> Lobbies.create_lobby() do
      {:ok, lobby} ->
        seat_players(tickets, lobby, seating)

      {:error, reason} ->
        Logger.warning("matchmaking: lobby creation failed: #{inspect(reason)}")
        _ = Matchmaking.requeue(tickets)
        {:error, reason}
    end
  end

  defp seat_players(tickets, lobby, seating) do
    failed =
      Enum.reject(tickets, fn ticket ->
        # A host the game named was seated when the lobby was created. The
        # lobby is born hidden and locked, and only `@seat_opts` gets past
        # either: an id alone must not let an outsider walk into someone's
        # match.
        ticket.user_id == lobby.host_id or
          match?({:ok, _}, Lobbies.join_lobby(ticket.user, lobby.id, @seat_opts))
      end)

    if failed == [] do
      _ = if MatchSeating.unlock?(seating), do: Lobbies.update_lobby(lobby, %{is_locked: false})
      announce_match(tickets, lobby)
    else
      # A player could not be seated (banned, already in a lobby, ...). Drop
      # the half-built lobby, cancel the unseatable tickets, and requeue the
      # rest so they simply wait for the next tick.
      Logger.warning(
        "matchmaking: #{length(failed)} of #{length(tickets)} joins failed; dropping lobby #{lobby.id}"
      )

      _ = Lobbies.delete_lobby(lobby)
      failed_ids = MapSet.new(failed, & &1.id)

      _ = Matchmaking.discard(failed)
      _ = tickets |> Enum.reject(&MapSet.member?(failed_ids, &1.id)) |> Matchmaking.requeue()

      {:error, :join_failed}
    end
  end

  # The lobby was deleted after its players were seated (an admin, retention):
  # there is no match to announce, so the tickets wait for the next sweep.
  defp announce_match(tickets, lobby) do
    case Matchmaking.assign_lobby(tickets, lobby.id) do
      :ok ->
        Broadcast.match_found(tickets, lobby.id)

        Gamend.Async.run(fn ->
          Gamend.Hooks.internal_call(:after_matchmaking_matched, [tickets, lobby.id])
        end)

        {:ok, lobby.id}

      {:error, :not_found} = gone ->
        _ = Matchmaking.requeue(tickets)
        gone
    end
  end
end
