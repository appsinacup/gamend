defmodule GameServer.Leaderboards do
  @moduledoc """
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

      # Get user's record (use leaderboard id)
      {:ok, record} = Leaderboards.get_user_record(leaderboard.id, user_id)
  """

  import Ecto.Query, warn: false
  use Nebulex.Caching, cache: GameServer.Cache
  alias GameServer.Repo
  alias GameServer.Types

  alias GameServer.Leaderboards.Leaderboard
  alias GameServer.Leaderboards.Record

  @leaderboards_cache_ttl_ms 60_000
  @records_cache_ttl_ms 10_000

  defp leaderboards_cache_version do
    GameServer.Cache.get!({:leaderboards, :version}) || 1
  end

  defp records_cache_version(leaderboard_id) when is_binary(leaderboard_id) do
    GameServer.Cache.get!({:leaderboards, :records_version, leaderboard_id}) || 1
  end

  defp record_cache_version(record_id) when is_binary(record_id) do
    GameServer.Cache.get!({:leaderboards, :record_version, record_id}) || 1
  end

  defp invalidate_leaderboards_cache do
    _ = GameServer.Cache.bump_version({:leaderboards, :version})
    :ok
  end

  defp invalidate_records_cache(leaderboard_id) when is_binary(leaderboard_id) do
    _ = GameServer.Cache.bump_version({:leaderboards, :records_version, leaderboard_id})
    :ok
  end

  defp invalidate_record_cache(record_id) when is_binary(record_id) do
    _ = GameServer.Cache.bump_version({:leaderboards, :record_version, record_id})
    :ok
  end

  defp cache_ok({:ok, _}), do: true
  defp cache_ok(_), do: false

  # ---------------------------------------------------------------------------
  # Leaderboard CRUD
  # ---------------------------------------------------------------------------

  @doc """
  Creates a new leaderboard.

  ## Attributes

  See `t:GameServer.Types.leaderboard_create_attrs/0` for available fields.

  ## Examples

      iex> create_leaderboard(%{slug: "my_lb", title: "My Leaderboard"})
      {:ok, %Leaderboard{}}

      iex> create_leaderboard(%{slug: "", title: ""})
      {:error, %Ecto.Changeset{}}
  """
  @spec create_leaderboard(Types.leaderboard_create_attrs()) ::
          {:ok, Leaderboard.t()} | {:error, Ecto.Changeset.t()}
  def create_leaderboard(attrs) do
    %Leaderboard{}
    |> Leaderboard.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, _lb} = ok ->
        _ = invalidate_leaderboards_cache()
        ok

      other ->
        other
    end
  end

  @doc """
  Updates an existing leaderboard.

  Note: `slug`, `sort_order`, and `operator` cannot be changed after creation.

  ## Attributes

  See `t:GameServer.Types.leaderboard_update_attrs/0` for available fields.
  """
  @spec update_leaderboard(Leaderboard.t(), Types.leaderboard_update_attrs()) ::
          {:ok, Leaderboard.t()} | {:error, Ecto.Changeset.t()}
  def update_leaderboard(%Leaderboard{} = leaderboard, attrs) do
    leaderboard
    |> Leaderboard.update_changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, lb} = ok ->
        _ = invalidate_leaderboards_cache()
        _ = invalidate_records_cache(lb.id)
        ok

      other ->
        other
    end
  end

  @doc """
  Deletes a leaderboard and all its records.
  """
  @spec delete_leaderboard(Leaderboard.t()) ::
          {:ok, Leaderboard.t()} | {:error, Ecto.Changeset.t()}
  def delete_leaderboard(%Leaderboard{} = leaderboard) do
    Repo.delete(leaderboard)
    |> case do
      {:ok, lb} = ok ->
        _ = invalidate_leaderboards_cache()
        _ = invalidate_records_cache(lb.id)
        ok

      other ->
        other
    end
  end

  @doc """
  Gets a leaderboard by its UUID, or the active leaderboard by slug.

  ## Examples

      iex> get_leaderboard("0198c0de-...")
      %Leaderboard{}

      iex> get_leaderboard(Ecto.UUID.generate())
      nil
  """
  @spec get_leaderboard(String.t()) :: Leaderboard.t() | nil
  def get_leaderboard(id_or_slug) when is_binary(id_or_slug) do
    case Ecto.UUID.cast(id_or_slug) do
      {:ok, id} -> get_leaderboard_cached(id)
      :error -> get_active_leaderboard_by_slug(id_or_slug)
    end
  end

  @doc """
  Gets a leaderboard by its ID. Raises if not found.
  """
  @spec get_leaderboard!(String.t()) :: Leaderboard.t()
  def get_leaderboard!(id) when is_binary(id) do
    case get_leaderboard(id) do
      %Leaderboard{} = lb -> lb
      nil -> raise Ecto.NoResultsError, queryable: Leaderboard
    end
  end

  @decorate cacheable(
              key: {:leaderboards, :get, leaderboards_cache_version(), id},
              opts: [ttl: @leaderboards_cache_ttl_ms]
            )
  defp get_leaderboard_cached(id) when is_binary(id) do
    Repo.get(Leaderboard, id)
  end

  @doc """
  Gets the currently active leaderboard with the given slug.
  Returns `nil` if no active leaderboard exists.

  An active leaderboard is one that:
  - Has not ended (`ends_at` is nil or in the future)
  - Has started (`starts_at` is nil or in the past)

  If multiple active leaderboards exist with the same slug,
  returns the most recently created one.
  """
  @spec get_active_leaderboard_by_slug(String.t()) :: Leaderboard.t() | nil
  def get_active_leaderboard_by_slug(slug) when is_binary(slug) do
    get_active_leaderboard_by_slug_cached(slug)
  end

  # Short TTL: this depends on DateTime.utc_now/0 (leaderboard can become active/inactive over time)
  @decorate cacheable(
              key: {:leaderboards, :active_by_slug, leaderboards_cache_version(), slug},
              opts: [ttl: @records_cache_ttl_ms]
            )
  defp get_active_leaderboard_by_slug_cached(slug) when is_binary(slug) do
    now = DateTime.utc_now()

    from(lb in Leaderboard,
      where: lb.slug == ^slug,
      where: is_nil(lb.ends_at) or lb.ends_at > ^now,
      where: is_nil(lb.starts_at) or lb.starts_at <= ^now,
      order_by: [desc: lb.inserted_at, desc: lb.id],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
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
  @spec resolve_slugs([String.t()]) :: %{String.t() => Leaderboard.t()}
  def resolve_slugs([]), do: %{}

  def resolve_slugs(slugs) when is_list(slugs) do
    now = DateTime.utc_now()
    unique_slugs = Enum.uniq(slugs)

    # Subquery: for each slug, find the most recently created active leaderboard
    ranked =
      from(lb in Leaderboard,
        where: lb.slug in ^unique_slugs,
        where: is_nil(lb.ends_at) or lb.ends_at > ^now,
        where: is_nil(lb.starts_at) or lb.starts_at <= ^now,
        select: %{
          id: lb.id,
          slug: lb.slug,
          row_number:
            over(row_number(),
              partition_by: lb.slug,
              order_by: [desc: lb.inserted_at, desc: lb.id]
            )
        }
      )

    from(lb in Leaderboard,
      join: r in subquery(ranked),
      on: lb.id == r.id and r.row_number == 1
    )
    |> Repo.all()
    |> Map.new(fn lb -> {lb.slug, lb} end)
  end

  @doc """
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
  @spec list_leaderboard_groups(keyword()) :: [map()]
  def list_leaderboard_groups(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 25)

    list_leaderboard_groups_cached(page, page_size)
  end

  @decorate cacheable(
              key: {:leaderboards, :list_groups, leaderboards_cache_version(), page, page_size},
              opts: [ttl: @leaderboards_cache_ttl_ms]
            )
  defp list_leaderboard_groups_cached(page, page_size) do
    offset = max((page - 1) * page_size, 0)

    # Get unique slugs ordered by most recent end date (nulls first = still active)
    slugs_query =
      from lb in Leaderboard,
        select: lb.slug,
        group_by: lb.slug,
        order_by: [desc_nulls_first: max(lb.ends_at)],
        offset: ^offset,
        limit: ^page_size

    slugs = Repo.all(slugs_query)

    # For each slug, get the group info
    Enum.map(slugs, fn slug ->
      build_group_info(slug)
    end)
  end

  defp build_group_info(slug) do
    now = DateTime.utc_now()

    # Get the latest leaderboard by end date (nulls first = active/permanent ones)
    latest =
      from(lb in Leaderboard,
        where: lb.slug == ^slug,
        order_by: [desc_nulls_first: lb.ends_at],
        limit: 1
      )
      |> Repo.one()

    # Get the active leaderboard (if any)
    active =
      from(lb in Leaderboard,
        where: lb.slug == ^slug,
        where: is_nil(lb.ends_at) or lb.ends_at > ^now,
        where: is_nil(lb.starts_at) or lb.starts_at <= ^now,
        order_by: [desc_nulls_first: lb.ends_at],
        limit: 1
      )
      |> Repo.one()

    # Count seasons
    season_count =
      from(lb in Leaderboard, where: lb.slug == ^slug)
      |> Repo.aggregate(:count, :id)

    %{
      slug: slug,
      title: latest.title,
      description: latest.description,
      icon_url: latest.icon_url,
      metadata: latest.metadata,
      active_id: active && active.id,
      latest_id: latest.id,
      season_count: season_count
    }
  end

  @doc """
  Counts unique leaderboard slugs.
  """
  @spec count_leaderboard_groups() :: non_neg_integer()
  def count_leaderboard_groups do
    count_leaderboard_groups_cached()
  end

  @decorate cacheable(
              key: {:leaderboards, :count_groups, leaderboards_cache_version()},
              opts: [ttl: @leaderboards_cache_ttl_ms]
            )
  defp count_leaderboard_groups_cached do
    from(lb in Leaderboard,
      select: count(lb.slug, :distinct)
    )
    |> Repo.one()
  end

  @doc """
  Lists all leaderboards with the given slug (all seasons), ordered by end date.
  """
  @spec list_leaderboards_by_slug(String.t()) :: [Leaderboard.t()]
  @spec list_leaderboards_by_slug(String.t(), keyword()) :: [Leaderboard.t()]
  def list_leaderboards_by_slug(slug, opts \\ []) when is_binary(slug) do
    opts
    |> Keyword.put(:slug, slug)
    |> Keyword.put_new(:order_by, :ends_at)
    |> list_leaderboards()
  end

  @doc """
  Lists leaderboards with optional filters.

  ## Options

    * `:slug` - Filter by slug (returns all seasons of that leaderboard)
    * `:active` - If `true`, only active leaderboards. If `false`, only ended.
    * `:order_by` - Order by field: `:ends_at` or `:inserted_at` (default)
    * `:starts_after` - Only leaderboards that started after this DateTime
    * `:starts_before` - Only leaderboards that started before this DateTime
    * `:ends_after` - Only leaderboards that end after this DateTime
    * `:ends_before` - Only leaderboards that end before this DateTime
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
  @spec list_leaderboards() :: [Leaderboard.t()]
  @spec list_leaderboards(keyword()) :: [Leaderboard.t()]
  def list_leaderboards(opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 25)
    order_by = Keyword.get(opts, :order_by, :inserted_at)

    list_leaderboards_cached(opts, order_by, page, page_size)
  end

  @decorate cacheable(
              key:
                {:leaderboards, :list, leaderboards_cache_version(), opts, order_by, page,
                 page_size},
              opts: [ttl: @leaderboards_cache_ttl_ms]
            )
  defp list_leaderboards_cached(opts, order_by, page, page_size) do
    offset = max((page - 1) * page_size, 0)

    opts
    |> build_leaderboard_query()
    |> apply_order_by(order_by)
    |> offset(^offset)
    |> limit(^page_size)
    |> Repo.all()
  end

  @doc """
  Counts leaderboards matching the given filters.

  Accepts the same filter options as `list_leaderboards/1`.
  """
  @spec count_leaderboards() :: non_neg_integer()
  @spec count_leaderboards(keyword()) :: non_neg_integer()
  def count_leaderboards(opts \\ []) do
    count_leaderboards_cached(opts)
  end

  @decorate cacheable(
              key: {:leaderboards, :count, leaderboards_cache_version(), opts},
              opts: [ttl: @leaderboards_cache_ttl_ms]
            )
  defp count_leaderboards_cached(opts) do
    opts
    |> build_leaderboard_query()
    |> Repo.aggregate(:count, :id)
  end

  defp apply_order_by(query, :ends_at) do
    order_by(query, [lb], desc_nulls_first: lb.ends_at)
  end

  defp apply_order_by(query, :inserted_at) do
    order_by(query, [lb], desc: lb.inserted_at)
  end

  defp apply_order_by(query, _), do: order_by(query, [lb], desc: lb.inserted_at)

  defp build_leaderboard_query(opts) do
    now = DateTime.utc_now()
    base = from(lb in Leaderboard)

    base
    |> maybe_filter_slug(Keyword.get(opts, :slug))
    |> maybe_filter_active(Keyword.get(opts, :active), now)
    |> maybe_filter_starts_after(Keyword.get(opts, :starts_after))
    |> maybe_filter_starts_before(Keyword.get(opts, :starts_before))
    |> maybe_filter_ends_after(Keyword.get(opts, :ends_after))
    |> maybe_filter_ends_before(Keyword.get(opts, :ends_before))
  end

  defp maybe_filter_slug(query, nil), do: query
  defp maybe_filter_slug(query, slug), do: from(lb in query, where: lb.slug == ^slug)

  defp maybe_filter_active(query, nil, _now), do: query

  defp maybe_filter_active(query, true, now) do
    from(lb in query, where: is_nil(lb.ends_at) or lb.ends_at > ^now)
  end

  defp maybe_filter_active(query, false, now) do
    from(lb in query, where: not is_nil(lb.ends_at) and lb.ends_at <= ^now)
  end

  defp maybe_filter_starts_after(query, nil), do: query

  defp maybe_filter_starts_after(query, datetime) do
    from(lb in query, where: lb.starts_at > ^datetime)
  end

  defp maybe_filter_starts_before(query, nil), do: query

  defp maybe_filter_starts_before(query, datetime) do
    from(lb in query, where: lb.starts_at <= ^datetime)
  end

  defp maybe_filter_ends_after(query, nil), do: query

  defp maybe_filter_ends_after(query, datetime) do
    from(lb in query, where: lb.ends_at > ^datetime)
  end

  defp maybe_filter_ends_before(query, nil), do: query

  defp maybe_filter_ends_before(query, datetime) do
    from(lb in query, where: lb.ends_at <= ^datetime)
  end

  @doc """
  Ends a leaderboard by setting `ends_at` to the current time.
  """
  @spec end_leaderboard(Leaderboard.t() | String.t()) ::
          {:ok, Leaderboard.t()} | {:error, Ecto.Changeset.t() | :not_found}
  def end_leaderboard(%Leaderboard{} = leaderboard) do
    update_leaderboard(leaderboard, %{ends_at: DateTime.utc_now(:second)})
  end

  def end_leaderboard(id_or_slug) when is_binary(id_or_slug) do
    leaderboard = get_leaderboard(id_or_slug)

    case leaderboard do
      nil -> {:error, :not_found}
      %Leaderboard{} = lb -> end_leaderboard(lb)
    end
  end

  @doc """
  Returns a changeset for a leaderboard (used in forms).
  """
  @spec change_leaderboard(Leaderboard.t()) :: Ecto.Changeset.t()
  @spec change_leaderboard(Leaderboard.t(), map()) :: Ecto.Changeset.t()
  def change_leaderboard(%Leaderboard{} = leaderboard, attrs \\ %{}) do
    Leaderboard.changeset(leaderboard, attrs)
  end

  # ---------------------------------------------------------------------------
  # Score Submission (Server-Only)
  # ---------------------------------------------------------------------------

  @doc """
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
  """
  @spec submit_score(String.t(), Ecto.UUID.t(), integer()) :: {:ok, Record.t()} | {:error, term()}
  @spec submit_score(String.t(), Ecto.UUID.t(), integer(), map()) ::
          {:ok, Record.t()} | {:error, term()}
  def submit_score(leaderboard_id, user_id, score, metadata \\ %{})
      when is_binary(leaderboard_id) and is_binary(user_id) and is_integer(score) do
    case get_leaderboard(leaderboard_id) do
      nil ->
        {:error, :leaderboard_not_found}

      leaderboard ->
        # Check if leaderboard is still active
        if Leaderboard.ended?(leaderboard) do
          {:error, :leaderboard_ended}
        else
          do_submit_score(leaderboard, user_id, score, metadata)
          |> run_after_score_submitted()
        end
    end
  end

  @doc """
  Submit a score for a label-based (non-user) record.

  Works just like `submit_score/4` but uses a string label instead of a user ID.
  This is useful for statistics, rankings by category, etc.

  ## Examples

      iex> submit_label_score(leaderboard_id, "English", 42)
      {:ok, %Record{label: "English", score: 42}}
  """
  @spec submit_label_score(String.t(), String.t(), integer(), map()) ::
          {:ok, Record.t()} | {:error, term()}
  def submit_label_score(leaderboard_id, label, score, metadata \\ %{})
      when is_binary(leaderboard_id) and is_binary(label) and is_integer(score) do
    case get_leaderboard(leaderboard_id) do
      nil ->
        {:error, :leaderboard_not_found}

      leaderboard ->
        if Leaderboard.ended?(leaderboard) do
          {:error, :leaderboard_ended}
        else
          do_submit_label_score(leaderboard, label, score, metadata)
          |> run_after_score_submitted()
        end
    end
  end

  defp run_after_score_submitted({:ok, record} = result) do
    GameServer.Async.run(fn ->
      GameServer.Hooks.internal_call(:after_score_submitted, [record])

      GameServer.Quests.report_event(record.user_id, "score_submitted", 1, %{
        "leaderboard_id" => record.leaderboard_id
      })
    end)

    result
  end

  defp run_after_score_submitted(other), do: other

  defp do_submit_label_score(leaderboard, label, score, metadata) do
    now = DateTime.utc_now(:second)

    changeset =
      %Record{}
      |> Record.changeset(%{
        leaderboard_id: leaderboard.id,
        label: label,
        score: score,
        metadata: metadata
      })

    case Repo.insert(changeset,
           on_conflict: build_score_upsert(leaderboard, score, metadata, now),
           conflict_target: [:leaderboard_id, :label]
         ) do
      {:ok, _} ->
        _ = invalidate_records_cache(leaderboard.id)
        record = get_label_record(leaderboard.id, label)

        if record do
          _ = invalidate_record_cache(record.id)
          {:ok, record}
        else
          {:error, :insert_failed}
        end

      error ->
        error
    end
  end

  @doc """
  Gets a single record by leaderboard ID and label.
  """
  @spec get_label_record(Ecto.UUID.t(), String.t()) :: Record.t() | nil
  def get_label_record(leaderboard_id, label)
      when is_binary(leaderboard_id) and is_binary(label) do
    from(r in Record,
      where: r.leaderboard_id == ^leaderboard_id and r.label == ^label
    )
    |> Repo.one()
  end

  defp do_submit_score(leaderboard, user_id, score, metadata) do
    now = DateTime.utc_now(:second)

    changeset =
      %Record{}
      |> Record.changeset(%{
        leaderboard_id: leaderboard.id,
        user_id: user_id,
        score: score,
        metadata: metadata
      })

    case Repo.insert(changeset,
           on_conflict: build_score_upsert(leaderboard, score, metadata, now),
           conflict_target: [:leaderboard_id, :user_id]
         ) do
      {:ok, _} ->
        # Invalidate caches and re-fetch to get accurate data after upsert
        _ = invalidate_records_cache(leaderboard.id)
        record = get_record(leaderboard.id, user_id)

        if record do
          _ = invalidate_record_cache(record.id)
          {:ok, record}
        else
          {:error, :insert_failed}
        end

      error ->
        error
    end
  end

  defp build_score_upsert(%{operator: :set}, score, metadata, now) do
    from(r in Record,
      update: [set: [score: ^score, metadata: ^metadata, updated_at: ^now]]
    )
  end

  defp build_score_upsert(%{operator: :best, sort_order: :desc}, score, _metadata, now) do
    from(r in Record,
      update: [
        set: [
          score: fragment("CASE WHEN ? >= ? THEN ? ELSE ? END", r.score, ^score, r.score, ^score),
          metadata:
            fragment(
              "CASE WHEN ? >= ? THEN ? ELSE excluded.\"metadata\" END",
              r.score,
              ^score,
              r.metadata
            ),
          updated_at: ^now
        ]
      ]
    )
  end

  defp build_score_upsert(%{operator: :best, sort_order: :asc}, score, _metadata, now) do
    from(r in Record,
      update: [
        set: [
          score: fragment("CASE WHEN ? <= ? THEN ? ELSE ? END", r.score, ^score, r.score, ^score),
          metadata:
            fragment(
              "CASE WHEN ? <= ? THEN ? ELSE excluded.\"metadata\" END",
              r.score,
              ^score,
              r.metadata
            ),
          updated_at: ^now
        ]
      ]
    )
  end

  defp build_score_upsert(%{operator: :incr}, score, metadata, now) do
    from(r in Record,
      update: [
        set: [score: fragment("? + ?", r.score, ^score), metadata: ^metadata, updated_at: ^now]
      ]
    )
  end

  defp build_score_upsert(%{operator: :decr}, score, metadata, now) do
    from(r in Record,
      update: [
        set: [score: fragment("? - ?", r.score, ^score), metadata: ^metadata, updated_at: ^now]
      ]
    )
  end

  # ---------------------------------------------------------------------------
  # Record Queries
  # ---------------------------------------------------------------------------

  @doc """
  Gets a record by its ID. Raises if not found.

  Intended for internal/admin usage.
  """
  @spec get_record!(Ecto.UUID.t()) :: Record.t()
  @decorate cacheable(
              key: {:leaderboards, :record, record_cache_version(id), id},
              opts: [ttl: @records_cache_ttl_ms]
            )
  def get_record!(id) when is_binary(id) do
    Repo.get_uuid!(Record, id)
  end

  @doc """
  Updates an existing record.

  Intended for internal/admin usage.
  """
  @spec update_record(Record.t(), map()) :: {:ok, Record.t()} | {:error, Ecto.Changeset.t()}
  def update_record(%Record{} = record, attrs) when is_map(attrs) do
    record
    |> Record.update_changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated} = ok ->
        _ = invalidate_records_cache(updated.leaderboard_id)
        _ = invalidate_record_cache(updated.id)
        ok

      other ->
        other
    end
  end

  @doc """
  Gets a single record by leaderboard ID and user ID.
  """
  @spec get_record(Ecto.UUID.t(), Ecto.UUID.t()) :: Record.t() | nil
  def get_record(leaderboard_id, user_id) when is_binary(leaderboard_id) do
    from(r in Record,
      where: r.leaderboard_id == ^leaderboard_id and r.user_id == ^user_id,
      preload: [:user]
    )
    |> Repo.one()
  end

  @doc """
  Gets a user's record with their rank.
  Returns `{:ok, record_with_rank}` or `{:error, :not_found}`.
  """
  @spec get_user_record(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, Record.t()} | {:error, :not_found}
  def get_user_record(leaderboard_id, user_id) when is_binary(leaderboard_id) do
    get_user_record_cached(leaderboard_id, user_id)
  end

  @decorate cacheable(
              key:
                {:leaderboards, :user_record, records_cache_version(leaderboard_id),
                 leaderboard_id, user_id},
              match: &cache_ok/1,
              opts: [ttl: @records_cache_ttl_ms]
            )
  defp get_user_record_cached(leaderboard_id, user_id)
       when is_binary(leaderboard_id) and is_binary(user_id) do
    case get_leaderboard(leaderboard_id) do
      nil ->
        {:error, :not_found}

      leaderboard ->
        case get_record(leaderboard.id, user_id) do
          nil ->
            {:error, :not_found}

          record ->
            rank = calculate_rank(leaderboard.id, record.score, record.inserted_at)
            {:ok, %{record | rank: rank}}
        end
    end
  end

  defp calculate_rank(leaderboard_id, score, inserted_at)
       when is_binary(leaderboard_id) do
    case get_leaderboard(leaderboard_id) do
      nil ->
        1

      leaderboard ->
        query =
          case leaderboard.sort_order do
            :desc ->
              from r in Record,
                where:
                  r.leaderboard_id == ^leaderboard_id and
                    (r.score > ^score or (r.score == ^score and r.inserted_at < ^inserted_at)),
                select: count(r.id)

            :asc ->
              from r in Record,
                where:
                  r.leaderboard_id == ^leaderboard_id and
                    (r.score < ^score or (r.score == ^score and r.inserted_at < ^inserted_at)),
                select: count(r.id)
          end

        Repo.one(query) + 1
    end
  end

  @doc """
  Lists records for a leaderboard, ordered by rank.

  ## Options

  See `t:GameServer.Types.pagination_opts/0` for available options.

  Returns records with `rank` field populated.
  """
  @spec list_records(String.t()) :: [Record.t()]
  @spec list_records(String.t(), Types.pagination_opts()) :: [Record.t()]
  def list_records(leaderboard_id, opts \\ []) when is_binary(leaderboard_id) do
    case get_leaderboard(leaderboard_id) do
      nil ->
        []

      leaderboard ->
        page = Keyword.get(opts, :page, 1)
        page_size = Keyword.get(opts, :page_size, 25)

        case search_pattern(opts) do
          nil ->
            list_records_cached(leaderboard.id, leaderboard.sort_order, page, page_size)

          pattern ->
            search_records(leaderboard.id, leaderboard.sort_order, pattern, page, page_size)
        end
    end
  end

  # Searches are unbounded strings, so they bypass the cache rather than filling
  # it with one entry per term anyone ever typed.
  defp search_records(leaderboard_id, sort_order, pattern, page, page_size) do
    offset = max((page - 1) * page_size, 0)

    ranked =
      from(r in Record,
        where: r.leaderboard_id == ^leaderboard_id,
        select: %{id: r.id, rank: over(row_number(), :ranking)},
        windows: [ranking: [order_by: ^record_order(sort_order)]]
      )

    from(r in Record,
      as: :record,
      join: ranked in subquery(ranked),
      on: ranked.id == r.id,
      left_join: u in assoc(r, :user),
      as: :user,
      where: ^name_match(pattern),
      order_by: [asc: ranked.rank],
      offset: ^offset,
      limit: ^page_size,
      select: {r, ranked.rank}
    )
    |> Repo.all()
    |> Enum.map(fn {record, rank} -> %{record | rank: rank} end)
    |> Repo.preload(:user)
  end

  # Matches the label a record shows publicly: its own label, or the user behind it.
  defp name_match(pattern) do
    dynamic(
      [record: r, user: u],
      fragment("lower(coalesce(?, '')) LIKE ? ESCAPE '\\'", r.label, ^pattern) or
        fragment("lower(coalesce(?, '')) LIKE ? ESCAPE '\\'", u.display_name, ^pattern) or
        fragment("lower(coalesce(?, '')) LIKE ? ESCAPE '\\'", u.username, ^pattern)
    )
  end

  defp search_pattern(opts), do: Repo.search_pattern(Keyword.get(opts, :search))

  defp record_order(:desc), do: [desc: :score, asc: :inserted_at]
  defp record_order(:asc), do: [asc: :score, asc: :inserted_at]

  @decorate cacheable(
              key:
                {:leaderboards, :list_records, records_cache_version(leaderboard_id),
                 leaderboard_id, sort_order, page, page_size},
              opts: [ttl: @records_cache_ttl_ms]
            )
  defp list_records_cached(leaderboard_id, sort_order, page, page_size)
       when is_binary(leaderboard_id) and is_integer(page) and is_integer(page_size) do
    offset = max((page - 1) * page_size, 0)

    records =
      from(r in Record,
        where: r.leaderboard_id == ^leaderboard_id,
        order_by: ^record_order(sort_order),
        offset: ^offset,
        limit: ^page_size,
        preload: [:user]
      )
      |> Repo.all()

    # Add rank to each record
    records
    |> Enum.with_index(offset + 1)
    |> Enum.map(fn {record, rank} -> %{record | rank: rank} end)
  end

  @doc """
  Counts records for a leaderboard.
  """
  @spec count_records(Ecto.UUID.t()) :: non_neg_integer()
  @spec count_records(Ecto.UUID.t(), keyword()) :: non_neg_integer()
  def count_records(leaderboard_id, opts \\ []) when is_binary(leaderboard_id) do
    case search_pattern(opts) do
      nil ->
        count_records_cached(leaderboard_id)

      pattern ->
        from(r in Record,
          as: :record,
          left_join: u in assoc(r, :user),
          as: :user,
          where: r.leaderboard_id == ^leaderboard_id,
          where: ^name_match(pattern)
        )
        |> Repo.aggregate(:count, :id)
    end
  end

  @decorate cacheable(
              key:
                {:leaderboards, :count_records, records_cache_version(leaderboard_id),
                 leaderboard_id},
              opts: [ttl: @records_cache_ttl_ms]
            )
  defp count_records_cached(leaderboard_id) when is_binary(leaderboard_id) do
    from(r in Record, where: r.leaderboard_id == ^leaderboard_id)
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Count all leaderboard records across all leaderboards.
  """
  @spec count_all_records() :: non_neg_integer()
  def count_all_records do
    from(r in Record)
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  Lists records around a specific user (centered on their position).

  Returns records above and below the user's rank.

  ## Options

    * `:limit` - Total number of records to return (default 11, centered on user)
  """
  @spec list_records_around_user(String.t(), Ecto.UUID.t()) :: [Record.t()]
  @spec list_records_around_user(String.t(), Ecto.UUID.t(), keyword()) :: [Record.t()]
  def list_records_around_user(leaderboard_id, user_id, opts \\ [])
      when is_binary(leaderboard_id) do
    case get_leaderboard(leaderboard_id) do
      nil ->
        []

      leaderboard ->
        limit = Keyword.get(opts, :limit, 11)

        list_records_around_user_cached(leaderboard.id, leaderboard.sort_order, user_id, limit)
    end
  end

  @decorate cacheable(
              key:
                {:leaderboards, :around_user, records_cache_version(leaderboard_id),
                 leaderboard_id, sort_order, user_id, limit},
              opts: [ttl: @records_cache_ttl_ms]
            )
  defp list_records_around_user_cached(leaderboard_id, sort_order, user_id, limit)
       when is_binary(leaderboard_id) and is_binary(user_id) and is_integer(limit) do
    half = div(limit, 2)

    case get_user_record(leaderboard_id, user_id) do
      {:error, :not_found} ->
        []

      {:ok, user_record} ->
        user_rank = user_record.rank

        # Calculate offset to center on user
        start_rank = max(1, user_rank - half)
        offset = start_rank - 1

        order_by =
          case sort_order do
            :desc -> [desc: :score, asc: :inserted_at]
            :asc -> [asc: :score, asc: :inserted_at]
          end

        records =
          from(r in Record,
            where: r.leaderboard_id == ^leaderboard_id,
            order_by: ^order_by,
            offset: ^offset,
            limit: ^limit,
            preload: [:user]
          )
          |> Repo.all()

        # Add rank to each record
        records
        |> Enum.with_index(start_rank)
        |> Enum.map(fn {record, rank} -> %{record | rank: rank} end)
    end
  end

  @doc """
  Deletes a record.
  """
  @spec delete_record(Record.t()) :: {:ok, Record.t()} | {:error, Ecto.Changeset.t()}
  def delete_record(%Record{} = record) do
    Repo.delete(record)
    |> case do
      {:ok, rec} = ok ->
        _ = invalidate_records_cache(rec.leaderboard_id)
        _ = invalidate_record_cache(rec.id)
        ok

      other ->
        other
    end
  end

  @doc """
  Deletes a user's record from a leaderboard.
  Accepts either leaderboard ID or slug (both strings).
  """
  @spec delete_user_record(String.t(), Ecto.UUID.t()) ::
          {:ok, Record.t()} | {:error, :not_found}
  def delete_user_record(id_or_slug, user_id) do
    leaderboard = get_leaderboard(id_or_slug)

    case leaderboard do
      nil ->
        {:error, :not_found}

      %Leaderboard{} = leaderboard ->
        case get_record(leaderboard.id, user_id) do
          nil ->
            {:error, :not_found}

          record ->
            delete_record(record)
            |> case do
              {:ok, _} = ok ->
                _ = invalidate_records_cache(leaderboard.id)
                ok

              other ->
                other
            end
        end
    end
  end

  @doc """
  Returns a changeset for a record (used in admin forms).
  """
  @spec change_record(Record.t()) :: Ecto.Changeset.t()
  @spec change_record(Record.t(), map()) :: Ecto.Changeset.t()
  def change_record(%Record{} = record, attrs \\ %{}) do
    Record.changeset(record, attrs)
  end
end
