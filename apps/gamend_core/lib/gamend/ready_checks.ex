defmodule Gamend.ReadyChecks do
  @moduledoc """
  Ready checks: *these players must each answer before this proceeds*.

  One primitive, two kinds — the only differences are what a "no" means and
  whether an answer can be taken back:

  | | `"accept"` | `"ready"` |
  | --- | --- | --- |
  | Answer | one-shot, irrevocable | a toggle |
  | A "no" | fails the check for everyone | leaves it pending |
  | Deadline | mandatory | optional |
  | On timeout | fails | fails, naming who stalled |

  `"ready"` is the lobby's ready-up and the party's standing ready board;
  `"accept"` is matchmaking's match confirmation (see
  the moduledoc below).

  ## Two lanes

  A player can be in at most one open check *per lane*: the match lane (lobby
  ready or matchmaking accept — one match at a time) and the party lane. The
  lanes are independent, so a party's standing board never blocks the party's
  lobby from opening its own check.

  ## What core does *not* do

  A failed check kicks nobody, deletes no lobby and moves no lobby state. Core
  records who did not answer (`not_ready/1`); the host — or the game, in
  `after_ready_check_failed` — decides what that is worth.

  ## Usage

      {:ok, check} = ReadyChecks.open(lobby, member_ids, opened_by: host.id)
      {:ok, check} = ReadyChecks.respond(user, true)
      ReadyChecks.passed?(lobby)

  ## Concurrency

  Answering is a single-row write, so no two players can lose each other's
  flag. *Evaluating* the result is the part that races: two players answering
  at once can each count the other as still pending, and nobody passes. So
  `respond/3` holds a per-check advisory lock (`:ready_check`) around
  write-then-evaluate. Hooks and broadcasts fire after the lock is released —
  never inside the transaction.
  """

  import Ecto.Query

  alias Gamend.Accounts.User
  alias Gamend.Limits
  alias Gamend.Lobbies.Lobby
  alias Gamend.Parties.Party
  alias Gamend.ReadyChecks.Check
  alias Gamend.ReadyChecks.ExpiryWorker
  alias Gamend.ReadyChecks.Participant
  alias Gamend.Repo

  @type subject :: Lobby.t() | Party.t() | :matchmaking
  @type scope :: :match | :party
  @type answer :: boolean()

  # ── Opening ───────────────────────────────────────────────────────────────

  @doc """
  Opens a check over `user_ids` and notifies them.

  `subject` is a `%Lobby{}` or `%Party{}` (kind `"ready"`) or `:matchmaking`
  (kind `"accept"`). For a lobby or a party, `user_ids` may be `:members`:
  every member, read again under the subject's lock as the check is written,
  so a member who joins or leaves while it opens is on the board exactly when
  they are in the lobby or party. `before_ready_check_open` sees the members
  as read before that lock. Options:

    * `:kind` — override the kind implied by the subject
    * `:timeout_ms` — answering window; `nil` leaves a `"ready"` check open
      until it passes or is cancelled. Defaults to `ready_check_timeout_ms`.
    * `:opened_by` — the user who asked for it; they are pre-marked ready,
      since clicking the button is their answer
    * `:ready` — user ids to pre-mark ready (bots, an auto-ready mode)
    * `:tickets` — `%{user_id => ticket_id}` for matchmaking checks
    * `:metadata` — game payload echoed to clients (match params, mode)

  Fails with `{:error, :already_pending}` when the subject already has an open
  check or any player is in one in the same lane, `{:error, :no_participants}`,
  and `{:error, :too_many_participants}` past `max_ready_check_participants`.
  """
  @spec open(subject(), [Ecto.UUID.t()] | :members, keyword()) ::
          {:ok, Check.t()} | {:error, term()}
  def open(subject, user_ids, opts \\ []) do
    roster = roster(subject, user_ids)

    with :ok <- validate_participants(roster),
         :ok <- ensure_none_pending(subject, roster),
         {:ok, attrs} <- run_open_hook(subject, roster, opts),
         {:ok, check} <- insert_check(subject, user_ids, roster, attrs, opts) do
      check = Repo.preload(check, :participants)
      broadcast(check, "ready_check_started")
      schedule_expiry(check)
      {:ok, check}
    end
  end

  @doc """
  Resets the subject's board: quietly cancels its pending check (no failed
  event, no hook — the fresh `ready_check_started` replaces it on clients) and
  opens a new one over `user_ids`.

  The one verb behind every "answers are stale now" moment: a match ended
  (rematch needs a fresh board), the game mode changed, a member joined a
  party whose board had already resolved, or the host wants everyone to
  re-confirm on a deadline_at ("force ready"). Same options as `open/3`.
  """
  @spec reset(subject(), [Ecto.UUID.t()] | :members, keyword()) ::
          {:ok, Check.t()} | {:error, term()}
  def reset(subject, user_ids, opts \\ []) do
    case pending_for_subject(subject) do
      nil -> :ok
      check -> quiet_cancel(check)
    end

    open(subject, user_ids, opts)
  end

  # Resolves a pending check as cancelled/"reset" without running effects.
  # Deliberately no broadcast and no `after_ready_check_failed`: a reset is not
  # a failure, and the caller immediately opens the replacement.
  defp quiet_cancel(check) do
    result =
      Gamend.Lock.serialize(:ready_check, check.id, fn ->
        case reload_pending(check) do
          {:ok, check} -> resolve(check, "cancelled", "reset")
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    with {:ok, _} <- result, do: :ok
  end

  defp validate_participants([]), do: {:error, :no_participants}

  defp validate_participants(user_ids) do
    if length(user_ids) > Limits.get(:max_ready_check_participants) do
      {:error, :too_many_participants}
    else
      :ok
    end
  end

  # "One open check per player per lane" spans two tables, so it cannot be an
  # index — a player who has already answered still belongs to the open check.
  # The lane filter keeps a party's standing board from blocking that party's
  # lobby check (and vice versa).
  defp ensure_none_pending(subject, user_ids) do
    query =
      from(p in Participant,
        join: c in Check,
        on: c.id == p.ready_check_id,
        where: p.user_id in ^user_ids and c.status == "pending"
      )

    query =
      case lane(subject) do
        :party -> where(query, [p, c], not is_nil(c.party_id))
        :match -> where(query, [p, c], is_nil(c.party_id))
      end

    if Repo.exists?(query), do: {:error, :already_pending}, else: :ok
  end

  defp lane(%Party{}), do: :party
  defp lane(_subject), do: :match

  defp run_open_hook(subject, user_ids, opts) do
    case Gamend.Hooks.internal_call(:before_ready_check_open, [subject, user_ids]) do
      {:ok, _} -> {:ok, opts}
      {:error, reason} -> {:error, {:hook_rejected, reason}}
    end
  end

  # The ids given, or for `:members` the subject's members as they are now:
  # what the early refusals and the hook see. `insert_check/5` reads the
  # members again under the subject's lock.
  defp roster(subject, :members), do: member_ids(subject)

  defp roster(_subject, user_ids) when is_list(user_ids),
    do: user_ids |> Enum.filter(&is_binary/1) |> Enum.uniq()

  defp member_ids(%Lobby{id: id}),
    do: Repo.all(from(u in User, where: u.lobby_id == ^id, order_by: u.inserted_at, select: u.id))

  defp member_ids(%Party{id: id}),
    do: Repo.all(from(u in User, where: u.party_id == ^id, order_by: u.inserted_at, select: u.id))

  defp insert_check(subject, requested, roster, _attrs, opts) do
    kind = Keyword.get(opts, :kind, default_kind(subject))
    opened_by = Keyword.get(opts, :opened_by)
    tickets = Keyword.get(opts, :tickets, %{})

    # The opener already answered by opening; bots are answered for by the game.
    pre_ready = MapSet.new(List.wrap(Keyword.get(opts, :ready, [])) ++ List.wrap(opened_by))

    check_attrs = %{
      kind: kind,
      status: "pending",
      lobby_id: lobby_id(subject),
      party_id: party_id(subject),
      deadline_at: deadline_for(opts),
      opened_by: opened_by,
      metadata: Keyword.get(opts, :metadata, %{})
    }

    # The lobby or party was read before this; deleted since, the check would
    # point at nothing, and the database refuses it.
    Repo.rescue_foreign_key(:not_found, fn ->
      within_subject(subject, fn ->
        roster = if requested == :members, do: member_ids(subject), else: roster

        with :ok <- validate_participants(roster),
             :ok <- ensure_subject_free(subject),
             :ok <- ensure_none_pending(subject, roster),
             {:ok, check} <- %Check{} |> Check.changeset(check_attrs) |> Repo.insert(),
             :ok <- insert_participants(check, roster, pre_ready, tickets) do
          check
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end)
  end

  # A lobby's or party's check is written under the subject's own lock, the
  # one every seat and every leave takes. A join then lands either before the
  # open, which reads the joiner among the members, or after it, when the
  # join's `add_member/2` finds the check. The members used to be read before
  # any lock: one who left in between stayed on the board, which then could
  # never pass, and one who joined was left off it. Two opens for one subject
  # queue here too, and the second answers `:already_pending`.
  defp within_subject(%Lobby{id: id}, fun), do: Gamend.Lock.serialize(:lobby, id, fun)
  defp within_subject(%Party{id: id}, fun), do: Gamend.Lock.serialize(:party, id, fun)
  defp within_subject(:matchmaking, fun), do: Gamend.AfterCommit.transaction(fun)

  defp ensure_subject_free(subject) do
    if pending_for_subject(subject), do: {:error, :already_pending}, else: :ok
  end

  defp insert_participants(check, user_ids, pre_ready, tickets) do
    now = DateTime.utc_now(:second)

    Enum.reduce_while(user_ids, :ok, fn user_id, _acc ->
      ready? = MapSet.member?(pre_ready, user_id)

      attrs = %{
        ready_check_id: check.id,
        user_id: user_id,
        ticket_id: Map.get(tickets, user_id),
        state: if(ready?, do: "ready", else: "pending"),
        responded_at: if(ready?, do: now)
      }

      case %Participant{} |> Participant.changeset(attrs) |> Repo.insert() do
        {:ok, _participant} -> {:cont, :ok}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end

  defp default_kind(%Lobby{}), do: "ready"
  defp default_kind(%Party{}), do: "ready"
  defp default_kind(:matchmaking), do: "accept"

  defp lobby_id(%Lobby{id: id}), do: id
  defp lobby_id(_subject), do: nil

  defp party_id(%Party{id: id}), do: id
  defp party_id(_subject), do: nil

  defp pending_for_subject(%Lobby{id: id}), do: pending_for_lobby(id)
  defp pending_for_subject(%Party{id: id}), do: pending_for_party(id)
  defp pending_for_subject(:matchmaking), do: nil

  # An explicit `timeout_ms: nil` means "no deadline_at" whatever the kind; the
  # changeset then rejects it for an accept check, rather than this quietly
  # substituting a default the caller did not ask for.
  defp deadline_for(opts) do
    case Keyword.fetch(opts, :timeout_ms) do
      {:ok, nil} -> nil
      {:ok, ms} when is_integer(ms) and ms > 0 -> deadline_in(ms)
      _ -> deadline_in(Limits.get(:ready_check_timeout_ms))
    end
  end

  defp deadline_in(ms), do: DateTime.utc_now(:second) |> DateTime.add(ms, :millisecond)

  # ── Answering ─────────────────────────────────────────────────────────────

  @doc """
  Records the caller's answer to their open check in `scope` and re-evaluates
  it.

  `scope` is `:match` (the lobby ready-up or matchmaking accept — the default)
  or `:party` (the party's standing board): a player can hold one open check
  in each lane, so the answer needs to say which one it is for.

  `true` is "ready"/"accept"; `false` is "not ready"/"decline". In an `accept`
  check a decline fails the whole check; in a `ready` check it just leaves the
  check pending and can be taken back.

  A `ready` board that ran out of time is still answerable: the deadline
  passing is the weakest kind of no — nobody refused, the clock did — and the
  board is still the one on everyone's screen. A late yes lands like any other
  and passes the board if it was the last one missing. (An `accept` check is
  not: its timeout has already released the tickets and re-queued everyone.)

  Returns the check as it stands after the answer. Fails with
  `{:error, :no_open_check}` and, for an `accept` check the caller already
  answered, `{:error, :not_revocable}`.
  """
  @spec respond(User.t() | Ecto.UUID.t(), answer(), scope()) ::
          {:ok, Check.t()} | {:error, term()}
  def respond(user, ready?, scope \\ :match) when is_boolean(ready?) do
    user_id = user_id(user)

    case answerable_for_user(user_id, scope) do
      nil -> {:error, :no_open_check}
      check -> write_answer(check, user_id, ready?)
    end
  end

  # The newest check in the lane, whatever became of it, and then only if it
  # can still take an answer. Newest-of-all rather than newest-answerable, so
  # anything that supersedes a timed-out board buries it: a reset opens a live
  # one to answer instead, and a cancel means there is nothing to answer at
  # all — neither should hand the reader back a board from before it.
  defp answerable_for_user(user_id, scope) do
    from(c in Check,
      join: p in Participant,
      on: p.ready_check_id == c.id,
      where: p.user_id == ^user_id,
      order_by: [desc: c.inserted_at, desc: c.id],
      limit: 1,
      preload: [:participants]
    )
    |> scope_filter(scope)
    |> Repo.one()
    |> case do
      %Check{status: "pending"} = check -> check
      %Check{kind: "ready", status: "failed", reason: "timeout"} = check -> check
      _ -> nil
    end
  end

  @doc """
  Answers on behalf of a member — for bots and AI-controlled players, which
  cannot press anything.

  Server-side only: this is in `internal_hooks()`, so a client cannot reach it
  over RPC and mark someone else ready.
  """
  @spec answer_for(Check.t(), Ecto.UUID.t(), answer()) :: {:ok, Check.t()} | {:error, term()}
  def answer_for(%Check{} = check, user_id, ready?) when is_boolean(ready?) do
    write_answer(check, user_id, ready?)
  end

  defp write_answer(check, user_id, ready?) do
    result =
      Gamend.Lock.serialize(:ready_check, check.id, fn ->
        with {:ok, check} <- reload_answerable(check),
             {:ok, participant} <- fetch_participant(check, user_id),
             :ok <- ensure_revocable(check, participant),
             {:ok, _participant} <- put_state(participant, answer_state(ready?)) do
          evaluate(check)
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    case result do
      {:ok, {check, effects}} -> {:ok, run_effects(check, effects)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp answer_state(true), do: "ready"
  defp answer_state(false), do: "declined"

  defp reload_pending(%Check{id: id}) do
    case Repo.get_uuid(Check, id) do
      %Check{status: "pending"} = check -> {:ok, check}
      %Check{} -> {:error, :already_resolved}
      nil -> {:error, :no_open_check}
    end
  end

  # As `reload_pending/1`, plus the one resolved state an answer still means
  # something in: a `ready` board that timed out. Cancelled boards stay shut —
  # someone called those off on purpose — and so do `accept` checks.
  defp reload_answerable(%Check{id: id}) do
    case Repo.get_uuid(Check, id) do
      %Check{status: "pending"} = check -> {:ok, check}
      %Check{kind: "ready", status: "failed", reason: "timeout"} = check -> {:ok, check}
      %Check{} -> {:error, :already_resolved}
      nil -> {:error, :no_open_check}
    end
  end

  defp fetch_participant(check, user_id) do
    Participant
    |> where([p], p.ready_check_id == ^check.id and p.user_id == ^user_id)
    |> Repo.one()
    |> case do
      nil -> {:error, :not_a_participant}
      participant -> {:ok, participant}
    end
  end

  # An accept is a commitment: you cannot un-accept a match other players are
  # already waiting on. A ready toggles freely.
  defp ensure_revocable(%Check{kind: "accept"}, %Participant{state: state})
       when state != "pending",
       do: {:error, :not_revocable}

  defp ensure_revocable(_check, _participant), do: :ok

  defp put_state(participant, state) do
    participant
    |> Participant.changeset(%{state: state, responded_at: DateTime.utc_now(:second)})
    |> Repo.update()
  end

  # ── Evaluation ────────────────────────────────────────────────────────────

  # Runs inside the lock. Returns the check plus the effects to run once the
  # transaction has committed — hooks and broadcasts must never fire in here.
  defp evaluate(check) do
    states = participant_states(check)

    cond do
      Enum.all?(states, &(&1 == "ready")) ->
        resolve(check, "passed", nil)

      check.kind == "accept" and Enum.any?(states, &(&1 == "declined")) ->
        resolve(check, "failed", "declined")

      true ->
        {check, [:updated]}
    end
  end

  defp resolve(check, status, reason) do
    {:ok, check} =
      check
      |> Check.changeset(%{
        status: status,
        reason: reason,
        resolved_at: DateTime.utc_now(:second)
      })
      |> Repo.update()

    {check, [resolution_effect(status)]}
  end

  defp resolution_effect("passed"), do: :passed

  # A cancelled check is a failed one from a client's point of view: the same
  # event, carrying "cancelled" as the reason.
  defp resolution_effect(status) when status in ["failed", "cancelled"], do: :failed

  defp participant_states(check) do
    Participant
    |> where([p], p.ready_check_id == ^check.id)
    |> select([p], p.state)
    |> Repo.all()
  end

  defp run_effects(check, effects) do
    check = Repo.preload(check, :participants, force: true)

    Enum.each(effects, fn
      :updated ->
        broadcast(check, "ready_check_updated")

      :passed ->
        broadcast(check, "ready_check_passed")
        defer(fn -> Gamend.Hooks.internal_call(:after_ready_check_passed, [check]) end)

      :failed ->
        broadcast(check, "ready_check_failed")

        defer(fn ->
          Gamend.Hooks.internal_call(:after_ready_check_failed, [
            check,
            check.reason,
            not_ready(check)
          ])
        end)
    end)

    check
  end

  defp defer(fun), do: Gamend.Async.run(fun)

  # ── Membership changes ────────────────────────────────────────────────────

  @doc """
  Drops a member from the lobby's open check and re-evaluates it.

  Called when someone leaves or is kicked: kicking the one player who never
  answered is a legitimate way to pass a check.
  """
  @spec remove_member(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok
  def remove_member(lobby_id, user_id) when is_binary(lobby_id) and is_binary(user_id) do
    do_remove_member(pending_for_lobby(lobby_id), user_id)
  end

  @doc "Drops a member from the party's open check and re-evaluates it."
  @spec remove_party_member(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok
  def remove_party_member(party_id, user_id) when is_binary(party_id) and is_binary(user_id) do
    do_remove_member(pending_for_party(party_id), user_id)
  end

  defp do_remove_member(nil, _user_id), do: :ok

  defp do_remove_member(check, user_id) do
    result =
      Gamend.Lock.serialize(:ready_check, check.id, fn ->
        # Re-read inside the lock, as `cancel/2`, `expire/1` and
        # `write_answer/2` all do.
        #
        # This path used the pre-lock struct and `resolve/3` writes
        # unconditionally, so a removal racing the expiry worker could take an
        # already-failed check, re-evaluate the remaining answers, and overwrite
        # it as `passed` — firing the success hook for a check that had already
        # fired the failure hook, and starting a match the game had torn down.
        case reload_pending(check) do
          {:ok, check} ->
            Participant
            |> where([p], p.ready_check_id == ^check.id and p.user_id == ^user_id)
            |> Repo.delete_all()

            case remaining_count(check) do
              0 -> resolve(check, "cancelled", "cancelled")
              _ -> evaluate(check)
            end

          {:error, reason} ->
            Repo.rollback(reason)
        end
      end)

    with {:ok, {check, effects}} <- result, do: run_effects(check, effects)
    :ok
  end

  @doc """
  Adds a member to the lobby's open check, if there is one.

  Call it inside the transaction that seats them, under the lobby's lock, as
  `Gamend.Lobbies` and `Gamend.Parties` do: the check then either takes the
  seat before it counts the next answer, or passed before the seat existed.
  """
  @spec add_member(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok
  def add_member(lobby_id, user_id) when is_binary(lobby_id) and is_binary(user_id) do
    do_add_member(pending_for_lobby(lobby_id), user_id)
  end

  @doc "Adds a member to the party's open check, if there is one. As `add_member/2`."
  @spec add_party_member(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok
  def add_party_member(party_id, user_id) when is_binary(party_id) and is_binary(user_id) do
    do_add_member(pending_for_party(party_id), user_id)
  end

  defp do_add_member(nil, _user_id), do: :ok

  # Under the check's lock, re-read, as an answer is. This ran after the join
  # had committed and wrote unconditionally: a last answer in between passed
  # the check without the member who had just joined, and the insert then put
  # them, pending, into a check already passed, and announced it.
  #
  # Nothing in here rolls back. It runs inside the seat's transaction, and a
  # rollback there would undo the seat with it; a check that resolved first
  # just takes no one.
  defp do_add_member(check, user_id) do
    Gamend.Lock.serialize(:ready_check, check.id, fn ->
      with {:ok, check} <- reload_pending(check),
           {:error, :not_a_participant} <- fetch_participant(check, user_id),
           {:ok, _participant} <-
             %Participant{}
             |> Participant.changeset(%{
               ready_check_id: check.id,
               user_id: user_id,
               state: "pending"
             })
             |> Repo.insert() do
        {check, [:updated]}
      else
        _resolved_or_present -> :unchanged
      end
    end)
    |> case do
      {:ok, {check, effects}} -> _ = run_effects(check, effects)
      _unchanged -> :ok
    end

    :ok
  end

  defp remaining_count(check) do
    Participant |> where([p], p.ready_check_id == ^check.id) |> Repo.aggregate(:count, :id)
  end

  # ── Cancelling and expiry ─────────────────────────────────────────────────

  @doc "Cancels a pending check — the host called it off, or the subject went away."
  @spec cancel(Check.t(), String.t()) ::
          {:ok, Check.t()} | {:error, :already_resolved | :no_open_check}
  def cancel(%Check{} = check, reason \\ "cancelled") do
    result =
      Gamend.Lock.serialize(:ready_check, check.id, fn ->
        case reload_pending(check) do
          {:ok, check} -> resolve(check, "cancelled", reason)
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    case result do
      {:ok, {check, effects}} -> {:ok, run_effects(check, effects)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Cancels the lobby's pending check, if it has one.

  `{:error, :already_resolved}` when it passed or failed before the cancel
  took its lock (or `:no_open_check` when it went with its lobby): it was
  read pending, and the cancel did not happen.
  """
  @spec cancel_for_lobby(Ecto.UUID.t()) :: :ok | {:error, :already_resolved | :no_open_check}
  def cancel_for_lobby(lobby_id) when is_binary(lobby_id) do
    case pending_for_lobby(lobby_id) do
      nil -> :ok
      check -> with {:ok, _} <- cancel(check), do: :ok
    end
  end

  @doc "Cancels the party's pending check, if it has one. As `cancel_for_lobby/1`."
  @spec cancel_for_party(Ecto.UUID.t()) :: :ok | {:error, :already_resolved | :no_open_check}
  def cancel_for_party(party_id) when is_binary(party_id) do
    case pending_for_party(party_id) do
      nil -> :ok
      check -> with {:ok, _} <- cancel(check), do: :ok
    end
  end

  @doc """
  Fails every pending check whose deadline_at has passed.

  Each still-unanswered participant becomes `timed_out`. Returns how many
  checks were expired. Idempotent, so the durable expiry job and the
  matchmaking sweep's backstop can both run it.
  """
  @spec expire_due(DateTime.t()) :: non_neg_integer()
  def expire_due(now \\ DateTime.utc_now()) do
    Check
    |> where([c], c.status == "pending" and not is_nil(c.deadline_at) and c.deadline_at <= ^now)
    |> Repo.all()
    |> Enum.count(&(expire(&1) == :ok))
  end

  @doc "Fails one check on its deadline_at. A no-op if it already resolved."
  @spec expire(Check.t()) :: :ok | :noop
  def expire(%Check{} = check) do
    result =
      Gamend.Lock.serialize(:ready_check, check.id, fn ->
        case reload_pending(check) do
          {:ok, check} ->
            Participant
            |> where([p], p.ready_check_id == ^check.id and p.state == "pending")
            |> Repo.update_all(set: [state: "timed_out", updated_at: DateTime.utc_now(:second)])

            resolve(check, "failed", "timeout")

          {:error, reason} ->
            Repo.rollback(reason)
        end
      end)

    case result do
      {:ok, {check, effects}} ->
        _ = run_effects(check, effects)
        :ok

      {:error, _reason} ->
        :noop
    end
  end

  defp schedule_expiry(%Check{deadline_at: nil}), do: :ok

  defp schedule_expiry(%Check{id: id, deadline_at: deadline_at}) do
    seconds = DateTime.diff(deadline_at, DateTime.utc_now())
    ExpiryWorker.schedule(id, max(seconds, 0))
  end

  # ── Reads ─────────────────────────────────────────────────────────────────

  @doc """
  The caller's open check, with participants preloaded, or nil.

  `scope` narrows to one lane: `:match` (lobby or matchmaking) or `:party`.
  `:any` returns the newest across both lanes — the admin's view, not the
  API's.
  """
  @spec for_user(User.t() | Ecto.UUID.t(), scope() | :any) :: Check.t() | nil
  def for_user(user, scope \\ :any) do
    user_id = user_id(user)

    from(c in Check,
      join: p in Participant,
      on: p.ready_check_id == c.id,
      where: p.user_id == ^user_id and c.status == "pending",
      order_by: [desc: c.inserted_at, desc: c.id],
      limit: 1,
      preload: [:participants]
    )
    |> scope_filter(scope)
    |> Repo.one()
  end

  defp scope_filter(query, :match), do: where(query, [c], is_nil(c.party_id))
  defp scope_filter(query, :party), do: where(query, [c], not is_nil(c.party_id))
  defp scope_filter(query, :any), do: query

  @doc "The lobby's open check, with participants preloaded, or nil."
  @spec pending_for_lobby(Ecto.UUID.t()) :: Check.t() | nil
  def pending_for_lobby(lobby_id) when is_binary(lobby_id) do
    Check
    |> where([c], c.lobby_id == ^lobby_id and c.status == "pending")
    |> preload(:participants)
    |> Repo.one()
  end

  def pending_for_lobby(_lobby_id), do: nil

  @doc "The party's open check, with participants preloaded, or nil."
  @spec pending_for_party(Ecto.UUID.t()) :: Check.t() | nil
  def pending_for_party(party_id) when is_binary(party_id) do
    Check
    |> where([c], c.party_id == ^party_id and c.status == "pending")
    |> preload(:participants)
    |> Repo.one()
  end

  def pending_for_party(_party_id), do: nil

  @doc """
  True when the subject's most recent check passed.

  What a game calls from `before_lobby_state_change` to gate its own start.
  A reset opens a fresh pending check, which makes this false again — so a
  rematch cannot ride the previous match's pass.
  """
  @spec passed?(Lobby.t() | Party.t() | Ecto.UUID.t()) :: boolean()
  def passed?(%Lobby{id: id}), do: passed?(id)
  def passed?(%Party{id: id}), do: subject_passed?(:party_id, id)

  def passed?(lobby_id) when is_binary(lobby_id), do: subject_passed?(:lobby_id, lobby_id)

  def passed?(_lobby), do: false

  # `id` breaks ties: `inserted_at` has second precision, and a reset opens
  # the replacement within the same second as the check it replaces. Ids are
  # UUIDv7, so they order by creation time.
  defp subject_passed?(field, id) do
    Check
    |> where([c], field(c, ^field) == ^id)
    |> order_by([c], desc: c.inserted_at, desc: c.id)
    |> limit(1)
    |> select([c], c.status)
    |> Repo.one()
    |> Kernel.==("passed")
  end

  @doc """
  The participants who did not answer ready — the host's kick list, and what
  `after_ready_check_failed` is handed.
  """
  @spec not_ready(Check.t()) :: [Participant.t()]
  def not_ready(%Check{} = check) do
    check
    |> load_participants()
    |> Enum.reject(&(&1.state == "ready"))
  end

  @doc "Fetches a check by id (with participants), or nil."
  @spec get_check(Ecto.UUID.t()) :: Check.t() | nil
  def get_check(id) do
    case Repo.get_uuid(Check, id) do
      nil -> nil
      check -> Repo.preload(check, :participants)
    end
  end

  @doc """
  Lists checks for the admin views, newest first.

  Options: `:status`, `:kind`, `:lobby_id`, `:party_id`, `:page`,
  `:page_size`.
  """
  @spec list_checks(keyword()) :: [Check.t()]
  def list_checks(opts \\ []) do
    opts
    |> checks_query()
    |> order_by([c], desc: c.inserted_at)
    |> paginate(opts)
    |> preload(:participants)
    |> Repo.all()
  end

  @doc "Counts checks matching the same filters as `list_checks/1`."
  @spec count_checks(keyword()) :: non_neg_integer()
  def count_checks(opts \\ []) do
    opts |> checks_query() |> Repo.aggregate(:count, :id)
  end

  @doc """
  Counts by status over the last `hours` — the accept-rate and dodge-rate
  numbers on the admin page.
  """
  @spec stats(pos_integer()) :: %{String.t() => non_neg_integer()}
  def stats(hours \\ 24) do
    since = DateTime.add(DateTime.utc_now(), -hours * 3600, :second)

    from(c in Check,
      where: c.inserted_at >= ^since,
      group_by: c.status,
      select: {c.status, count(c.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  # ── internals ─────────────────────────────────────────────────────────────

  defp checks_query(opts) do
    Check
    |> filter_equals(:status, Keyword.get(opts, :status))
    |> filter_equals(:kind, Keyword.get(opts, :kind))
    |> filter_equals(:lobby_id, Keyword.get(opts, :lobby_id))
    |> filter_equals(:party_id, Keyword.get(opts, :party_id))
  end

  defp filter_equals(query, field, value) when is_binary(value) and value != "",
    do: where(query, [c], field(c, ^field) == ^value)

  defp filter_equals(query, _field, _value), do: query

  # Pagination is opt-in; an unwindowed read is still bounded.
  defp paginate(query, opts), do: Gamend.Query.maybe_page(query, opts)

  defp load_participants(%Check{participants: %Ecto.Association.NotLoaded{}} = check),
    do: check |> Repo.preload(:participants) |> Map.fetch!(:participants)

  defp load_participants(%Check{participants: participants}), do: participants

  defp user_id(%User{id: id}), do: id
  defp user_id(id) when is_binary(id), do: id

  # Lobby checks go to the lobby topic and party checks to the party topic, so
  # every member (and, for lobbies, spectator) sees one event; matchmaking
  # checks have no shared topic yet, so they fan out per user.
  defp broadcast(%Check{lobby_id: lobby_id} = check, event) when is_binary(lobby_id) do
    Gamend.Broadcast.publish(
      "lobby:#{lobby_id}",
      {:ready_check_event, event, check}
    )
  end

  defp broadcast(%Check{party_id: party_id} = check, event) when is_binary(party_id) do
    Gamend.Broadcast.publish(
      "party:#{party_id}",
      {:ready_check_event, event, check}
    )
  end

  defp broadcast(%Check{} = check, event) do
    check
    |> load_participants()
    |> Enum.each(fn participant ->
      Gamend.Broadcast.publish(
        "matchmaking:user:#{participant.user_id}",
        {:ready_check_event, event, check}
      )
    end)
  end
end
