defmodule Gamend.Leaderboards do
  @moduledoc ~S"""
  The Leaderboards context.

  Provides server-authoritative leaderboard management. Scores can only be
  submitted via server-side code — there is no public API for score submission.

  ## Usage

      # Create a leaderboard
      {:ok, lb} = Leaderboards.create_leaderboard(%{
        slug: "weekly_kills",
        title: "Weekly Kills",
        sort_order: :desc,
        operator: :incr
      })

      # Submit score (server-only): resolve the active leaderboard first and submit by ID
      leaderboard = Leaderboards.get_active_leaderboard_by_slug("weekly_kills")
      {:ok, record} = Leaderboards.submit_score(leaderboard.id, user_id, 10)

      # List records with rank (use leaderboard id)
      records = Leaderboards.list_records(leaderboard.id, page: 1, limit: 25)

  ## Keys

  A board can hold several rankings: a record is unique per user (or label)
  and `key`, and every read ranks within one key. `""` is the default, a
  board with one ranking. A host keeping, say, a best per game and language
  on one board submits with `key: "match|60|es_es"` and metadata naming the
  parts; `list_records/2` with `key: :all` and `meta:` reads across keys
  (`best_per_user: true` keeps each player's best of them). `list_keys/2`
  names the keys a board holds, and `list_records_above/3` the records just
  ahead of a score on one key. A board can show its keys as tabs and
  filters on `/leaderboards` (`GamendWeb.LeaderboardViews`).

  ## All time

  A `:best` board with seasons (`all_time?/1`: a start or an end date) has
  an all-time ranking too: every season of its slug read as one, each
  player's (or label's) best row of them, ranked. `all_time: true` on
  `list_records/2`, `count_records/2`, `get_user_record/3` and
  `list_keys/2` reads it, per key, from any season of the slug.

  Those rows are kept on a hidden board of their own, `<slug>__all_time`:
  a submit to a season raises it the way a `:best` submit does, an edited
  or deleted season row reads its owner's best again, and a deleted season
  refills it. So All time reads like any board, indexed and cached, however
  many seasons and players there are. Computing it from the seasons on
  every read took a second a page at 100,000 rows. The board is made and
  filled the first time it is asked for; `rebuild_all_time/1` refills it
  for rows written around `submit_score/5`.

  ## Hidden boards

  `hidden: true` keeps a board out of `list_leaderboards/1`,
  `list_leaderboard_groups/1` and their counts unless `include_hidden: true`
  is passed. Everything else reads it like any board.

  ## Guests

  When the host requires an account to be listed (`Gamend.AccountRequired`,
  `:leaderboards`), a guest's records stay on a public board but out of every
  read of it: lists, counts and ranks, so a guest moves nobody. The guest's
  own `get_user_record/3` still answers, ranked where it would stand, with
  `hidden: true`. A hidden board keeps its guests (it is no one's public
  board), and `guests: true` reads them anyway (the admin's view).

  Whether a record is a guest's is stored on it (`Record`'s `guest`), kept
  by the database: set from the user on insert, moved when the user
  registers (or loses their last identity). A listed read filters the
  record alone, on its own rank index (`NOT guest`); joining every record to
  its user took a second a rank at a million rows.

      # Get user's record (use leaderboard id)
      {:ok, record} = Leaderboards.get_user_record(leaderboard.id, user_id)


  **Note:** This is an SDK stub. Calling these functions will raise an error.
  The actual implementation runs on the Gamend.
  """

  @doc ~S"""
    Whether a board has an all-time ranking: a `:best` board with seasons (a
    start or an end date). *All time* above.
    
  """
  @spec all_time?(Gamend.Leaderboards.Leaderboard.t()) :: boolean()
  def all_time?(_leaderboard) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :erlang.phash2(make_ref(), 2) == 0

      _ ->
        raise "Gamend.Leaderboards.all_time?/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Returns a changeset for a leaderboard (used in forms).
    
  """
  @spec change_leaderboard(Gamend.Leaderboards.Leaderboard.t()) :: Ecto.Changeset.t()
  def change_leaderboard(_leaderboard) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Leaderboards.change_leaderboard/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Returns a changeset for a leaderboard (used in forms).
    
  """
  @spec change_leaderboard(Gamend.Leaderboards.Leaderboard.t(), map()) :: Ecto.Changeset.t()
  def change_leaderboard(_leaderboard, _attrs) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Leaderboards.change_leaderboard/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Returns a changeset for a record (used in admin forms).
    
  """
  @spec change_record(Gamend.Leaderboards.Record.t()) :: Ecto.Changeset.t()
  def change_record(_record) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Leaderboards.change_record/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Returns a changeset for a record (used in admin forms).
    
  """
  @spec change_record(Gamend.Leaderboards.Record.t(), map()) :: Ecto.Changeset.t()
  def change_record(_record, _attrs) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Leaderboards.change_record/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count all leaderboard records across all leaderboards.
    
  """
  @spec count_all_records() :: non_neg_integer()
  def count_all_records() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Leaderboards.count_all_records/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Counts unique leaderboard slugs.
    
  """
  @spec count_leaderboard_groups() :: non_neg_integer()
  def count_leaderboard_groups() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Leaderboards.count_leaderboard_groups/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Counts unique leaderboard slugs.
    
  """
  @spec count_leaderboard_groups(keyword()) :: non_neg_integer()
  def count_leaderboard_groups(_opts) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Leaderboards.count_leaderboard_groups/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Counts leaderboards matching the given filters.
    
    Accepts the same filter options as `list_leaderboards/1`.
    
  """
  @spec count_leaderboards() :: non_neg_integer()
  def count_leaderboards() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Leaderboards.count_leaderboards/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Counts leaderboards matching the given filters.
    
    Accepts the same filter options as `list_leaderboards/1`.
    
  """
  @spec count_leaderboards(keyword()) :: non_neg_integer()
  def count_leaderboards(_opts) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Leaderboards.count_leaderboards/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Counts records for a leaderboard: the same `:key`, `:meta`,
    `:best_per_user`, `:search` and `:all_time` as `list_records/2`.
    
  """
  @spec count_records(Ecto.UUID.t()) :: non_neg_integer()
  def count_records(_leaderboard_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Leaderboards.count_records/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Counts records for a leaderboard: the same `:key`, `:meta`,
    `:best_per_user`, `:search` and `:all_time` as `list_records/2`.
    
  """
  @spec count_records(
          Ecto.UUID.t(),
          keyword()
        ) :: non_neg_integer()
  def count_records(_leaderboard_id, _opts) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Leaderboards.count_records/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    How many records each of `leaderboard_ids` holds, every key and every
    player (the admin's view), in one grouped query: `%{id => count}`, a board
    without records absent.
    
  """
  @spec count_records_by_board([Ecto.UUID.t()]) :: %{required(Ecto.UUID.t()) => non_neg_integer()}
  def count_records_by_board(_leaderboard_ids) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        %{}

      _ ->
        raise "Gamend.Leaderboards.count_records_by_board/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Creates a new leaderboard.
    
    ## Attributes
    
    See `t:Gamend.Types.leaderboard_create_attrs/0` for available fields.
    
    ## Examples
    
        iex> create_leaderboard(%{slug: "my_lb", title: "My Leaderboard"})
        {:ok, %Leaderboard{}}
    
        iex> create_leaderboard(%{slug: "", title: ""})
        {:error, %Ecto.Changeset{}}
    
  """
  @spec create_leaderboard(Gamend.Types.leaderboard_create_attrs()) ::
          {:ok, Gamend.Leaderboards.Leaderboard.t()} | {:error, Ecto.Changeset.t()}
  def create_leaderboard(_attrs) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if reason = Application.get_env(:gamend_sdk, :stub_error),
          do: {:error, reason},
          else:
            {:ok,
             %Gamend.Leaderboards.Leaderboard{
               id: 0,
               slug: "",
               title: "",
               description: nil,
               sort_order: :desc,
               operator: :set,
               starts_at: nil,
               ends_at: nil,
               metadata: %{},
               inserted_at: ~U[1970-01-01 00:00:00Z],
               updated_at: ~U[1970-01-01 00:00:00Z]
             }}

      _ ->
        raise "Gamend.Leaderboards.create_leaderboard/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Deletes a leaderboard and all its records.
    
  """
  @spec delete_leaderboard(Gamend.Leaderboards.Leaderboard.t()) ::
          {:ok, Gamend.Leaderboards.Leaderboard.t()} | {:error, Ecto.Changeset.t()}
  def delete_leaderboard(_leaderboard) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if reason = Application.get_env(:gamend_sdk, :stub_error),
          do: {:error, reason},
          else:
            {:ok,
             %Gamend.Leaderboards.Leaderboard{
               id: 0,
               slug: "",
               title: "",
               description: nil,
               sort_order: :desc,
               operator: :set,
               starts_at: nil,
               ends_at: nil,
               metadata: %{},
               inserted_at: ~U[1970-01-01 00:00:00Z],
               updated_at: ~U[1970-01-01 00:00:00Z]
             }}

      _ ->
        raise "Gamend.Leaderboards.delete_leaderboard/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Deletes a record.
    
  """
  @spec delete_record(Gamend.Leaderboards.Record.t()) ::
          {:ok, Gamend.Leaderboards.Record.t()} | {:error, Ecto.Changeset.t()}
  def delete_record(_record) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if reason = Application.get_env(:gamend_sdk, :stub_error),
          do: {:error, reason},
          else:
            {:ok,
             %Gamend.Leaderboards.Record{
               id: 0,
               leaderboard_id: 0,
               user_id: 0,
               label: nil,
               score: 0,
               rank: nil,
               metadata: %{},
               inserted_at: ~U[1970-01-01 00:00:00Z],
               updated_at: ~U[1970-01-01 00:00:00Z]
             }}

      _ ->
        raise "Gamend.Leaderboards.delete_record/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Deletes a user's record from a leaderboard (in `key:`, default `""`).
    Accepts either leaderboard ID or slug (both strings).
    
  """
  @spec delete_user_record(String.t(), Ecto.UUID.t(), keyword()) ::
          {:ok, Gamend.Leaderboards.Record.t()} | {:error, :not_found}
  def delete_user_record(_id_or_slug, _user_id, _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if reason = Application.get_env(:gamend_sdk, :stub_error),
          do: {:error, reason},
          else:
            {:ok,
             %Gamend.Leaderboards.Record{
               id: 0,
               leaderboard_id: 0,
               user_id: 0,
               label: nil,
               score: 0,
               rank: nil,
               metadata: %{},
               inserted_at: ~U[1970-01-01 00:00:00Z],
               updated_at: ~U[1970-01-01 00:00:00Z]
             }}

      _ ->
        raise "Gamend.Leaderboards.delete_user_record/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Ends a leaderboard by setting `ends_at` to the current time.
    
  """
  @spec end_leaderboard(Gamend.Leaderboards.Leaderboard.t() | String.t()) ::
          {:ok, Gamend.Leaderboards.Leaderboard.t()} | {:error, Ecto.Changeset.t() | :not_found}
  def end_leaderboard(_leaderboard) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if reason = Application.get_env(:gamend_sdk, :stub_error),
          do: {:error, reason},
          else:
            {:ok,
             %Gamend.Leaderboards.Leaderboard{
               id: 0,
               slug: "",
               title: "",
               description: nil,
               sort_order: :desc,
               operator: :set,
               starts_at: nil,
               ends_at: nil,
               metadata: %{},
               inserted_at: ~U[1970-01-01 00:00:00Z],
               updated_at: ~U[1970-01-01 00:00:00Z]
             }}

      _ ->
        raise "Gamend.Leaderboards.end_leaderboard/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Gets the currently active leaderboard with the given slug.
    Returns `nil` if no active leaderboard exists.
    
    An active leaderboard is one that:
    - Has not ended (`ends_at` is nil or in the future)
    - Has started (`starts_at` is nil or in the past)
    
    If multiple active leaderboards exist with the same slug,
    returns the most recently created one.
    
  """
  @spec get_active_leaderboard_by_slug(String.t()) :: Gamend.Leaderboards.Leaderboard.t() | nil
  def get_active_leaderboard_by_slug(_slug) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0,
          do: nil,
          else: %Gamend.Leaderboards.Leaderboard{
            id: 0,
            slug: "",
            title: "",
            description: nil,
            sort_order: :desc,
            operator: :set,
            starts_at: nil,
            ends_at: nil,
            metadata: %{},
            inserted_at: ~U[1970-01-01 00:00:00Z],
            updated_at: ~U[1970-01-01 00:00:00Z]
          }

      _ ->
        raise "Gamend.Leaderboards.get_active_leaderboard_by_slug/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Gets a single record by leaderboard ID, label and key (default `""`).
    
  """
  @spec get_label_record(Ecto.UUID.t(), String.t(), String.t()) ::
          Gamend.Leaderboards.Record.t() | nil
  def get_label_record(_leaderboard_id, _label, _key \\ "") do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0,
          do: nil,
          else: %Gamend.Leaderboards.Record{
            id: 0,
            leaderboard_id: 0,
            user_id: 0,
            label: nil,
            score: 0,
            rank: nil,
            metadata: %{},
            inserted_at: ~U[1970-01-01 00:00:00Z],
            updated_at: ~U[1970-01-01 00:00:00Z]
          }

      _ ->
        raise "Gamend.Leaderboards.get_label_record/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Gets a leaderboard by its UUID, or the active leaderboard by slug.
    
    ## Examples
    
        iex> get_leaderboard("0198c0de-...")
        %Leaderboard{}
    
        iex> get_leaderboard(Ecto.UUID.generate())
        nil
    
  """
  @spec get_leaderboard(String.t()) :: Gamend.Leaderboards.Leaderboard.t() | nil
  def get_leaderboard(_id_or_slug) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0,
          do: nil,
          else: %Gamend.Leaderboards.Leaderboard{
            id: 0,
            slug: "",
            title: "",
            description: nil,
            sort_order: :desc,
            operator: :set,
            starts_at: nil,
            ends_at: nil,
            metadata: %{},
            inserted_at: ~U[1970-01-01 00:00:00Z],
            updated_at: ~U[1970-01-01 00:00:00Z]
          }

      _ ->
        raise "Gamend.Leaderboards.get_leaderboard/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Gets a leaderboard by its ID. Raises if not found.
    
  """
  @spec get_leaderboard!(String.t()) :: Gamend.Leaderboards.Leaderboard.t()
  def get_leaderboard!(_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Leaderboards.get_leaderboard!/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Gets a record by its ID, or `nil` when there is none (or `id` is not a UUID).
    
    Intended for internal/admin usage.
    
  """
  @spec get_record(Ecto.UUID.t()) :: Gamend.Leaderboards.Record.t() | nil
  def get_record(_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0,
          do: nil,
          else: %Gamend.Leaderboards.Record{
            id: 0,
            leaderboard_id: 0,
            user_id: 0,
            label: nil,
            score: 0,
            rank: nil,
            metadata: %{},
            inserted_at: ~U[1970-01-01 00:00:00Z],
            updated_at: ~U[1970-01-01 00:00:00Z]
          }

      _ ->
        raise "Gamend.Leaderboards.get_record/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Gets a single record by leaderboard ID, user ID and key (default `""`).
    
  """
  @spec get_record(Ecto.UUID.t(), Ecto.UUID.t(), String.t()) ::
          Gamend.Leaderboards.Record.t() | nil
  def get_record(_leaderboard_id, _user_id, _key \\ "") do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0,
          do: nil,
          else: %Gamend.Leaderboards.Record{
            id: 0,
            leaderboard_id: 0,
            user_id: 0,
            label: nil,
            score: 0,
            rank: nil,
            metadata: %{},
            inserted_at: ~U[1970-01-01 00:00:00Z],
            updated_at: ~U[1970-01-01 00:00:00Z]
          }

      _ ->
        raise "Gamend.Leaderboards.get_record/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Like `get_record/1`, but raises `Ecto.NoResultsError` when there is none.
  """
  @spec get_record!(Ecto.UUID.t()) :: Gamend.Leaderboards.Record.t()
  def get_record!(_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Leaderboards.get_record!/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Gets a user's record with their rank (within its key: `key:`, default `""`).
    Returns `{:ok, record_with_rank}` or `{:error, :not_found}`.
    
    `all_time: true` answers their best row of every season, ranked all time
    (*All time* above).
    
  """
  @spec get_user_record(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, Gamend.Leaderboards.Record.t()} | {:error, :not_found}
  def get_user_record(_leaderboard_id, _user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if reason = Application.get_env(:gamend_sdk, :stub_error),
          do: {:error, reason},
          else:
            {:ok,
             %Gamend.Leaderboards.Record{
               id: 0,
               leaderboard_id: 0,
               user_id: 0,
               label: nil,
               score: 0,
               rank: nil,
               metadata: %{},
               inserted_at: ~U[1970-01-01 00:00:00Z],
               updated_at: ~U[1970-01-01 00:00:00Z]
             }}

      _ ->
        raise "Gamend.Leaderboards.get_user_record/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Gets a user's record with their rank (within its key: `key:`, default `""`).
    Returns `{:ok, record_with_rank}` or `{:error, :not_found}`.
    
    `all_time: true` answers their best row of every season, ranked all time
    (*All time* above).
    
  """
  @spec get_user_record(Ecto.UUID.t(), Ecto.UUID.t(), keyword()) ::
          {:ok, Gamend.Leaderboards.Record.t()} | {:error, :not_found}
  def get_user_record(_leaderboard_id, _user_id, _opts) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if reason = Application.get_env(:gamend_sdk, :stub_error),
          do: {:error, reason},
          else:
            {:ok,
             %Gamend.Leaderboards.Record{
               id: 0,
               leaderboard_id: 0,
               user_id: 0,
               label: nil,
               score: 0,
               rank: nil,
               metadata: %{},
               inserted_at: ~U[1970-01-01 00:00:00Z],
               updated_at: ~U[1970-01-01 00:00:00Z]
             }}

      _ ->
        raise "Gamend.Leaderboards.get_user_record/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Where a board is climbed, for the button on its page and its card:
    `{label, path}`, or nil. Set `config :gamend_core, :leaderboard_action,
    {Module, :function}`; it is called as `function(user_id | nil, slug)` and
    answers `{label, path}` (the label already in the reader's language) or nil.
    
    A board only says what it counts ("Most kilometers sailed"), never where
    that is done, and only the host knows its own pages, as with a quest
    (`Gamend.Quests.host_action/2`). A path starts with one `/` (`"/games"`); a
    URL or `"//…"` is dropped. The page keeps the reader's locale prefix on it.
    
  """
  @spec host_action(String.t(), Ecto.UUID.t() | nil) :: {String.t(), String.t()} | nil
  def host_action(_slug, _user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Leaderboards.host_action/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Forget the cached leaderboard lookups.
    
    Every write in here does this already. It is public because a CALLER can also
    learn the cache is stale: `get_active_leaderboard_by_slug/1` is cached for a
    minute, so a board deleted (or rolled back, under a test sandbox) hands out an
    id whose row is gone, and the next `submit_score/4` fails on the foreign key.
    A caller that sees that can drop the lookup and try again rather than wait out
    the TTL.
    
  """
  @spec invalidate_cache() :: :ok
  def invalidate_cache() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Leaderboards.invalidate_cache/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    The keys a board holds, sorted, from its listed records; with `prefix:`
    only the keys starting with it (`"match|"`: every language Word match has
    runs in). A key only guests have played is not offered. `all_time: true`
    names the keys of every season of the slug (*All time* above).
    
  """
  @spec list_keys(String.t()) :: [String.t()]
  def list_keys(_leaderboard_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Leaderboards.list_keys/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    The keys a board holds, sorted, from its listed records; with `prefix:`
    only the keys starting with it (`"match|"`: every language Word match has
    runs in). A key only guests have played is not offered. `all_time: true`
    names the keys of every season of the slug (*All time* above).
    
  """
  @spec list_keys(
          String.t(),
          keyword()
        ) :: [String.t()]
  def list_keys(_leaderboard_id, _opts) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Leaderboards.list_keys/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Lists unique leaderboard slugs with summary info.
    
    Returns a list of maps with:
    - `:slug` - the leaderboard slug
    - `:title` - title from the latest leaderboard
    - `:description` - description from the latest leaderboard
    - `:active_id` - ID of the currently active leaderboard (or nil)
    - `:latest_id` - ID of the most recent leaderboard
    - `:season_count` - total number of leaderboards with this slug
    
  """
  @spec list_leaderboard_groups() :: [map()]
  def list_leaderboard_groups() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Leaderboards.list_leaderboard_groups/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Lists unique leaderboard slugs with summary info.
    
    Returns a list of maps with:
    - `:slug` - the leaderboard slug
    - `:title` - title from the latest leaderboard
    - `:description` - description from the latest leaderboard
    - `:active_id` - ID of the currently active leaderboard (or nil)
    - `:latest_id` - ID of the most recent leaderboard
    - `:season_count` - total number of leaderboards with this slug
    
  """
  @spec list_leaderboard_groups(keyword()) :: [map()]
  def list_leaderboard_groups(_opts) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Leaderboards.list_leaderboard_groups/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Lists leaderboards with optional filters.
    
    ## Options
    
      * `:slug` - Filter by slug (returns all seasons of that leaderboard)
      * `:active` - If `true`, only active leaderboards. If `false`, only ended.
      * `:order_by` - Order by field: `:ends_at` or `:inserted_at` (default)
      * `:starts_after` - Only leaderboards that started after this DateTime
      * `:starts_before` - Only leaderboards that started before this DateTime
      * `:ends_after` - Only leaderboards that end after this DateTime
      * `:ends_before` - Only leaderboards that end before this DateTime
      * `:include_hidden` - Also hidden boards (default false)
      * `:page` - Page number (default 1)
      * `:page_size` - Page size (default 25)
    
    ## Examples
    
        iex> list_leaderboards(active: true)
        [%Leaderboard{}, ...]
    
        iex> list_leaderboards(slug: "weekly_kills")
        [%Leaderboard{}, ...]
    
        iex> list_leaderboards(starts_after: ~U[2025-01-01 00:00:00Z])
        [%Leaderboard{}, ...]
    
  """
  @spec list_leaderboards() :: [Gamend.Leaderboards.Leaderboard.t()]
  def list_leaderboards() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Leaderboards.list_leaderboards/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Lists leaderboards with optional filters.
    
    ## Options
    
      * `:slug` - Filter by slug (returns all seasons of that leaderboard)
      * `:active` - If `true`, only active leaderboards. If `false`, only ended.
      * `:order_by` - Order by field: `:ends_at` or `:inserted_at` (default)
      * `:starts_after` - Only leaderboards that started after this DateTime
      * `:starts_before` - Only leaderboards that started before this DateTime
      * `:ends_after` - Only leaderboards that end after this DateTime
      * `:ends_before` - Only leaderboards that end before this DateTime
      * `:include_hidden` - Also hidden boards (default false)
      * `:page` - Page number (default 1)
      * `:page_size` - Page size (default 25)
    
    ## Examples
    
        iex> list_leaderboards(active: true)
        [%Leaderboard{}, ...]
    
        iex> list_leaderboards(slug: "weekly_kills")
        [%Leaderboard{}, ...]
    
        iex> list_leaderboards(starts_after: ~U[2025-01-01 00:00:00Z])
        [%Leaderboard{}, ...]
    
  """
  @spec list_leaderboards(keyword()) :: [Gamend.Leaderboards.Leaderboard.t()]
  def list_leaderboards(_opts) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Leaderboards.list_leaderboards/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Lists all leaderboards with the given slug (all seasons), ordered by end date.
    
  """
  @spec list_leaderboards_by_slug(String.t()) :: [Gamend.Leaderboards.Leaderboard.t()]
  def list_leaderboards_by_slug(_slug) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Leaderboards.list_leaderboards_by_slug/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Lists all leaderboards with the given slug (all seasons), ordered by end date.
    
  """
  @spec list_leaderboards_by_slug(
          String.t(),
          keyword()
        ) :: [Gamend.Leaderboards.Leaderboard.t()]
  def list_leaderboards_by_slug(_slug, _opts) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Leaderboards.list_leaderboards_by_slug/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Lists records for a leaderboard, ordered by rank.
    
    ## Options
    
    See `t:Gamend.Types.pagination_opts/0` for available options, plus:
    
      * `:key` — the ranking to read (default `""`), or `:all` for every key's
        rows ranked together.
      * `:meta` — a map, keeping only records whose `metadata[field]` equals
        each value (`%{"game" => "match", "lang" => "es_es"}`). Ranks are
        computed **within** the filtered set, because "the Spanish board" means
        first among Spanish, not 57th overall. That is the opposite of
        `:search`, which ranks over the whole key so a found player's real
        position is what shows.
      * `:best_per_user` — with `key: :all`, each player's (or label's) best
        row only: one board read across keys, a player once.
      * `:guests` — `true` lists guests' records on a public board too, when
        the host keeps them off it (`Gamend.AccountRequired`): the admin's view.
      * `:all_time` — `true` reads every season of the board's slug as one
        ranking (*All time* above), with `:key` and `:search` only. A board
        without seasons reads as itself.
    
  """
  @spec list_records(String.t()) :: [Gamend.Leaderboards.Record.t()]
  def list_records(_leaderboard_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Leaderboards.list_records/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Lists records for a leaderboard, ordered by rank.
    
    ## Options
    
    See `t:Gamend.Types.pagination_opts/0` for available options, plus:
    
      * `:key` — the ranking to read (default `""`), or `:all` for every key's
        rows ranked together.
      * `:meta` — a map, keeping only records whose `metadata[field]` equals
        each value (`%{"game" => "match", "lang" => "es_es"}`). Ranks are
        computed **within** the filtered set, because "the Spanish board" means
        first among Spanish, not 57th overall. That is the opposite of
        `:search`, which ranks over the whole key so a found player's real
        position is what shows.
      * `:best_per_user` — with `key: :all`, each player's (or label's) best
        row only: one board read across keys, a player once.
      * `:guests` — `true` lists guests' records on a public board too, when
        the host keeps them off it (`Gamend.AccountRequired`): the admin's view.
      * `:all_time` — `true` reads every season of the board's slug as one
        ranking (*All time* above), with `:key` and `:search` only. A board
        without seasons reads as itself.
    
  """
  @spec list_records(
          String.t(),
          keyword()
        ) :: [Gamend.Leaderboards.Record.t()]
  def list_records(_leaderboard_id, _opts) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Leaderboards.list_records/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    The listed records just ahead of `score` on one key, nearest first: the
    runs a player at that score would overtake next. Ahead means a strictly
    better score (higher on a `:desc` board, lower on an `:asc` one), so a tie
    is not ahead. Each record carries its `rank`.
    
    It needs no record of the caller's: a first-timer reads it with their
    first score, and a guest with theirs, though a guest's own record is not
    listed (`Gamend.AccountRequired`). `list_records_around_user/3` needs the
    caller on the board. Labels' records are listed, like any.
    
    ## Options
    
      * `:key` — the ranking (default `""`)
      * `:limit` — how many (default 3)
    
  """
  @spec list_records_above(String.t(), integer()) :: [Gamend.Leaderboards.Record.t()]
  def list_records_above(_leaderboard_id, _score) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Leaderboards.list_records_above/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    The listed records just ahead of `score` on one key, nearest first: the
    runs a player at that score would overtake next. Ahead means a strictly
    better score (higher on a `:desc` board, lower on an `:asc` one), so a tie
    is not ahead. Each record carries its `rank`.
    
    It needs no record of the caller's: a first-timer reads it with their
    first score, and a guest with theirs, though a guest's own record is not
    listed (`Gamend.AccountRequired`). `list_records_around_user/3` needs the
    caller on the board. Labels' records are listed, like any.
    
    ## Options
    
      * `:key` — the ranking (default `""`)
      * `:limit` — how many (default 3)
    
  """
  @spec list_records_above(String.t(), integer(), keyword()) :: [Gamend.Leaderboards.Record.t()]
  def list_records_above(_leaderboard_id, _score, _opts) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Leaderboards.list_records_above/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Lists records around a specific user (centered on their position).
    
    Returns records above and below the user's rank.
    
    ## Options
    
      * `:limit` - Total number of records to return (default 11, centered on user)
      * `:key` - The ranking (default `""`)
    
  """
  @spec list_records_around_user(String.t(), Ecto.UUID.t()) :: [Gamend.Leaderboards.Record.t()]
  def list_records_around_user(_leaderboard_id, _user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Leaderboards.list_records_around_user/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Lists records around a specific user (centered on their position).
    
    Returns records above and below the user's rank.
    
    ## Options
    
      * `:limit` - Total number of records to return (default 11, centered on user)
      * `:key` - The ranking (default `""`)
    
  """
  @spec list_records_around_user(String.t(), Ecto.UUID.t(), keyword()) :: [
          Gamend.Leaderboards.Record.t()
        ]
  def list_records_around_user(_leaderboard_id, _user_id, _opts) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Leaderboards.list_records_around_user/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    The listed records either side of `record` on its key: `{above, below}`,
    each nearest first, each carrying its rank. Above is sorting ahead of it
    the way ranks count (a better score, or the same one set earlier), below
    sorting behind it, so the ranks run on from the record's own: `rank - 1`,
    `rank - 2`… above, `rank + 1`… below. `record` must carry its rank
    (`get_user_record/3`'s).
    
    A record kept off the board (a guest's, `Gamend.AccountRequired`) reads
    the same: its rank is where it would stand, and the rows behind it are
    numbered as if it stood there. Read off the rank index, as
    `list_records_above/3` is: the key is never ranked whole.
    
    ## Options
    
      * `:above`, `:below` — how many on each side (default 1)
    
  """
  @spec list_records_beside(String.t(), Gamend.Leaderboards.Record.t(), keyword()) ::
          {[Gamend.Leaderboards.Record.t()], [Gamend.Leaderboards.Record.t()]}
  def list_records_beside(_leaderboard_id, _record, _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Leaderboards.list_records_beside/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    The last records listed on a key, in rank order, each carrying its rank:
    the bottom of the board, where a player with no score yet comes in.
    
    ## Options
    
      * `:key` — the ranking (default `""`)
      * `:limit` — how many (default 3)
    
  """
  @spec list_records_last(
          String.t(),
          keyword()
        ) :: [Gamend.Leaderboards.Record.t()]
  def list_records_last(_leaderboard_id, _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Leaderboards.list_records_last/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Moves `from_user_id`'s records onto `to_user_id`, the way a guest's play
    joins the account they log in to (`Gamend.Accounts.GuestMerge`). The
    account's records are never lowered or deleted, and no hook or quest event
    fires: these scores were submitted once already.
    
      * `best` boards keep the better of the two (the board's sort order).
      * `incr` boards add the two up.
      * `set` and `decr` boards take the guest's record only where the account
        has none on that board and key.
    
    A guest's records left behind go with the guest account. Answers how many
    records reached the account.
    
  """
  @spec merge_user_records(Ecto.UUID.t(), Ecto.UUID.t()) :: non_neg_integer()
  def merge_user_records(_from_user_id, _to_user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Leaderboards.merge_user_records/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Fills the all-time board of `slug`'s seasons again from them (*All time*
    above). Reads make and fill it on their own the first time; this is for
    rows written around `submit_score/5`, such as a bulk import or
    `mix demo.seed`. Answers how many rows it holds, or `:error` when no board
    under `slug` has an all-time ranking.
    
  """
  @spec rebuild_all_time(String.t()) :: {:ok, non_neg_integer()} | :error
  def rebuild_all_time(_slug) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Leaderboards.rebuild_all_time/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Resolves multiple slugs to their currently active leaderboards in a single query.
    
    Returns a map of `slug => %Leaderboard{}` for each slug that has an active
    leaderboard. Slugs with no active leaderboard are omitted from the result.
    
    ## Examples
    
        iex> resolve_slugs(["weekly_kills", "monthly_score", "nonexistent"])
        %{
          "weekly_kills" => %Leaderboard{id: 1, slug: "weekly_kills", ...},
          "monthly_score" => %Leaderboard{id: 5, slug: "monthly_score", ...}
        }
    
  """
  @spec resolve_slugs([String.t()]) :: %{
          required(String.t()) => Gamend.Leaderboards.Leaderboard.t()
        }
  def resolve_slugs(_slugs) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        %{}

      _ ->
        raise "Gamend.Leaderboards.resolve_slugs/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Submit a score for a label-based (non-user) record.
    
    Works just like `submit_score/4` but uses a string label instead of a user ID.
    This is useful for statistics, rankings by category, etc.
    
    ## Examples
    
        iex> submit_label_score(leaderboard_id, "English", 42)
        {:ok, %Record{label: "English", score: 42}}
    
  """
  @spec submit_label_score(String.t(), String.t(), integer(), map(), keyword()) ::
          {:ok, Gamend.Leaderboards.Record.t()} | {:error, term()}
  def submit_label_score(_leaderboard_id, _label, _score, _metadata \\ %{}, _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if reason = Application.get_env(:gamend_sdk, :stub_error),
          do: {:error, reason},
          else:
            {:ok,
             %Gamend.Leaderboards.Record{
               id: 0,
               leaderboard_id: 0,
               user_id: 0,
               label: nil,
               score: 0,
               rank: nil,
               metadata: %{},
               inserted_at: ~U[1970-01-01 00:00:00Z],
               updated_at: ~U[1970-01-01 00:00:00Z]
             }}

      _ ->
        raise "Gamend.Leaderboards.submit_label_score/5 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Submits a score for a user on a leaderboard.
    
    This is a server-only function — there is no public API for score submission.
    The score is processed according to the leaderboard's operator:
    
      * `:set` — Always replace with new score
      * `:best` — Only update if new score is better (respects sort_order)
      * `:incr` — Add to existing score
      * `:decr` — Subtract from existing score
    
    To submit to a leaderboard by slug, first get the active leaderboard ID:
    
        leaderboard = Leaderboards.get_active_leaderboard_by_slug("weekly_kills")
        Leaderboards.submit_score(leaderboard.id, user_id, 10)
    
    ## Examples
    
        iex> submit_score(123, user_id, 10)
        {:ok, %Record{score: 10}}
    
        iex> submit_score(123, user_id, 5, %{weapon: "sword"})
        {:ok, %Record{score: 15, metadata: %{weapon: "sword"}}}
    
    `key:` (default `""`) is the ranking within the board the score goes to;
    the operator applies per key.
    
        iex> submit_score(123, user_id, 23, %{"game" => "match"}, key: "match|60")
        {:ok, %Record{key: "match|60", score: 23}}
    
  """
  @spec submit_score(String.t(), Ecto.UUID.t(), integer()) ::
          {:ok, Gamend.Leaderboards.Record.t()} | {:error, term()}
  def submit_score(_leaderboard_id, _user_id, _score) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if reason = Application.get_env(:gamend_sdk, :stub_error),
          do: {:error, reason},
          else:
            {:ok,
             %Gamend.Leaderboards.Record{
               id: 0,
               leaderboard_id: 0,
               user_id: 0,
               label: nil,
               score: 0,
               rank: nil,
               metadata: %{},
               inserted_at: ~U[1970-01-01 00:00:00Z],
               updated_at: ~U[1970-01-01 00:00:00Z]
             }}

      _ ->
        raise "Gamend.Leaderboards.submit_score/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Submits a score for a user on a leaderboard.
    
    This is a server-only function — there is no public API for score submission.
    The score is processed according to the leaderboard's operator:
    
      * `:set` — Always replace with new score
      * `:best` — Only update if new score is better (respects sort_order)
      * `:incr` — Add to existing score
      * `:decr` — Subtract from existing score
    
    To submit to a leaderboard by slug, first get the active leaderboard ID:
    
        leaderboard = Leaderboards.get_active_leaderboard_by_slug("weekly_kills")
        Leaderboards.submit_score(leaderboard.id, user_id, 10)
    
    ## Examples
    
        iex> submit_score(123, user_id, 10)
        {:ok, %Record{score: 10}}
    
        iex> submit_score(123, user_id, 5, %{weapon: "sword"})
        {:ok, %Record{score: 15, metadata: %{weapon: "sword"}}}
    
    `key:` (default `""`) is the ranking within the board the score goes to;
    the operator applies per key.
    
        iex> submit_score(123, user_id, 23, %{"game" => "match"}, key: "match|60")
        {:ok, %Record{key: "match|60", score: 23}}
    
  """
  @spec submit_score(String.t(), Ecto.UUID.t(), integer(), map()) ::
          {:ok, Gamend.Leaderboards.Record.t()} | {:error, term()}
  def submit_score(_leaderboard_id, _user_id, _score, _metadata) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if reason = Application.get_env(:gamend_sdk, :stub_error),
          do: {:error, reason},
          else:
            {:ok,
             %Gamend.Leaderboards.Record{
               id: 0,
               leaderboard_id: 0,
               user_id: 0,
               label: nil,
               score: 0,
               rank: nil,
               metadata: %{},
               inserted_at: ~U[1970-01-01 00:00:00Z],
               updated_at: ~U[1970-01-01 00:00:00Z]
             }}

      _ ->
        raise "Gamend.Leaderboards.submit_score/4 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Submits a score for a user on a leaderboard.
    
    This is a server-only function — there is no public API for score submission.
    The score is processed according to the leaderboard's operator:
    
      * `:set` — Always replace with new score
      * `:best` — Only update if new score is better (respects sort_order)
      * `:incr` — Add to existing score
      * `:decr` — Subtract from existing score
    
    To submit to a leaderboard by slug, first get the active leaderboard ID:
    
        leaderboard = Leaderboards.get_active_leaderboard_by_slug("weekly_kills")
        Leaderboards.submit_score(leaderboard.id, user_id, 10)
    
    ## Examples
    
        iex> submit_score(123, user_id, 10)
        {:ok, %Record{score: 10}}
    
        iex> submit_score(123, user_id, 5, %{weapon: "sword"})
        {:ok, %Record{score: 15, metadata: %{weapon: "sword"}}}
    
    `key:` (default `""`) is the ranking within the board the score goes to;
    the operator applies per key.
    
        iex> submit_score(123, user_id, 23, %{"game" => "match"}, key: "match|60")
        {:ok, %Record{key: "match|60", score: 23}}
    
  """
  @spec submit_score(String.t(), Ecto.UUID.t(), integer(), map(), keyword()) ::
          {:ok, Gamend.Leaderboards.Record.t()} | {:error, term()}
  def submit_score(_leaderboard_id, _user_id, _score, _metadata, _opts) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if reason = Application.get_env(:gamend_sdk, :stub_error),
          do: {:error, reason},
          else:
            {:ok,
             %Gamend.Leaderboards.Record{
               id: 0,
               leaderboard_id: 0,
               user_id: 0,
               label: nil,
               score: 0,
               rank: nil,
               metadata: %{},
               inserted_at: ~U[1970-01-01 00:00:00Z],
               updated_at: ~U[1970-01-01 00:00:00Z]
             }}

      _ ->
        raise "Gamend.Leaderboards.submit_score/5 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Updates an existing leaderboard.
    
    Note: `slug`, `sort_order`, and `operator` cannot be changed after creation.
    
    ## Attributes
    
    See `t:Gamend.Types.leaderboard_update_attrs/0` for available fields.
    
  """
  @spec update_leaderboard(
          Gamend.Leaderboards.Leaderboard.t(),
          Gamend.Types.leaderboard_update_attrs()
        ) ::
          {:ok, Gamend.Leaderboards.Leaderboard.t()} | {:error, Ecto.Changeset.t()}
  def update_leaderboard(_leaderboard, _attrs) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if reason = Application.get_env(:gamend_sdk, :stub_error),
          do: {:error, reason},
          else:
            {:ok,
             %Gamend.Leaderboards.Leaderboard{
               id: 0,
               slug: "",
               title: "",
               description: nil,
               sort_order: :desc,
               operator: :set,
               starts_at: nil,
               ends_at: nil,
               metadata: %{},
               inserted_at: ~U[1970-01-01 00:00:00Z],
               updated_at: ~U[1970-01-01 00:00:00Z]
             }}

      _ ->
        raise "Gamend.Leaderboards.update_leaderboard/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Updates an existing record.
    
    Intended for internal/admin usage.
    
  """
  @spec update_record(Gamend.Leaderboards.Record.t(), map()) ::
          {:ok, Gamend.Leaderboards.Record.t()} | {:error, Ecto.Changeset.t()}
  def update_record(_record, _attrs) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if reason = Application.get_env(:gamend_sdk, :stub_error),
          do: {:error, reason},
          else:
            {:ok,
             %Gamend.Leaderboards.Record{
               id: 0,
               leaderboard_id: 0,
               user_id: 0,
               label: nil,
               score: 0,
               rank: nil,
               metadata: %{},
               inserted_at: ~U[1970-01-01 00:00:00Z],
               updated_at: ~U[1970-01-01 00:00:00Z]
             }}

      _ ->
        raise "Gamend.Leaderboards.update_record/2 is a stub - only available at runtime on Gamend"
    end
  end
end
