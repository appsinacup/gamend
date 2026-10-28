defmodule Gamend.Leaderboards do
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
  """

  import Ecto.Query, warn: false
  use Nebulex.Caching, cache: Gamend.Cache
  alias Gamend.Repo
  alias Gamend.Types

  alias Gamend.AccountRequired
  alias Gamend.Accounts
  alias Gamend.Accounts.User
  alias Gamend.Leaderboards.Leaderboard
  alias Gamend.Leaderboards.Record
  alias Gamend.Repo.AdvisoryLock
  alias Gamend.UUIDv7

  require Logger

  @records_cache_ttl_ms 10_000

  # Name of the ranking CTE used by `list_records_around_user/3`. One
  # attribute because the name has to match in three places — the `with_cte`
  # that defines it, the join that reads it, and the subquery that finds the
  # caller's row in it.
  @rank_cte "leaderboard_ranks"

  defp leaderboards_cache_version do
    Gamend.Cache.get!({:leaderboards, :version}) || 1
  end

  defp records_cache_version(leaderboard_id) when is_binary(leaderboard_id) do
    Gamend.Cache.get!({:leaderboards, :records_version, leaderboard_id}) || 1
  end

  defp record_cache_version(record_id) when is_binary(record_id) do
    Gamend.Cache.get!({:leaderboards, :record_version, record_id}) || 1
  end

  @doc """
  Forget the cached leaderboard lookups.

  Every write in here does this already. It is public because a CALLER can also
  learn the cache is stale: `get_active_leaderboard_by_slug/1` is cached for a
  minute, so a board deleted (or rolled back, under a test sandbox) hands out an
  id whose row is gone, and the next `submit_score/4` fails on the foreign key.
  A caller that sees that can drop the lookup and try again rather than wait out
  the TTL.
  """
  @spec invalidate_cache() :: :ok
  def invalidate_cache, do: invalidate_leaderboards_cache()

  @doc """
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
  def host_action(slug, user_id) when is_binary(slug) do
    case Application.get_env(:gamend_core, :leaderboard_action) do
      {mod, fun} when is_atom(mod) and is_atom(fun) ->
        normalize_action(apply(mod, fun, [user_id, slug]))

      _ ->
        nil
    end
  end

  # A host answering nonsense means "no button", never a broken one or one
  # off the site.
  defp normalize_action({label, "/" <> rest = path}) when is_binary(label) and label != "" do
    if String.starts_with?(rest, ["/", "\\"]), do: nil, else: {label, path}
  end

  defp normalize_action(_action), do: nil

  defp invalidate_leaderboards_cache do
    _ = Gamend.Cache.bump_version({:leaderboards, :version})
    :ok
  end

  defp invalidate_records_cache(leaderboard_id) when is_binary(leaderboard_id) do
    _ = Gamend.Cache.bump_version({:leaderboards, :records_version, leaderboard_id})
    :ok
  end

  defp invalidate_record_cache(record_id) when is_binary(record_id) do
    _ = Gamend.Cache.bump_version({:leaderboards, :record_version, record_id})
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

  See `t:Gamend.Types.leaderboard_create_attrs/0` for available fields.

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

  See `t:Gamend.Types.leaderboard_update_attrs/0` for available fields.
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
        if all_time?(lb), do: rebuild_all_time(lb.slug)
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
    case Gamend.Parse.uuid(id_or_slug) do
      nil -> get_active_leaderboard_by_slug(id_or_slug)
      id -> get_leaderboard_cached(id)
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
              opts: [ttl: Gamend.Cache.ttl()]
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
    include_hidden = Keyword.get(opts, :include_hidden, false)

    list_leaderboard_groups_cached(page, page_size, include_hidden)
  end

  @decorate cacheable(
              key:
                {:leaderboards, :list_groups, leaderboards_cache_version(), page, page_size,
                 include_hidden},
              opts: [ttl: Gamend.Cache.ttl()]
            )
  defp list_leaderboard_groups_cached(page, page_size, include_hidden) do
    offset = max((page - 1) * page_size, 0)

    # Get unique slugs ordered by most recent end date (nulls first = still active)
    slugs_query =
      from lb in maybe_filter_hidden(Leaderboard, include_hidden),
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
  @spec count_leaderboard_groups(keyword()) :: non_neg_integer()
  def count_leaderboard_groups(opts \\ []) do
    count_leaderboard_groups_cached(Keyword.get(opts, :include_hidden, false))
  end

  @decorate cacheable(
              key: {:leaderboards, :count_groups, leaderboards_cache_version(), include_hidden},
              opts: [ttl: Gamend.Cache.ttl()]
            )
  defp count_leaderboard_groups_cached(include_hidden) do
    from(lb in maybe_filter_hidden(Leaderboard, include_hidden),
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
  @spec list_leaderboards() :: [Leaderboard.t()]
  @spec list_leaderboards(keyword()) :: [Leaderboard.t()]
  def list_leaderboards(opts \\ []) do
    # Clamped before the cached call: both values are in its cache key.
    page = Gamend.Limits.clamp_page(Keyword.get(opts, :page))
    page_size = Gamend.Limits.clamp_page_size(Keyword.get(opts, :page_size))
    order_by = Keyword.get(opts, :order_by, :inserted_at)

    list_leaderboards_cached(opts, order_by, page, page_size)
  end

  @decorate cacheable(
              key:
                {:leaderboards, :list, leaderboards_cache_version(), opts, order_by, page,
                 page_size},
              opts: [ttl: Gamend.Cache.ttl()]
            )
  defp list_leaderboards_cached(opts, order_by, page, page_size) do
    opts
    |> build_leaderboard_query()
    |> apply_order_by(order_by)
    |> Gamend.Query.page(page: page, page_size: page_size)
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
              opts: [ttl: Gamend.Cache.ttl()]
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
    |> maybe_filter_hidden(Keyword.get(opts, :include_hidden, false))
    |> maybe_filter_slug(Keyword.get(opts, :slug))
    |> maybe_filter_active(Keyword.get(opts, :active), now)
    |> maybe_filter_starts_after(Keyword.get(opts, :starts_after))
    |> maybe_filter_starts_before(Keyword.get(opts, :starts_before))
    |> maybe_filter_ends_after(Keyword.get(opts, :ends_after))
    |> maybe_filter_ends_before(Keyword.get(opts, :ends_before))
  end

  defp maybe_filter_hidden(query, true), do: query
  defp maybe_filter_hidden(query, _include), do: from(lb in query, where: lb.hidden == false)

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

  `key:` (default `""`) is the ranking within the board the score goes to;
  the operator applies per key.

      iex> submit_score(123, user_id, 23, %{"game" => "match"}, key: "match|60")
      {:ok, %Record{key: "match|60", score: 23}}
  """
  @spec submit_score(String.t(), Ecto.UUID.t(), integer()) :: {:ok, Record.t()} | {:error, term()}
  @spec submit_score(String.t(), Ecto.UUID.t(), integer(), map()) ::
          {:ok, Record.t()} | {:error, term()}
  @spec submit_score(String.t(), Ecto.UUID.t(), integer(), map(), keyword()) ::
          {:ok, Record.t()} | {:error, term()}
  def submit_score(leaderboard_id, user_id, score, metadata \\ %{}, opts \\ [])
      when is_binary(leaderboard_id) and is_binary(user_id) and is_integer(score) do
    with {:board, %Leaderboard{} = leaderboard} <- {:board, get_leaderboard(leaderboard_id)},
         # Checked before the insert, because SQLite cannot tell Ecto which
         # constraint an INSERT violated — see `Gamend.Accounts.user_exists?/1`.
         # Without this, a score for an unknown user raised
         # `Ecto.ConstraintError`, so an admin request naming a stale id got a
         # 500 rather than an answer.
         {:user, true} <- {:user, Accounts.user_exists?(user_id)},
         {:ended, false} <- {:ended, Leaderboard.ended?(leaderboard)} do
      leaderboard
      |> do_submit_score(user_id, score, metadata, key_opt(opts))
      |> run_after_score_submitted()
    else
      {:board, nil} -> {:error, :leaderboard_not_found}
      {:user, false} -> {:error, :user_not_found}
      {:ended, true} -> {:error, :leaderboard_ended}
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
  @spec submit_label_score(String.t(), String.t(), integer(), map(), keyword()) ::
          {:ok, Record.t()} | {:error, term()}
  def submit_label_score(leaderboard_id, label, score, metadata \\ %{}, opts \\ [])
      when is_binary(leaderboard_id) and is_binary(label) and is_integer(score) do
    case get_leaderboard(leaderboard_id) do
      nil ->
        {:error, :leaderboard_not_found}

      leaderboard ->
        if Leaderboard.ended?(leaderboard) do
          {:error, :leaderboard_ended}
        else
          do_submit_label_score(leaderboard, label, score, metadata, key_opt(opts))
          |> run_after_score_submitted()
        end
    end
  end

  defp run_after_score_submitted({:ok, record} = result) do
    Gamend.Async.run(fn ->
      Gamend.Hooks.internal_call(:after_score_submitted, [record])

      # Label entries carry no user — there is no one to advance a quest for.
      if is_binary(record.user_id) do
        Gamend.Quests.report_event(record.user_id, "score_submitted", 1, %{
          "leaderboard_id" => record.leaderboard_id
        })
      end
    end)

    result
  end

  defp run_after_score_submitted(other), do: other

  defp do_submit_label_score(leaderboard, label, score, metadata, key) do
    now = DateTime.utc_now(:second)

    changeset =
      %Record{}
      |> Record.changeset(%{
        leaderboard_id: leaderboard.id,
        label: label,
        key: key,
        score: score,
        metadata: metadata
      })

    # The board was checked before this, but it can still be deleted before
    # the write lands — see `Gamend.Repo.rescue_foreign_key/2`. A label record
    # references nothing else, so that is the only key that can fire.
    insert = fn ->
      Repo.insert(changeset,
        on_conflict: build_score_upsert(leaderboard, score, metadata, now),
        conflict_target: [:leaderboard_id, :label, :key]
      )
    end

    case Repo.rescue_foreign_key(:leaderboard_not_found, insert) do
      {:ok, _} ->
        _ = invalidate_records_cache(leaderboard.id)
        record = get_label_record(leaderboard.id, label, key)

        if record do
          _ = invalidate_record_cache(record.id)
          keep_all_time(leaderboard, record)
          {:ok, record}
        else
          {:error, :insert_failed}
        end

      error ->
        error
    end
  end

  @doc """
  Gets a single record by leaderboard ID, label and key (default `""`).
  """
  @spec get_label_record(Ecto.UUID.t(), String.t(), String.t()) :: Record.t() | nil
  def get_label_record(leaderboard_id, label, key \\ "")
      when is_binary(leaderboard_id) and is_binary(label) and is_binary(key) do
    from(r in Record,
      where: r.leaderboard_id == ^leaderboard_id and r.label == ^label and r.key == ^key
    )
    |> Repo.one()
  end

  # A submit's key: a string, `""` when none is given.
  defp key_opt(opts) do
    case Keyword.get(opts, :key, "") do
      key when is_binary(key) -> key
    end
  end

  defp do_submit_score(leaderboard, user_id, score, metadata, key) do
    now = DateTime.utc_now(:second)

    changeset =
      %Record{}
      |> Record.changeset(%{
        leaderboard_id: leaderboard.id,
        user_id: user_id,
        key: key,
        score: score,
        metadata: metadata
      })

    # Board and user were checked before this, but either can still be
    # deleted before the write lands — see `Gamend.Repo.rescue_foreign_key/2`.
    insert = fn ->
      Repo.insert(changeset,
        on_conflict: build_score_upsert(leaderboard, score, metadata, now),
        conflict_target: [:leaderboard_id, :user_id, :key]
      )
    end

    case Repo.rescue_foreign_key(:foreign_key, insert) do
      {:error, :foreign_key} ->
        # SQLite does not say which key fired, so ask again.
        if Accounts.user_exists?(user_id),
          do: {:error, :leaderboard_not_found},
          else: {:error, :user_not_found}

      {:ok, _} ->
        # Invalidate caches and re-fetch to get accurate data after upsert
        _ = invalidate_records_cache(leaderboard.id)
        record = get_record(leaderboard.id, user_id, key)

        if record do
          _ = invalidate_record_cache(record.id)
          keep_all_time(leaderboard, record)
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
  Gets a record by its ID, or `nil` when there is none (or `id` is not a UUID).

  Intended for internal/admin usage.
  """
  @spec get_record(Ecto.UUID.t()) :: Record.t() | nil
  @decorate cacheable(
              key: {:leaderboards, :record, record_cache_version(id), id},
              match: &(&1 != nil),
              opts: [ttl: @records_cache_ttl_ms]
            )
  def get_record(id) when is_binary(id), do: Repo.get_uuid(Record, id)

  @doc "Like `get_record/1`, but raises `Ecto.NoResultsError` when there is none."
  @spec get_record!(Ecto.UUID.t()) :: Record.t()
  def get_record!(id) when is_binary(id) do
    case get_record(id) do
      %Record{} = record -> record
      nil -> raise Ecto.NoResultsError, queryable: Record
    end
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
        refresh_all_time_of(updated)
        ok

      other ->
        other
    end
  end

  @doc """
  Gets a single record by leaderboard ID, user ID and key (default `""`).
  """
  @spec get_record(Ecto.UUID.t(), Ecto.UUID.t(), String.t()) :: Record.t() | nil
  def get_record(leaderboard_id, user_id, key \\ "")
      when is_binary(leaderboard_id) and is_binary(key) do
    from(r in Record,
      where: r.leaderboard_id == ^leaderboard_id and r.user_id == ^user_id and r.key == ^key,
      preload: [:user]
    )
    |> Repo.one()
  end

  @doc """
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
  def merge_user_records(from_user_id, to_user_id)
      when is_binary(from_user_id) and is_binary(to_user_id) and from_user_id != to_user_id do
    from(r in Record, where: r.user_id == ^from_user_id, preload: [:leaderboard])
    |> Repo.all()
    |> Enum.count(fn %Record{leaderboard: board} = record ->
      if board.operator in [:set, :decr] and get_record(board.id, to_user_id, record.key) do
        false
      else
        match?(
          {:ok, _},
          do_submit_score(board, to_user_id, record.score, record.metadata, record.key)
        )
      end
    end)
  end

  @doc """
  Gets a user's record with their rank (within its key: `key:`, default `""`).
  Returns `{:ok, record_with_rank}` or `{:error, :not_found}`.

  `all_time: true` answers their best row of every season, ranked all time
  (*All time* above).
  """
  @spec get_user_record(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, Record.t()} | {:error, :not_found}
  @spec get_user_record(Ecto.UUID.t(), Ecto.UUID.t(), keyword()) ::
          {:ok, Record.t()} | {:error, :not_found}
  def get_user_record(leaderboard_id, user_id, opts \\ []) when is_binary(leaderboard_id) do
    case read_board(leaderboard_id, opts) do
      nil -> {:error, :not_found}
      leaderboard -> get_user_record_cached(leaderboard, user_id, key_opt(opts))
    end
  end

  @decorate cacheable(
              key:
                {:leaderboards, :user_record, records_cache_version(leaderboard.id),
                 leaderboard.id, user_id, key},
              match: &cache_ok/1,
              opts: [ttl: @records_cache_ttl_ms]
            )
  defp get_user_record_cached(%Leaderboard{} = leaderboard, user_id, key)
       when is_binary(user_id) do
    case get_record(leaderboard.id, user_id, key) do
      nil ->
        {:error, :not_found}

      record ->
        rank = calculate_rank(leaderboard, record.score, record.inserted_at, key)
        {:ok, %{record | rank: rank, hidden: unlisted?(leaderboard, record)}}
    end
  end

  defp calculate_rank(
         %Leaderboard{id: leaderboard_id, sort_order: sort_order} = leaderboard,
         score,
         at,
         key,
         opts \\ []
       ) do
    from(r in Record,
      where: r.leaderboard_id == ^leaderboard_id and r.key == ^key,
      where: ^ahead(sort_order, score, at),
      select: count(r.id)
    )
    |> listed(leaderboard, opts)
    |> Repo.one()
    |> Kernel.+(1)
  end

  # The rows sorting ahead of `score` set at `at`: a better score, or the
  # same one set earlier, as `record_order/1` sorts them.
  defp ahead(:desc, score, at),
    do: dynamic([r], r.score > ^score or (r.score == ^score and r.inserted_at < ^at))

  defp ahead(:asc, score, at),
    do: dynamic([r], r.score < ^score or (r.score == ^score and r.inserted_at < ^at))

  # The rows sorting behind it: a worse score, or the same one set later.
  defp behind(:desc, score, at),
    do: dynamic([r], r.score < ^score or (r.score == ^score and r.inserted_at > ^at))

  defp behind(:asc, score, at),
    do: dynamic([r], r.score > ^score or (r.score == ^score and r.inserted_at > ^at))

  # ---------------------------------------------------------------------------
  # All time
  # ---------------------------------------------------------------------------

  @all_time_suffix "__all_time"

  @doc """
  Whether a board has an all-time ranking: a `:best` board with seasons (a
  start or an end date). *All time* above.
  """
  @spec all_time?(Leaderboard.t()) :: boolean()
  def all_time?(%Leaderboard{operator: :best, starts_at: starts_at, ends_at: ends_at}),
    do: not is_nil(starts_at) or not is_nil(ends_at)

  def all_time?(_leaderboard), do: false

  @doc """
  Fills the all-time board of `slug`'s seasons again from them (*All time*
  above). Reads make and fill it on their own the first time; this is for
  rows written around `submit_score/5`, such as a bulk import or
  `mix demo.seed`. Answers how many rows it holds, or `:error` when no board
  under `slug` has an all-time ranking.
  """
  @spec rebuild_all_time(String.t()) :: {:ok, non_neg_integer()} | :error
  def rebuild_all_time(slug) when is_binary(slug) do
    case newest_season(slug) do
      nil ->
        # The last season went: so does what was read from them.
        with %Leaderboard{} = board <- get_all_time_board(slug) do
          {:ok, _} = Repo.delete(board)
          _ = invalidate_leaderboards_cache()
        end

        :error

      season ->
        case with_all_time_lock(slug, fn -> fill_all_time(season) end) do
          {:ok, {%Leaderboard{}, rows}} -> {:ok, rows}
          _failed -> :error
        end
    end
  end

  defp newest_season(slug) do
    from(lb in Leaderboard,
      where: lb.slug == ^slug and lb.operator == :best,
      where: not is_nil(lb.starts_at) or not is_nil(lb.ends_at),
      order_by: [desc: lb.inserted_at],
      limit: 1
    )
    |> Repo.one()
  end

  # The board a read reads: the board itself, or with `all_time: true` its
  # seasons' all-time board, listed by the board's own rules (a public
  # board keeps its guests off All time too).
  defp read_board(leaderboard_id, opts) do
    case get_leaderboard(leaderboard_id) do
      %Leaderboard{} = leaderboard ->
        if Keyword.get(opts, :all_time) == true and all_time?(leaderboard),
          do: all_time_view(leaderboard),
          else: leaderboard

      nil ->
        nil
    end
  end

  defp all_time_view(%Leaderboard{} = season) do
    case all_time_board(season) do
      %Leaderboard{id: id} -> %{season | id: id}
      nil -> season
    end
  end

  # The hidden board holding each player's (and label's) best row of every
  # season under `season`'s slug, per key. Made and filled from the seasons
  # the first time it is asked for, under a lock so two first readers make
  # one; nil (logged) when it cannot be made, and the season reads alone.
  defp all_time_board(%Leaderboard{slug: slug} = season) do
    with nil <- get_all_time_board(slug) do
      case with_all_time_lock(slug, fn ->
             find_all_time_board(slug) || elem(fill_all_time(season), 0)
           end) do
        {:ok, %Leaderboard{} = board} ->
          board

        failed ->
          Logger.warning("no all-time board for #{slug}: #{inspect(failed)}")
          nil
      end
    end
  end

  # One builder per slug, across nodes (an advisory lock; SQLite's single
  # writer on one node), in a transaction with no time limit: a fill reads
  # every season's rows and `Repo.stream/2` needs the transaction.
  defp with_all_time_lock(slug, fun) do
    Gamend.AfterCommit.transaction(
      fn ->
        AdvisoryLock.lock("leaderboard_all_time", slug)
        fun.()
      end,
      timeout: :infinity
    )
  end

  @decorate cacheable(
              key: {:leaderboards, :all_time_board, leaderboards_cache_version(), slug},
              match: &(&1 != nil)
            )
  defp get_all_time_board(slug), do: find_all_time_board(slug)

  # By its slug, and only when it says whose it is: a board someone named
  # `x__all_time` by hand is not this one.
  defp find_all_time_board(slug) do
    from(lb in Leaderboard, where: lb.slug == ^(slug <> @all_time_suffix), limit: 1)
    |> Repo.one()
    |> case do
      %Leaderboard{metadata: %{"all_time_of" => ^slug}} = board -> board
      _other -> nil
    end
  end

  # Makes the all-time board when there is none, then fills it from scratch:
  # each owner's best row of every season per key, at the time they first
  # appeared (a `:best` board keeps a row's first insert time when it rises).
  # Runs inside `with_all_time_lock/2`.
  defp fill_all_time(%Leaderboard{slug: slug, sort_order: sort_order} = season) do
    board =
      find_all_time_board(slug) ||
        %Leaderboard{}
        |> Leaderboard.changeset(%{
          slug: slug <> @all_time_suffix,
          title: season.title,
          description: season.description,
          sort_order: sort_order,
          operator: :best,
          hidden: true,
          metadata: %{"all_time_of" => slug}
        })
        |> Repo.insert!()

    _ = invalidate_leaderboards_cache()
    now = DateTime.utc_now(:second)
    Repo.delete_all(from(r in Record, where: r.leaderboard_id == ^board.id), timeout: :infinity)

    best =
      from(r in in_seasons(season, :all),
        select: %{
          id: r.id,
          n: over(row_number(), :best),
          first_at: over(min(r.inserted_at), :owner)
        },
        windows: [
          owner: [partition_by: [r.key, r.user_id, r.label]],
          best: [partition_by: [r.key, r.user_id, r.label], order_by: ^record_order(sort_order)]
        ]
      )

    rows =
      from(r in Record,
        join: b in subquery(best),
        on: b.id == r.id and b.n == 1,
        select: %{
          user_id: r.user_id,
          label: r.label,
          key: r.key,
          score: r.score,
          metadata: r.metadata,
          inserted_at: b.first_at
        }
      )
      |> Repo.stream(max_rows: 2_000, timeout: :infinity)
      |> Stream.map(
        &Map.merge(&1, %{id: UUIDv7.generate(), leaderboard_id: board.id, updated_at: now})
      )
      |> Stream.chunk_every(2_000)
      |> Enum.reduce(0, fn chunk, total ->
        {inserted, _} = Repo.insert_all(Record, chunk, timeout: :infinity)
        total + inserted
      end)

    _ = invalidate_records_cache(board.id)
    {board, rows}
  end

  # Every season's rows of one key (or all): each board under the slug. The
  # all-time board's own slug carries the suffix, so it is never one of them.
  defp in_seasons(%Leaderboard{slug: slug}, key) do
    seasons = from(lb in Leaderboard, where: lb.slug == ^slug, select: lb.id)
    query = from(r in Record, where: r.leaderboard_id in subquery(seasons))

    if key == :all, do: query, else: from(r in query, where: r.key == ^key)
  end

  # A season row rose: the all-time row rises with it, by the same `:best`
  # upsert (the all-time board has no seasons, so it keeps nothing further).
  defp keep_all_time(%Leaderboard{} = season, %Record{} = record) do
    with true <- all_time?(season),
         %Leaderboard{} = board <- all_time_board(season) do
      result =
        if is_binary(record.user_id),
          do: do_submit_score(board, record.user_id, record.score, record.metadata, record.key),
          else:
            do_submit_label_score(board, record.label, record.score, record.metadata, record.key)

      with {:error, reason} <- result do
        Logger.warning("all-time row for #{season.slug} not kept: #{inspect(reason)}")
      end
    end

    :ok
  end

  # A season row was edited or deleted: its owner's all-time row is read
  # again from what the seasons hold now, or goes when they hold nothing.
  defp refresh_all_time(%Leaderboard{} = season, %Record{} = record) do
    with true <- all_time?(season),
         %Leaderboard{id: board_id} <- all_time_board(season) do
      owner =
        if is_binary(record.user_id),
          do: dynamic([r], r.user_id == ^record.user_id),
          else: dynamic([r], r.label == ^record.label)

      rows = from(r in in_seasons(season, record.key), where: ^owner)
      best = from(r in rows, order_by: ^record_order(season.sort_order), limit: 1) |> Repo.one()
      Repo.delete_all(from(r in in_key(board_id, record.key), where: ^owner))

      if best do
        first_at = Repo.one(from(r in rows, select: min(r.inserted_at)))

        %Record{}
        |> Ecto.Changeset.change(
          leaderboard_id: board_id,
          user_id: best.user_id,
          label: best.label,
          key: best.key,
          score: best.score,
          metadata: best.metadata,
          inserted_at: first_at
        )
        |> Repo.insert!()
      end

      _ = invalidate_records_cache(board_id)
    end

    :ok
  end

  defp refresh_all_time_of(%Record{leaderboard_id: leaderboard_id} = record) do
    case get_leaderboard(leaderboard_id) do
      %Leaderboard{} = season -> refresh_all_time(season, record)
      nil -> :ok
    end
  end

  # A guest's record on a public board, while the host lists registered
  # players only (`Gamend.AccountRequired`): kept, never shown to others.
  defp unlisted?(%Leaderboard{hidden: false}, %Record{guest: true}),
    do: AccountRequired.required?(:leaderboards)

  defp unlisted?(_leaderboard, _record), do: false

  # The records others see: a public board without its guests' when the host
  # requires an account to be listed. `guests: true` keeps them. The flag is
  # the record's own (*Guests* above), so this is a filter on the rank index
  # `leaderboard_records_listed_rank_index`, never a join.
  defp listed(query, %Leaderboard{hidden: false}, opts) do
    if AccountRequired.required?(:leaderboards) and Keyword.get(opts, :guests) != true,
      do: where(query, [r], r.guest == false),
      else: query
  end

  defp listed(query, _leaderboard, _opts), do: query

  @doc """
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
  @spec list_records(String.t()) :: [Record.t()]
  @spec list_records(String.t(), keyword()) :: [Record.t()]
  def list_records(leaderboard_id, opts \\ []) when is_binary(leaderboard_id) do
    case read_board(leaderboard_id, opts) do
      nil ->
        []

      leaderboard ->
        page = Keyword.get(opts, :page, 1)
        page_size = Keyword.get(opts, :page_size, 25)
        key = Keyword.get(opts, :key, "")

        cond do
          pattern = search_pattern(opts) ->
            search_records(leaderboard, key, pattern, page, page_size, opts)

          is_binary(key) and meta_filter(opts) == [] and not Keyword.has_key?(opts, :guests) ->
            list_records_cached(leaderboard, key, page, page_size)

          true ->
            leaderboard
            |> scoped_records(opts)
            |> page_records(leaderboard.sort_order, page, page_size)
        end
    end
  end

  # The rows a read covers: one key or all, the metadata filter, and with
  # `best_per_user` each player's best of them. Uncached for the same reason
  # `search_records/5` is: the filter is caller-supplied, and caching would fill
  # the cache with one entry per value anyone ever picked.
  defp scoped_records(%Leaderboard{id: id, sort_order: sort_order} = leaderboard, opts) do
    rows =
      opts
      |> meta_filter()
      |> Enum.reduce(in_key(id, Keyword.get(opts, :key, "")), fn {field, value}, query ->
        where(query, ^meta_match(field, value))
      end)
      |> listed(leaderboard, opts)

    if Keyword.get(opts, :best_per_user, false) do
      best =
        from(r in rows,
          select: %{id: r.id, n: over(row_number(), :best)},
          windows: [
            best: [partition_by: [r.user_id, r.label], order_by: ^record_order(sort_order)]
          ]
        )

      from(r in Record, join: b in subquery(best), on: b.id == r.id and b.n == 1)
    else
      rows
    end
  end

  defp in_key(leaderboard_id, :all),
    do: from(r in Record, where: r.leaderboard_id == ^leaderboard_id)

  defp in_key(leaderboard_id, key) when is_binary(key),
    do: from(r in Record, where: r.leaderboard_id == ^leaderboard_id and r.key == ^key)

  defp page_records(query, sort_order, page, page_size) do
    offset = max((page - 1) * page_size, 0)

    from(r in query,
      order_by: ^record_order(sort_order),
      offset: ^offset,
      limit: ^page_size,
      preload: [:user]
    )
    |> Repo.all()
    |> Enum.with_index(offset + 1)
    |> Enum.map(fn {record, rank} -> %{record | rank: rank} end)
  end

  defp meta_filter(opts) do
    case Keyword.get(opts, :meta) do
      %{} = fields ->
        for {field, value} <- fields,
            is_binary(field) and is_binary(value) and value != "",
            do: {field, value}

      _ ->
        []
    end
  end

  # Adapter-specific, the same way `Gamend.Notifications` reads a metadata key:
  # Postgres wants `->>`, SQLite `json_extract`. Both compare as text, so the
  # value is bound as a parameter rather than spliced into the fragment.
  defp meta_match(key, value) do
    if AdvisoryLock.postgres?() do
      dynamic([r], fragment("?->>? = ?", r.metadata, ^key, ^value))
    else
      dynamic([r], fragment("json_extract(?, '$.' || ?) = ?", r.metadata, ^key, ^value))
    end
  end

  # Searches are unbounded strings, so they bypass the cache rather than filling
  # it with one entry per term anyone ever typed. A found row shows its real
  # rank: the rows ahead of it, counted on the rank index, as
  # `get_user_record/3` ranks one. Ranking the whole board to find a page of
  # names read every row of it per search.
  defp search_records(
         %Leaderboard{sort_order: sort_order} = leaderboard,
         key,
         pattern,
         page,
         page_size,
         opts
       ) do
    offset = max((page - 1) * page_size, 0)

    from(r in matching_records(leaderboard, key, pattern, opts),
      order_by: ^record_order(sort_order),
      offset: ^offset,
      limit: ^page_size,
      preload: [:user]
    )
    |> Repo.all()
    |> Enum.map(fn record ->
      %{record | rank: calculate_rank(leaderboard, record.score, record.inserted_at, key, opts)}
    end)
  end

  # The listed rows a search names: a label holding the term, or a player
  # found by name (`Gamend.Query.users_named/1`) — by their ids when few, in
  # the board's order joined to the names when many.
  defp matching_records(%Leaderboard{id: id} = leaderboard, key, pattern, opts) do
    rows = listed(in_key(id, key), leaderboard, opts)

    label =
      dynamic(
        [r],
        not is_nil(r.label) and fragment("lower(?) LIKE ? ESCAPE '\\'", r.label, ^pattern)
      )

    case Gamend.Query.users_named(pattern) do
      {:few, ids} ->
        from(r in rows, where: ^dynamic([r], r.user_id in ^ids or ^label))

      :many ->
        from(r in rows,
          left_join: u in User,
          as: :named_user,
          on: u.id == r.user_id,
          where: ^dynamic([r], ^label or ^Gamend.Query.name_match(pattern))
        )
    end
  end

  defp search_pattern(opts), do: Repo.search_pattern(Keyword.get(opts, :search))

  defp record_order(:desc), do: [desc: :score, asc: :inserted_at]
  defp record_order(:asc), do: [asc: :score, asc: :inserted_at]

  @decorate cacheable(
              key:
                {:leaderboards, :list_records, records_cache_version(leaderboard.id),
                 leaderboard.id, leaderboard.sort_order, key, page, page_size},
              opts: [ttl: @records_cache_ttl_ms]
            )
  defp list_records_cached(%Leaderboard{} = leaderboard, key, page, page_size)
       when is_integer(page) and is_integer(page_size) do
    leaderboard.id
    |> in_key(key)
    |> listed(leaderboard, [])
    |> page_records(leaderboard.sort_order, page, page_size)
  end

  @doc """
  Counts records for a leaderboard: the same `:key`, `:meta`,
  `:best_per_user`, `:search` and `:all_time` as `list_records/2`.
  """
  @spec count_records(Ecto.UUID.t()) :: non_neg_integer()
  @spec count_records(Ecto.UUID.t(), keyword()) :: non_neg_integer()
  def count_records(leaderboard_id, opts \\ []) when is_binary(leaderboard_id) do
    key = Keyword.get(opts, :key, "")

    case read_board(leaderboard_id, opts) do
      nil ->
        0

      leaderboard ->
        cond do
          pattern = search_pattern(opts) ->
            leaderboard |> matching_records(key, pattern, opts) |> Repo.aggregate(:count, :id)

          is_binary(key) and meta_filter(opts) == [] and not Keyword.has_key?(opts, :guests) ->
            count_records_cached(leaderboard, key)

          true ->
            leaderboard |> scoped_records(opts) |> Repo.aggregate(:count, :id)
        end
    end
  end

  @decorate cacheable(
              key:
                {:leaderboards, :count_records, records_cache_version(leaderboard.id),
                 leaderboard.id, key},
              opts: [ttl: @records_cache_ttl_ms]
            )
  defp count_records_cached(%Leaderboard{} = leaderboard, key) do
    leaderboard.id
    |> in_key(key)
    |> listed(leaderboard, [])
    |> Repo.aggregate(:count, :id)
  end

  @doc """
  How many records each of `leaderboard_ids` holds, every key and every
  player (the admin's view), in one grouped query: `%{id => count}`, a board
  without records absent.
  """
  @spec count_records_by_board([Ecto.UUID.t()]) :: %{Ecto.UUID.t() => non_neg_integer()}
  def count_records_by_board([]), do: %{}

  def count_records_by_board(leaderboard_ids) when is_list(leaderboard_ids) do
    from(r in Record,
      where: r.leaderboard_id in ^leaderboard_ids,
      group_by: r.leaderboard_id,
      select: {r.leaderboard_id, count(r.id)}
    )
    |> Repo.all()
    |> Map.new()
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
    * `:key` - The ranking (default `""`)
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

        list_records_around_user_cached(leaderboard, key_opt(opts), user_id, limit)
    end
  end

  # Ranked and windowed in one statement, deliberately.
  #
  # This used to be two queries: `get_user_record/2` for the rank (itself
  # cached for 10s), then an OFFSET query that trusted it. Anyone submitting a
  # better score in between pushed the caller down the board, so the second
  # query windowed around a position the caller had already left — and once
  # that drift passed `half`, the caller was missing from their own "around
  # me" page. The load test caught it on 3.2% of reads under 30 concurrent
  # writers on Postgres and on none under SQLite, whose single writer hides
  # the race rather than removing it.
  #
  # One CTE means the rank and the window read the same snapshot, so the
  # caller is in the result by construction — and it is one round trip where
  # the old path was three.
  @decorate cacheable(
              key:
                {:leaderboards, :around_user, records_cache_version(leaderboard.id),
                 leaderboard.id, leaderboard.sort_order, key, user_id, limit},
              opts: [ttl: @records_cache_ttl_ms]
            )
  defp list_records_around_user_cached(%Leaderboard{} = leaderboard, key, user_id, limit)
       when is_binary(user_id) and is_integer(limit) do
    # `rank >= mine - half`, rearranged so the interpolated value sits on the
    # side Ecto can type. `LIMIT` then does what `max(1, ...)` used to: a
    # caller inside the top `half` simply starts the window at rank 1. A
    # caller with no record on this board matches nothing — the subquery is
    # empty, the comparison is NULL — which is the `[]` the old clause
    # returned explicitly.
    half = div(limit, 2)

    my_rank =
      from(m in @rank_cte,
        where: m.user_id == type(^user_id, :binary_id),
        select: m.rank
      )

    from(r in Record,
      join: k in @rank_cte,
      on: k.id == r.id,
      where: k.rank + type(^half, :integer) >= subquery(my_rank),
      order_by: [asc: k.rank],
      limit: ^limit,
      select: {r, k.rank},
      preload: [:user]
    )
    |> with_cte(@rank_cte, as: ^ranked_records(leaderboard, key))
    |> Repo.all()
    |> Enum.map(fn {record, rank} -> %{record | rank: rank} end)
  end

  # `row_number()` reproduces `calculate_rank/4` exactly — the number of rows
  # sorting ahead, plus one — so a rank from here and a rank from there agree.
  # Two clauses rather than one with an interpolated direction: a fragment's
  # SQL is literal, and `ORDER BY ? DESC` cannot take the direction as a
  # parameter.
  defp ranked_records(%Leaderboard{id: leaderboard_id, sort_order: :desc} = leaderboard, key) do
    from(r in listed(in_key(leaderboard_id, key), leaderboard, []),
      select: %{
        id: r.id,
        user_id: r.user_id,
        rank: fragment("row_number() over (order by ? desc, ? asc)", r.score, r.inserted_at)
      }
    )
  end

  defp ranked_records(%Leaderboard{id: leaderboard_id, sort_order: :asc} = leaderboard, key) do
    from(r in listed(in_key(leaderboard_id, key), leaderboard, []),
      select: %{
        id: r.id,
        user_id: r.user_id,
        rank: fragment("row_number() over (order by ? asc, ? asc)", r.score, r.inserted_at)
      }
    )
  end

  @doc """
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
  @spec list_records_above(String.t(), integer()) :: [Record.t()]
  @spec list_records_above(String.t(), integer(), keyword()) :: [Record.t()]
  def list_records_above(leaderboard_id, score, opts \\ [])
      when is_binary(leaderboard_id) and is_integer(score) do
    case get_leaderboard(leaderboard_id) do
      nil ->
        []

      leaderboard ->
        list_records_above_cached(
          leaderboard,
          key_opt(opts),
          score,
          max(Keyword.get(opts, :limit, 3), 1)
        )
    end
  end

  # The rows just ahead of the score in the board's order reversed, read off
  # the rank index; then one count gives the nearest its rank, and the rest
  # are the ranks before it (consecutive rows of the ranking). Ranking the
  # whole key to find three rows took a second and more at a million.
  @decorate cacheable(
              key:
                {:leaderboards, :above, records_cache_version(leaderboard.id), leaderboard.id,
                 leaderboard.sort_order, key, score, limit},
              opts: [ttl: @records_cache_ttl_ms]
            )
  defp list_records_above_cached(
         %Leaderboard{sort_order: sort_order} = leaderboard,
         key,
         score,
         limit
       )
       when is_integer(limit) do
    {ahead, nearest_first} =
      case sort_order do
        :desc -> {dynamic([r], r.score > ^score), [asc: :score, desc: :inserted_at]}
        :asc -> {dynamic([r], r.score < ^score), [desc: :score, desc: :inserted_at]}
      end

    from(r in listed(in_key(leaderboard.id, key), leaderboard, []),
      where: ^ahead,
      order_by: ^nearest_first,
      limit: ^limit,
      preload: [:user]
    )
    |> Repo.all()
    |> case do
      [] ->
        []

      [nearest | _] = rows ->
        rank = calculate_rank(leaderboard, nearest.score, nearest.inserted_at, key)
        rows |> Enum.with_index() |> Enum.map(fn {record, i} -> %{record | rank: rank - i} end)
    end
  end

  @doc """
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
  @spec list_records_beside(String.t(), Record.t(), keyword()) :: {[Record.t()], [Record.t()]}
  def list_records_beside(leaderboard_id, %Record{rank: rank} = record, opts \\ [])
      when is_binary(leaderboard_id) and is_integer(rank) do
    case get_leaderboard(leaderboard_id) do
      nil ->
        {[], []}

      leaderboard ->
        list_records_beside_cached(
          leaderboard,
          record,
          max(Keyword.get(opts, :above, 1), 0),
          max(Keyword.get(opts, :below, 1), 0)
        )
    end
  end

  @decorate cacheable(
              key:
                {:leaderboards, :beside, records_cache_version(leaderboard.id), leaderboard.id,
                 leaderboard.sort_order, record.key, record.id, record.score, record.inserted_at,
                 record.rank, above, below},
              opts: [ttl: @records_cache_ttl_ms]
            )
  defp list_records_beside_cached(
         %Leaderboard{sort_order: sort} = leaderboard,
         record,
         above,
         below
       )
       when is_integer(above) and is_integer(below) do
    %Record{key: key, score: score, inserted_at: at, rank: rank} = record
    rows = from(r in listed(in_key(leaderboard.id, key), leaderboard, []), preload: [:user])

    ahead_rows =
      if above > 0,
        do:
          Repo.all(
            from(r in rows,
              where: ^ahead(sort, score, at),
              order_by: ^last_first(sort),
              limit: ^above
            )
          ),
        else: []

    behind_rows =
      if below > 0,
        do:
          Repo.all(
            from(r in rows,
              where: ^behind(sort, score, at),
              order_by: ^record_order(sort),
              limit: ^below
            )
          ),
        else: []

    {ahead_rows |> Enum.with_index(1) |> Enum.map(fn {r, i} -> %{r | rank: rank - i} end),
     behind_rows |> Enum.with_index(1) |> Enum.map(fn {r, i} -> %{r | rank: rank + i} end)}
  end

  @doc """
  The last records listed on a key, in rank order, each carrying its rank:
  the bottom of the board, where a player with no score yet comes in.

  ## Options

    * `:key` — the ranking (default `""`)
    * `:limit` — how many (default 3)
  """
  @spec list_records_last(String.t(), keyword()) :: [Record.t()]
  def list_records_last(leaderboard_id, opts \\ []) when is_binary(leaderboard_id) do
    case get_leaderboard(leaderboard_id) do
      nil ->
        []

      leaderboard ->
        key = key_opt(opts)
        count = count_records(leaderboard.id, key: key)
        list_records_last_cached(leaderboard, key, count, max(Keyword.get(opts, :limit, 3), 1))
    end
  end

  @decorate cacheable(
              key:
                {:leaderboards, :last, records_cache_version(leaderboard.id), leaderboard.id,
                 leaderboard.sort_order, key, count, limit},
              opts: [ttl: @records_cache_ttl_ms]
            )
  defp list_records_last_cached(%Leaderboard{sort_order: sort} = leaderboard, key, count, limit)
       when is_integer(limit) do
    from(r in listed(in_key(leaderboard.id, key), leaderboard, []),
      order_by: ^last_first(sort),
      limit: ^limit,
      preload: [:user]
    )
    |> Repo.all()
    |> Enum.with_index()
    |> Enum.map(fn {record, i} -> %{record | rank: count - i} end)
    |> Enum.reverse()
  end

  # The board's order turned round: the last row first.
  defp last_first(:desc), do: [asc: :score, desc: :inserted_at]
  defp last_first(:asc), do: [desc: :score, desc: :inserted_at]

  @doc """
  The keys a board holds, sorted, from its listed records; with `prefix:`
  only the keys starting with it (`"match|"`: every language Word match has
  runs in). A key only guests have played is not offered. `all_time: true`
  names the keys of every season of the slug (*All time* above).
  """
  @spec list_keys(String.t()) :: [String.t()]
  @spec list_keys(String.t(), keyword()) :: [String.t()]
  def list_keys(leaderboard_id, opts \\ []) when is_binary(leaderboard_id) do
    case get_leaderboard(leaderboard_id) do
      nil ->
        []

      leaderboard ->
        leaderboard =
          if Keyword.get(opts, :all_time) == true and all_time?(leaderboard),
            do: all_time_view(leaderboard),
            else: leaderboard

        list_keys_cached(leaderboard, Keyword.get(opts, :prefix, ""))
    end
  end

  # One index seek per key (a loose scan of the rank index), not every
  # record read for its key: 2 s at a million rows. A public board that lists
  # registered players only keeps the keys one of them (or a label) holds,
  # each found on its first listed row. The prefix is checked here, not as a
  # range: a collation that skips punctuation does not keep `match|…` together.
  defp list_keys_cached(%Leaderboard{id: id} = leaderboard, prefix) when is_binary(prefix) do
    next = fn after_key ->
      from(r in Record, where: r.leaderboard_id == ^id, select: min(r.key))
      |> then(&if after_key, do: where(&1, [r], r.key > ^after_key), else: &1)
      |> Repo.one()
    end

    next.(nil)
    |> Stream.unfold(fn
      nil -> nil
      key -> {key, next.(key)}
    end)
    |> Enum.filter(&(String.starts_with?(&1, prefix) and listed_key?(leaderboard, &1)))
  end

  defp listed_key?(%Leaderboard{hidden: false} = leaderboard, key) do
    not AccountRequired.required?(:leaderboards) or
      Repo.exists?(listed(in_key(leaderboard.id, key), leaderboard, []))
  end

  defp listed_key?(_leaderboard, _key), do: true

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
        refresh_all_time_of(rec)
        ok

      other ->
        other
    end
  end

  @doc """
  Deletes a user's record from a leaderboard (in `key:`, default `""`).
  Accepts either leaderboard ID or slug (both strings).
  """
  @spec delete_user_record(String.t(), Ecto.UUID.t(), keyword()) ::
          {:ok, Record.t()} | {:error, :not_found}
  def delete_user_record(id_or_slug, user_id, opts \\ []) do
    leaderboard = get_leaderboard(id_or_slug)

    case leaderboard do
      nil ->
        {:error, :not_found}

      %Leaderboard{} = leaderboard ->
        case get_record(leaderboard.id, user_id, key_opt(opts)) do
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
