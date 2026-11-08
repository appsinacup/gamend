defmodule Gamend.Results do
  @moduledoc """
  What happened in a play (priv/docs/40-gameplay/45-results.md).

  A **result** is one play by one player (`Gamend.Results.Result`), its
  **events** what happened in it, in order (`Gamend.Results.Event`). The game
  writes an event when something happens and nothing else: no summary kept up
  to date, no copy of the play's state. The lobby holds the live state; the
  result is the record it leaves. The same rows are the replay (the events by
  id), the play at a glance (`stats/1`: each key's count and sum) and the
  player's history (`list/2`).

  **Writes are the server's.** A plugin, the host app or a hook handling a
  move calls `start/3`, `record/4` and `finish/1`; no client writes a result.
  An event is one insert and `finish/1` one update that only matches an open
  row, so a play ends once; the two take turns under the result's lock, so
  no event lands after the end and the event cap holds.

  **Reads follow the result's visibility**, KV's words (`readable?/2`), and
  every write is pushed as it happens (`result_started`, `result_event`,
  `result_ended`) to the owner's `user:<id>` topic and, when its lobby's
  members may read it, the lobby's `lobby:<id>`.
  """

  import Ecto.Query

  alias Gamend.Accounts.User
  alias Gamend.Broadcast
  alias Gamend.Repo
  alias Gamend.Results.Event
  alias Gamend.Results.Result

  require Gamend.Results.ResultStatus, as: ResultStatus
  require Gamend.Results.ResultVisibility, as: ResultVisibility

  @user_id "user_id"
  @lobby_id "lobby_id"
  @status "status"
  @kind "kind"

  # Visibilities whose events reach the owner, and the lobby's members.
  @owner_pushed ~w(public owner_only lobby_members_only owner_or_lobby_member)
  @lobby_pushed ~w(public lobby_members_only owner_or_lobby_member)

  @default_events_limit 500
  @max_events_limit 2_000

  # ── Writing ──────────────────────────────────────────────────────────────

  @doc """
  A play begun by `user_id`, of `kind` (`match`, `boat_run`): `{:ok,
  result}`. Opts: `:lobby_id` the lobby it runs in, `:visibility` who may
  read it (KV's words, atom or string; `owner_only` by default),
  `:metadata` what the play is (its settings; never its outcome).
  """
  @spec start(String.t(), String.t(), keyword()) :: {:ok, Result.t()} | {:error, term()}
  def start(user_id, kind, opts \\ []) when is_binary(user_id) and is_binary(kind) do
    attrs = %{
      user_id: user_id,
      lobby_id: opts[:lobby_id],
      kind: kind,
      visibility: to_string(opts[:visibility] || :owner_only),
      metadata: opts[:metadata] || %{},
      started_at: DateTime.utc_now()
    }

    case %Result{} |> Result.changeset(attrs) |> Repo.insert() do
      {:ok, result} ->
        push(result, {:result_started, result})
        {:ok, result}

      {:error, _changeset} = error ->
        error
    end
  end

  @doc """
  One thing that happened in a play: `key` what (`answer`, `hint`), `value`
  the number it carries (or nil), `metadata` anything else. `{:ok, event}`;
  `{:error, :ended}` once the play is over, `{:error, :not_found}`,
  `{:error, :too_many_events}` past `GAMEND_LIMITS_MAX_RESULT_EVENTS`.
  """
  @spec record(Result.t() | String.t(), String.t(), number() | nil, map()) ::
          {:ok, Event.t()} | {:error, term()}
  def record(result, key, value \\ nil, metadata \\ %{})

  def record(result_id, key, value, metadata) when is_binary(result_id) do
    case get(result_id) do
      %Result{} = result -> record(result, key, value, metadata)
      nil -> {:error, :not_found}
    end
  end

  def record(%Result{status: ResultStatus.ended()}, _key, _value, _metadata), do: {:error, :ended}

  # The struct's status is an early refusal only: it was read before, maybe
  # long before (`record_lobby/4`'s list, a caller's own copy). The result is
  # read again under its lock, where `finish/1` writes too, so an event lands
  # before the end or is refused, and the cap counts what is really there.
  # Checked against the struct and counted with no lock, two events at the
  # cap both passed it, and an event recorded beside `finish/1` landed after
  # the play had ended.
  def record(%Result{} = result, key, value, metadata) when is_binary(key) do
    with_result_lock(result.id, fn ->
      case Repo.get(Result, result.id) do
        nil ->
          Repo.rollback(:not_found)

        %Result{status: ResultStatus.ended()} ->
          Repo.rollback(:ended)

        %Result{} = current ->
          if count_events(current.id) >= Gamend.Limits.get(:max_result_events),
            do: Repo.rollback(:too_many_events),
            else: insert_event(current, key, value, metadata)
      end
    end)
  end

  # Pushes wait for the commit (`Gamend.Broadcast`).
  defp insert_event(result, key, value, metadata) do
    attrs = %{
      result_id: result.id,
      elapsed_ms: max(DateTime.diff(DateTime.utc_now(), result.started_at, :millisecond), 0),
      key: key,
      value: value && value / 1,
      metadata: metadata || %{}
    }

    case %Event{} |> Event.changeset(attrs) |> Repo.insert() do
      {:ok, event} ->
        push(result, {:result_event, %{result_id: result.id, event: event}})
        event

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  # One result's events and its end take turns.
  defp with_result_lock(result_id, fun), do: Gamend.Lock.serialize("result", result_id, fun)

  @doc """
  `record/4` on every open result of `lobby_id`, for code that knows the
  lobby and not its players (a timer, a disconnect). Answers how many it
  wrote.
  """
  @spec record_lobby(String.t(), String.t(), number() | nil, map()) :: non_neg_integer()
  def record_lobby(lobby_id, key, value \\ nil, metadata \\ %{}) when is_binary(lobby_id) do
    from(r in Result, where: r.lobby_id == ^lobby_id and r.status == ^ResultStatus.open())
    |> Repo.all()
    |> Enum.count(&match?({:ok, _}, record(&1, key, value, metadata)))
  end

  @doc """
  The play over: `{:ok, result}`, ended now. One update that only matches an
  open row, so a second finish answers `{:error, :already_ended}`.
  """
  @spec finish(Result.t() | String.t()) :: {:ok, Result.t()} | {:error, term()}
  def finish(%Result{id: id}), do: finish(id)

  def finish(result_id) when is_binary(result_id) do
    # Under the lock `record/4` takes, so no event is being written beside it,
    # and timed inside it, so every event recorded first is before the end.
    with_result_lock(result_id, fn ->
      from(r in Result, where: r.id == ^result_id and r.status == ^ResultStatus.open())
      |> Repo.compare_and_set(set: [status: ResultStatus.ended(), ended_at: DateTime.utc_now()])
      |> case do
        {:ok, result} ->
          push(result, {:result_ended, result})
          result

        {:error, :precondition_failed} ->
          if get(result_id), do: Repo.rollback(:already_ended), else: Repo.rollback(:not_found)
      end
    end)
  end

  @doc """
  A result and its events, deleted. `{:error, :not_found}` when another
  delete took it first.
  """
  @spec delete(Result.t()) :: {:ok, Result.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def delete(%Result{} = result) do
    Gamend.AfterCommit.transaction(fn ->
      from(e in Event, where: e.result_id == ^result.id) |> Repo.delete_all()

      case Repo.rescue_stale(:not_found, fn -> Repo.delete(result) end) do
        {:ok, deleted} -> deleted
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  # ── Reading ──────────────────────────────────────────────────────────────

  @doc "A result by id, or nil."
  @spec get(String.t()) :: Result.t() | nil
  def get(id) when is_binary(id), do: Repo.get_uuid(Result, id)

  @doc """
  Results, newest first. Filters: `:user_id`, `:kind` (one, or a list),
  `:status`, `:lobby_id`. Opts: `:page` and `:page_size`; with no `:page`, the first
  `Gamend.Query.unpaginated_limit/0`.
  """
  @spec list(map(), keyword()) :: [Result.t()]
  def list(filters \\ %{}, opts \\ []) do
    filters
    |> query()
    |> order_by([r], desc: r.started_at, desc: r.id)
    |> Gamend.Query.maybe_page(opts)
    |> Repo.all()
  end

  @doc "How many results match `filters` (as `list/2`)."
  @spec count(map()) :: non_neg_integer()
  def count(filters \\ %{}), do: filters |> query() |> Repo.aggregate(:count, :id)

  @doc "The kinds results have been written under, for a filter."
  @spec kinds() :: [String.t()]
  def kinds do
    from(r in Result, distinct: true, select: r.kind, order_by: r.kind) |> Repo.all()
  end

  defp query(filters) do
    Enum.reduce(filters, from(r in Result), fn {key, value}, query ->
      filter(query, to_string(key), blank(value))
    end)
  end

  defp filter(query, _key, nil), do: query
  defp filter(query, @kind, kinds) when is_list(kinds), do: where(query, [r], r.kind in ^kinds)
  defp filter(query, @kind, value), do: where(query, [r], r.kind == ^value)
  defp filter(query, @status, value), do: where(query, [r], r.status == ^value)

  # An id that is not one matches nothing, rather than raising on the cast.
  defp filter(query, key, value) when key in [@user_id, @lobby_id] do
    case Gamend.UUIDv7.cast_or_nil(value) do
      nil -> where(query, false)
      id when key == @user_id -> where(query, [r], r.user_id == ^id)
      id -> where(query, [r], r.lobby_id == ^id)
    end
  end

  defp filter(query, _key, _value), do: query

  defp blank(value) when value in [nil, ""], do: nil
  defp blank(value), do: value

  @doc """
  A result's events, oldest first. Opts: `:after`, an event id (the events
  written after it: a reconnect's catch-up), `:limit` (500, at most 2,000).
  """
  @spec events(String.t(), keyword()) :: [Event.t()]
  def events(result_id, opts \\ []) when is_binary(result_id) do
    limit = opts[:limit] |> to_limit() |> min(@max_events_limit)

    from(e in Event, where: e.result_id == ^result_id, order_by: [asc: e.id], limit: ^limit)
    |> after_event(opts[:after])
    |> Repo.all()
  end

  defp after_event(query, id) when is_binary(id) and id != "",
    do: where(query, [e], e.id > ^id)

  defp after_event(query, _id), do: query

  defp to_limit(limit) when is_integer(limit) and limit > 0, do: limit
  defp to_limit(_limit), do: @default_events_limit

  @doc """
  The events of many results whose key is one of `keys`, by result id, each
  list oldest first: one query, for a page of results read whole (a
  history list).
  """
  @spec events_by_key([String.t()], [String.t()]) :: %{String.t() => [Event.t()]}
  def events_by_key([], _keys), do: %{}

  def events_by_key(result_ids, keys) when is_list(result_ids) and is_list(keys) do
    from(e in Event,
      where: e.result_id in ^result_ids and e.key in ^keys,
      order_by: [asc: e.id]
    )
    |> Repo.all()
    |> Enum.group_by(& &1.result_id)
  end

  @doc """
  A guest's results made the account's (`Gamend.Accounts.GuestMerge`): their
  plays join the account's history instead of going with the guest.
  """
  @spec move_user(String.t(), String.t()) :: non_neg_integer()
  def move_user(from_user_id, to_user_id)
      when is_binary(from_user_id) and is_binary(to_user_id) do
    {count, _} =
      from(r in Result, where: r.user_id == ^from_user_id)
      |> Repo.update_all(set: [user_id: to_user_id])

    count
  end

  @doc "How many events a result holds."
  @spec count_events(String.t()) :: non_neg_integer()
  def count_events(result_id) when is_binary(result_id) do
    from(e in Event, where: e.result_id == ^result_id) |> Repo.aggregate(:count, :id)
  end

  @doc """
  Each event key's `count` and `sum` of `value`, for one result
  (`%{"answer" => %{count: 10, sum: 7.0}}`) or a list of result ids (by id:
  one query whatever their number). A key whose events carry no value sums
  to 0.
  """
  @spec stats(Result.t() | [String.t()]) :: map()
  def stats(%Result{id: id}), do: Map.get(stats([id]), id, %{})
  def stats([]), do: %{}

  def stats(ids) when is_list(ids) do
    from(e in Event,
      where: e.result_id in ^ids,
      group_by: [e.result_id, e.key],
      select: {e.result_id, e.key, count(e.id), sum(e.value)}
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn {result_id, key, count, sum}, acc ->
      entry = %{count: count, sum: (sum || 0) / 1}
      Map.update(acc, result_id, %{key => entry}, &Map.put(&1, key, entry))
    end)
  end

  @doc """
  Whether `user` may read `result`, by its visibility: `public` anyone,
  `owner_only` its player, `lobby_members_only` a player seated in its
  lobby now, `owner_or_lobby_member` either, `admin_only` and every other
  an admin. `server_only` no client.
  """
  @spec readable?(Result.t(), User.t() | nil) :: boolean()
  def readable?(%Result{visibility: ResultVisibility.server_only()}, _user), do: false
  def readable?(%Result{}, %User{is_admin: true}), do: true
  def readable?(%Result{visibility: ResultVisibility.public()}, _user), do: true

  def readable?(%Result{visibility: ResultVisibility.owner_only()} = r, user),
    do: played_by?(r, user)

  def readable?(%Result{visibility: ResultVisibility.lobby_members_only()} = r, user),
    do: seated_in_lobby?(r, user)

  def readable?(%Result{visibility: ResultVisibility.owner_or_lobby_member()} = r, user),
    do: played_by?(r, user) or seated_in_lobby?(r, user)

  def readable?(%Result{}, _user), do: false

  defp played_by?(%Result{user_id: owner}, %User{id: id}), do: owner == id
  defp played_by?(_result, _user), do: false

  defp seated_in_lobby?(%Result{lobby_id: lobby_id}, %User{lobby_id: lobby_id})
       when is_binary(lobby_id),
       do: true

  defp seated_in_lobby?(_result, _user), do: false

  # ── Retention ────────────────────────────────────────────────────────────

  @doc """
  Results started before `cutoff` deleted with their events, `batch` at a
  time; answers how many results went.
  """
  @spec prune_before(DateTime.t(), pos_integer()) :: non_neg_integer()
  def prune_before(%DateTime{} = cutoff, batch) when is_integer(batch) and batch > 0 do
    ids =
      from(r in Result, where: r.started_at < ^cutoff, select: r.id, limit: ^batch)
      |> Repo.all()

    case ids do
      [] ->
        0

      ids ->
        from(e in Event, where: e.result_id in ^ids) |> Repo.delete_all()
        {count, _} = from(r in Result, where: r.id in ^ids) |> Repo.delete_all()
        count + prune_before(cutoff, batch)
    end
  end

  # ── Pushes ───────────────────────────────────────────────────────────────

  # Once the write commits, to whoever may read it: the owner unless the
  # result is the server's or the admins', the lobby's members when they
  # may read it.
  defp push(%Result{} = result, message) do
    if result.visibility in @owner_pushed,
      do: Broadcast.publish("user:#{result.user_id}", message)

    if result.visibility in @lobby_pushed and is_binary(result.lobby_id),
      do: Broadcast.publish("lobby:#{result.lobby_id}", message)

    :ok
  end
end
