defmodule Gamend.Query do
  @moduledoc """
  Query-building pieces shared by the contexts. Right now: paging.

  ## Why this exists

  Seven contexts each carried a private `paginate/2`, in four different
  behaviours. Three (`quests`, `economy`, `inventory`) read `:page_size`
  straight out of the options and applied it, so `list_ledger(page_size:
  1_000_000)` was a single unbounded read. Two (`groups`, `lobbies`) clamped —
  to a hard-coded `@max_page_size 1000` that ignored the configurable
  `max_page_size` limit entirely. Two (`matchmaking`, `ready_checks`) clamped
  correctly through `Gamend.Limits`.

  `GamendWeb.Pagination` already fixed the same drift one layer up, and
  `mix gamend.api.lint` keeps controllers honest — but nothing was watching
  the contexts, and a plugin calls them directly. Both functions here clamp
  through `Gamend.Limits`, so the configured maximum is the maximum wherever
  the call came from.

  ## Which one

  `page/2` always windows: the caller is paging, and no `:page` just means the
  first one. `maybe_page/2` windows only when asked, and otherwise bounds the
  read at `unpaginated_limit/0` — for a listing whose callers legitimately want
  "all of them", where "all" must still not mean an unbounded `Repo.all` over a
  growing table.
  """

  import Ecto.Query, only: [dynamic: 2, from: 2, limit: 2, offset: 2, where: 2, where: 3, join: 5]

  alias Gamend.Accounts.User
  alias Gamend.Limits
  alias Gamend.Repo

  # The ceiling on a read that asked for no window. Deliberately well above
  # `max_page_size`: this is a backstop against an unbounded scan, not a page.
  @unpaginated_limit 1000

  @doc "The ceiling applied to a read that requested no page."
  @spec unpaginated_limit() :: pos_integer()
  def unpaginated_limit, do: @unpaginated_limit

  @doc """
  Applies `:page` and `:page_size`, both clamped, defaulting to the first page.

      Query.page(query, page: 2, page_size: 50)
  """
  @spec page(Ecto.Queryable.t(), keyword()) :: Ecto.Query.t()
  def page(query, opts) do
    window(query, Keyword.get(opts, :page), Keyword.get(opts, :page_size))
  end

  @doc """
  Applies the window when `:page` is given, and otherwise caps the read at
  `unpaginated_limit/0`.
  """
  @spec maybe_page(Ecto.Queryable.t(), keyword()) :: Ecto.Query.t()
  def maybe_page(query, opts) do
    case Keyword.get(opts, :page) do
      nil -> limit(query, @unpaginated_limit)
      page -> window(query, page, Keyword.get(opts, :page_size))
    end
  end

  @doc """
  Narrows a query over a table with a `user_id` column to one user, found by
  exact id or by a substring of their username or display name — so an admin
  can filter a list without knowing the raw id.

  `nil` leaves the query alone. Economy, inventory and quests each carried an
  identical private copy of this.
  """
  @spec filter_user(Ecto.Queryable.t(), String.t() | nil) :: Ecto.Queryable.t()
  def filter_user(query, value) when value in [nil, ""], do: query

  def filter_user(query, value) when is_binary(value) do
    case Gamend.Parse.uuid(value) do
      nil ->
        case Repo.search_pattern(value) do
          nil -> query
          pattern -> filter_user_named(query, :user_id, pattern)
        end

      uuid ->
        where(query, [q], q.user_id == ^uuid)
    end
  end

  @named_probe 500

  @doc """
  The users whose username or display name holds `pattern` (a
  `Repo.search_pattern/1`): `{:few, ids}` when at most #{@named_probe} do,
  `:many` past that.

  Every player search across a big table goes through it: when a term names
  few players, the table is read by their ids, through its index; when it
  names many, the caller reads the table in its own order, joined to the
  names, and stops at a page. Joining every row to the names first read a
  whole leaderboard or member list per search, 0.5 s at 100,000 rows. On
  Postgres the names are found through their trigram indexes
  (`UserNameTrigramIndexes`).
  """
  @spec users_named(String.t()) :: {:few, [Ecto.UUID.t()]} | :many
  def users_named(pattern) when is_binary(pattern) do
    ids =
      from(u in User, as: :named_user, select: u.id, limit: ^(@named_probe + 1))
      |> where(^name_match(pattern))
      |> Repo.all()

    if length(ids) > @named_probe, do: :many, else: {:few, ids}
  end

  @doc """
  Narrows `query` to the rows whose `field` holds a player named by
  `pattern` (`users_named/1`): by their ids when few, else joined to the
  names as `:named_user`.
  """
  @spec filter_user_named(Ecto.Queryable.t(), atom(), String.t()) :: Ecto.Query.t()
  def filter_user_named(query, field, pattern) when is_atom(field) and is_binary(pattern) do
    case users_named(pattern) do
      {:few, ids} ->
        where(query, [q], field(q, ^field) in ^ids)

      :many ->
        query
        |> join(:inner, [q], u in User, as: :named_user, on: u.id == field(q, ^field))
        |> where(^name_match(pattern))
    end
  end

  @doc """
  The condition a player search reads, on a user bound as `binding`
  (`:named_user`): the expressions the trigram indexes cover.
  """
  @spec name_match(String.t(), atom()) :: Ecto.Query.dynamic_expr()
  def name_match(pattern, binding \\ :named_user) when is_binary(pattern) do
    dynamic(
      [{^binding, u}],
      fragment("lower(coalesce(?, '')) LIKE ? ESCAPE '\\'", u.username, ^pattern) or
        fragment("lower(coalesce(?, '')) LIKE ? ESCAPE '\\'", u.display_name, ^pattern)
    )
  end

  @doc """
  The rows whose `field` is exactly the id `value`.

  For a caller holding an id rather than a search term -- a plugin scoping a
  read by user or lobby, a link from another page. `nil` and `""` leave the
  query alone. A value that is not a UUID matches nothing: it arrives in
  request params, where comparing it raised `Ecto.Query.CastError`, and
  ignoring it instead would answer every row to a filter plainly meant to
  narrow them. KV did the first and push the second.

  See `filter_user/2` for the admin search that also matches names.
  """
  @spec filter_id(Ecto.Queryable.t(), atom(), String.t() | nil) :: Ecto.Queryable.t()
  def filter_id(query, _field, value) when value in [nil, ""], do: query

  def filter_id(query, field, value) when is_atom(field) and is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> where(query, [q], field(q, ^field) == ^uuid)
      :error -> where(query, [_q], false)
    end
  end

  defp window(query, raw_page, raw_page_size) do
    page = Limits.clamp_page(raw_page)
    size = Limits.clamp_page_size(raw_page_size)

    query |> limit(^size) |> offset(^((page - 1) * size))
  end
end
