defmodule Gamend.Results do
  @moduledoc ~S"""
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


  **Note:** This is an SDK stub. Calling these functions will raise an error.
  The actual implementation runs on the Gamend.
  """

  @doc ~S"""
    How many results match `filters` (as `list/2`).
  """
  @spec count(map()) :: non_neg_integer()
  def count(_filters \\ %{}) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Results.count/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    How many events a result holds.
  """
  @spec count_events(String.t()) :: non_neg_integer()
  def count_events(_result_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Results.count_events/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    A result and its events, deleted. `{:error, :not_found}` when another
    delete took it first.
    
  """
  @spec delete(Gamend.Results.Result.t()) ::
          {:ok, Gamend.Results.Result.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def delete(_result) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0,
          do: {:error, :not_found},
          else:
            {:ok,
             %Gamend.Results.Result{
               id: "",
               user_id: "",
               lobby_id: nil,
               kind: "",
               visibility: "owner_only",
               status: "open",
               metadata: %{},
               started_at: ~U[1970-01-01 00:00:00Z],
               ended_at: nil
             }}

      _ ->
        raise "Gamend.Results.delete/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    A result's events, oldest first. Opts: `:after`, an event id (the events
    written after it: a reconnect's catch-up), `:limit` (500, at most 2,000).
    
  """
  @spec events(
          String.t(),
          keyword()
        ) :: [Gamend.Results.Event.t()]
  def events(_result_id, _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Results.events/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    The events of many results whose key is one of `keys`, by result id, each
    list oldest first: one query, for a page of results read whole (a
    history list).
    
  """
  @spec events_by_key([String.t()], [String.t()]) :: %{
          required(String.t()) => [Gamend.Results.Event.t()]
        }
  def events_by_key(_result_ids, _keys) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        %{}

      _ ->
        raise "Gamend.Results.events_by_key/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    The play over: `{:ok, result}`, ended now. One update that only matches an
    open row, so a second finish answers `{:error, :already_ended}`.
    
  """
  @spec finish(Gamend.Results.Result.t() | String.t()) ::
          {:ok, Gamend.Results.Result.t()} | {:error, term()}
  def finish(_result_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0,
          do: {:error, :not_found},
          else:
            {:ok,
             %Gamend.Results.Result{
               id: "",
               user_id: "",
               lobby_id: nil,
               kind: "",
               visibility: "owner_only",
               status: "open",
               metadata: %{},
               started_at: ~U[1970-01-01 00:00:00Z],
               ended_at: nil
             }}

      _ ->
        raise "Gamend.Results.finish/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    A result by id, or nil.
  """
  @spec get(String.t()) :: Gamend.Results.Result.t() | nil
  def get(_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0,
          do: nil,
          else: %Gamend.Results.Result{
            id: "",
            user_id: "",
            lobby_id: nil,
            kind: "",
            visibility: "owner_only",
            status: "open",
            metadata: %{},
            started_at: ~U[1970-01-01 00:00:00Z],
            ended_at: nil
          }

      _ ->
        raise "Gamend.Results.get/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    The kinds results have been written under, for a filter.
  """
  @spec kinds() :: [String.t()]
  def kinds() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Results.kinds/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Results, newest first. Filters: `:user_id`, `:kind` (one, or a list),
    `:status`, `:lobby_id`. Opts: `:page` and `:page_size`; with no `:page`, the first
    `Gamend.Query.unpaginated_limit/0`.
    
  """
  @spec list(
          map(),
          keyword()
        ) :: [Gamend.Results.Result.t()]
  def list(_filters \\ %{}, _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Results.list/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    A guest's results made the account's (`Gamend.Accounts.GuestMerge`): their
    plays join the account's history instead of going with the guest.
    
  """
  @spec move_user(String.t(), String.t()) :: non_neg_integer()
  def move_user(_from_user_id, _to_user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Results.move_user/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Results started before `cutoff` deleted with their events, `batch` at a
    time; answers how many results went.
    
  """
  @spec prune_before(DateTime.t(), pos_integer()) :: non_neg_integer()
  def prune_before(_cutoff, _batch) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Results.prune_before/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Whether `user` may read `result`, by its visibility: `public` anyone,
    `owner_only` its player, `lobby_members_only` a player seated in its
    lobby now, `owner_or_lobby_member` either, `admin_only` and every other
    an admin. `server_only` no client.
    
  """
  @spec readable?(Gamend.Results.Result.t(), Gamend.Accounts.User.t() | nil) :: boolean()
  def readable?(_r, _user) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :erlang.phash2(make_ref(), 2) == 0

      _ ->
        raise "Gamend.Results.readable?/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    One thing that happened in a play: `key` what (`answer`, `hint`), `value`
    the number it carries (or nil), `metadata` anything else. `{:ok, event}`;
    `{:error, :ended}` once the play is over, `{:error, :not_found}`,
    `{:error, :too_many_events}` past `GAMEND_LIMITS_MAX_RESULT_EVENTS`.
    
  """
  @spec record(Gamend.Results.Result.t() | String.t(), String.t(), number() | nil, map()) ::
          {:ok, Gamend.Results.Event.t()} | {:error, term()}
  def record(_result, _key, _value \\ nil, _metadata \\ %{}) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0,
          do: {:error, :ended},
          else:
            {:ok,
             %Gamend.Results.Event{
               id: "",
               result_id: "",
               elapsed_ms: 0,
               key: "",
               value: nil,
               metadata: %{}
             }}

      _ ->
        raise "Gamend.Results.record/4 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    `record/4` on every open result of `lobby_id`, for code that knows the
    lobby and not its players (a timer, a disconnect). Answers how many it
    wrote.
    
  """
  @spec record_lobby(String.t(), String.t(), number() | nil, map()) :: non_neg_integer()
  def record_lobby(_lobby_id, _key, _value \\ nil, _metadata \\ %{}) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Results.record_lobby/4 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    A play begun by `user_id`, of `kind` (`match`, `boat_run`): `{:ok,
    result}`. Opts: `:lobby_id` the lobby it runs in, `:visibility` who may
    read it (KV's words, atom or string; `owner_only` by default),
    `:metadata` what the play is (its settings; never its outcome).
    
  """
  @spec start(String.t(), String.t(), keyword()) ::
          {:ok, Gamend.Results.Result.t()} | {:error, term()}
  def start(_user_id, _kind, _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0,
          do: {:error, :not_found},
          else:
            {:ok,
             %Gamend.Results.Result{
               id: "",
               user_id: "",
               lobby_id: nil,
               kind: "",
               visibility: "owner_only",
               status: "open",
               metadata: %{},
               started_at: ~U[1970-01-01 00:00:00Z],
               ended_at: nil
             }}

      _ ->
        raise "Gamend.Results.start/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Each event key's `count` and `sum` of `value`, for one result
    (`%{"answer" => %{count: 10, sum: 7.0}}`) or a list of result ids (by id:
    one query whatever their number). A key whose events carry no value sums
    to 0.
    
  """
  @spec stats(Gamend.Results.Result.t() | [String.t()]) :: map()
  def stats(_ids) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        %{}

      _ ->
        raise "Gamend.Results.stats/1 is a stub - only available at runtime on Gamend"
    end
  end
end
