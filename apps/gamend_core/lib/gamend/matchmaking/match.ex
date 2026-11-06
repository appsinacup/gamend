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

  A match whose tickets ask for an accept (`accept_timeout_ms`) is not seated
  here at first: `start/1` opens the accept check, and `accept_resolved/1`
  seats it once everyone accepted, or puts the ones who did back in the
  queue. A match with a backfill ticket is seated in that lobby (see
  `Gamend.Matchmaking`, *Backfill*).
  """

  require Logger

  import Ecto.Query

  alias Gamend.Accounts.User
  alias Gamend.Lobbies
  alias Gamend.Matchmaking
  alias Gamend.Matchmaking.Broadcast
  alias Gamend.Matchmaking.Constants
  alias Gamend.Matchmaking.Ticket
  alias Gamend.ReadyChecks
  alias Gamend.ReadyChecks.Check
  alias Gamend.ReadyChecks.Participant
  alias Gamend.Repo
  alias Gamend.Types

  @doc """
  A claimed match, begun: its accept check opened when its oldest ticket
  asks for one (`{:accepting, check_id}`), else seated at once (`create/1`).
  """
  @spec start([Types.matchmaking_ticket()]) ::
          {:ok, Ecto.UUID.t()} | {:accepting, Ecto.UUID.t()} | {:error, term()}
  def start(tickets) do
    case Enum.min_by(tickets, & &1.queued_at, DateTime) do
      %{accept_timeout_ms: ms} when is_integer(ms) and ms > 0 -> ask_accept(tickets, ms)
      _ -> create(tickets)
    end
  end

  defp ask_accept(tickets, ms) do
    first = hd(tickets)

    case ReadyChecks.open(:matchmaking, Enum.map(tickets, & &1.user_id),
           timeout_ms: ms,
           tickets: Map.new(tickets, &{&1.user_id, &1.id}),
           metadata: %{"match_params" => first.match_params}
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
  it passed or failed). Passed: the match is seated (`create/1`). Failed: the
  tickets of whoever accepted, or had not answered yet when someone declined,
  go back in the queue, keeping their place; whoever declined or let the
  deadline pass has their ticket cancelled. Tickets no longer held by the match (an admin
  cancelled one) are left alone; a check with no tickets is not
  matchmaking's.
  """
  @spec accept_resolved(Check.t()) :: {:ok, Ecto.UUID.t()} | :ok | {:error, term()}
  def accept_resolved(%Check{id: check_id, status: status}) do
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
        held |> Matchmaking.with_lobbies() |> create()

      true ->
        {still_in, out} = Enum.split_with(held, &(answers[&1.id] in ["ready", "pending"]))
        _ = Matchmaking.discard(out)
        _ = Matchmaking.requeue(still_in)
        Matchmaking.Worker.nudge()
        :ok
    end
  end

  @doc """
  Seats a claimed match: in its backfill ticket's lobby when it has one
  (`Gamend.Matchmaking.target_ticket/1`), else in a new hidden lobby, locked
  once everyone is in. Records the lobby on the tickets and broadcasts
  `match_found`.
  """
  @spec create([Types.matchmaking_ticket()]) :: {:ok, Ecto.UUID.t()} | {:error, term()}
  def create(tickets) do
    case Matchmaking.target_ticket(tickets) do
      nil -> create_lobby(tickets)
      target -> backfill(tickets, target)
    end
  end

  # ── Backfill: the match seated in a lobby its host queued from ────────────

  defp backfill(tickets, target) do
    lobby = Lobbies.get_lobby(target.lobby_id)

    if lobby && seated_in?(target.user_id, lobby.id) do
      {home, movers} = Enum.split_with(tickets, &seated_in?(&1.user_id, lobby.id))

      {seated, failed} =
        Enum.split_with(movers, &match?({:ok, _}, move(&1.user_id, lobby)))

      cond do
        failed == [] ->
          announce_match(tickets, lobby)

        seated == [] ->
          _ = Matchmaking.discard(failed)
          _ = Matchmaking.requeue(home)
          {:error, :join_failed}

        true ->
          Logger.warning(
            "matchmaking: #{length(failed)} of #{length(tickets)} could not join lobby #{lobby.id}"
          )

          _ = Matchmaking.discard(failed)
          announce_match(home ++ seated, lobby)
      end
    else
      # The lobby went, or its host left it, since the sweep read it: the
      # next sweep sees the tickets as they are now.
      _ = Matchmaking.requeue(tickets)
      {:error, :lobby_gone}
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

    with :ok <- leave_own(user, lobby.id) do
      # `bypass_hidden` and `bypass_lock`: the lobby's host queued to fill it,
      # which is the invitation; an id alone still lets nobody else in.
      Lobbies.join_lobby(user, lobby, %{bypass_hidden: true, bypass_lock: true})
    end
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

  defp create_lobby(tickets) do
    first = hd(tickets)

    case Lobbies.create_lobby(%{
           max_users: first.max_players,
           is_hidden: true,
           is_locked: false,
           hostless: true,
           metadata: %{match_params: first.match_params}
         }) do
      {:ok, lobby} ->
        seat_players(tickets, lobby)

      {:error, reason} ->
        Logger.warning("matchmaking: lobby creation failed: #{inspect(reason)}")
        _ = Matchmaking.requeue(tickets)
        {:error, reason}
    end
  end

  defp seat_players(tickets, lobby) do
    failed =
      Enum.reject(tickets, fn ticket ->
        # `bypass_hidden`: the match lobby is created hidden on purpose (players
        # are seated into it, never browse to it), and `join_lobby/2` refuses a
        # hidden lobby for everyone else — an id alone must not let an outsider
        # walk into someone's match.
        match?({:ok, _}, Lobbies.join_lobby(ticket.user, lobby.id, %{bypass_hidden: true}))
      end)

    if failed == [] do
      _ = Lobbies.update_lobby(lobby, %{is_locked: true})
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
