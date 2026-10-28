defmodule Gamend.Accounts.Search do
  @moduledoc """
  Finding users: the player-facing search and the admin user listing.

  Split out of `Gamend.Accounts`, which still exposes every function here under
  the same name.
  """

  import Ecto.Query, warn: false
  alias Gamend.Accounts
  alias Gamend.Accounts.User
  alias Gamend.Repo
  alias Gamend.Types

  # Fields the ADMIN search matches. Deliberately wider than search_users/2
  # (username + display_name only): email, device id and provider ids are
  # sensitive and must never be searchable through the public player search.
  @admin_id_fields ~w(device_id google_id apple_id facebook_id github_id steam_id discord_id)a

  @doc """
  Search users by display name (case-insensitive prefix match) or exact numeric id.

  Returns a list of User structs.

  ## Options

  See `t:Gamend.Types.pagination_opts/0` for available options.
  """
  @spec search_users(String.t()) :: [User.t()]
  @spec search_users(String.t(), Types.pagination_opts()) :: [User.t()]
  def search_users(query, opts \\ []) when is_binary(query) do
    q = String.trim(query)
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 25)

    if q == "" do
      []
    else
      normalized_q = String.downcase(q)
      text_results = search_users_by_text(normalized_q, page, page_size)

      maybe_prepend_id_match(text_results, q)
    end
  end

  # If `q` looks like a UUID, attempt a direct ID lookup and prepend the result
  # (deduplicated) to `results`.  Returns `results` unchanged otherwise.
  defp maybe_prepend_id_match(results, q) do
    with id when is_binary(id) <- Gamend.Parse.uuid(q),
         %{} = user <- Accounts.get_user(id) do
      [user | Enum.reject(results, &(&1.id == id))]
    else
      _ -> results
    end
  end

  # Whether a user's display_name starts with `q` (case-insensitive), meaning
  # the text search already includes them.
  defp text_search_matches_user?(user, q) do
    nq = String.downcase(q)
    dn = (user.display_name || "") |> String.downcase()
    String.starts_with?(dn, nq)
  end

  defp search_users_by_text(normalized_q, page, page_size) do
    pattern = "#{Repo.escape_like(normalized_q)}%"
    offset = (page - 1) * page_size

    Repo.all(
      from u in User,
        where:
          fragment("lower(?) LIKE ? ESCAPE '\\'", u.display_name, ^pattern) or
            fragment("? LIKE ? ESCAPE '\\'", u.username, ^pattern),
        limit: ^page_size,
        offset: ^offset
    )
  end

  @doc """
  Count users matching a username/display name query or exact id. Returns integer.
  """
  @spec count_search_users(String.t()) :: non_neg_integer()
  def count_search_users(query) when is_binary(query) do
    q = String.trim(query)

    if q == "" do
      0
    else
      normalized_q = String.downcase(q)
      text_count = count_search_users_by_text(normalized_q)

      maybe_add_id_match_count(text_count, q)
    end
  end

  # If `q` looks like a UUID, check for an ID match and add 1 to the count
  # only if the user isn't already included in the text results.
  defp maybe_add_id_match_count(text_count, q) do
    with id when is_binary(id) <- Gamend.Parse.uuid(q),
         %{} = user <- Accounts.get_user(id),
         false <- text_search_matches_user?(user, q) do
      text_count + 1
    else
      _ -> text_count
    end
  end

  defp count_search_users_by_text(normalized_q) do
    pattern = "#{Repo.escape_like(normalized_q)}%"

    Repo.one(
      from u in User,
        where:
          fragment("lower(?) LIKE ? ESCAPE '\\'", u.display_name, ^pattern) or
            fragment("? LIKE ? ESCAPE '\\'", u.username, ^pattern),
        select: count(u.id)
    ) || 0
  end

  @doc """
  Admin user listing: search across identity fields (or an exact id), optional
  facet filters, sorting and pagination — the query behind the admin Users page.

  Distinct from `search_users/2`, the privacy-safe player search: this matches
  sensitive fields a player cannot, so it is admin-only.

  `filters` keys (string or atom): `:search` (term or full id), `:facets` (list
  of `"online"`, `"unactivated"`, `"banned"` (an active account ban), `"unverified"` — an email never confirmed —
  and provider names). `opts`: `:page`,
  `:page_size`, `:sort_field`, `:sort_dir`.
  """
  @spec list_all_users(map(), keyword()) :: [User.t()]
  def list_all_users(filters \\ %{}, opts \\ []) do
    filters
    |> all_users_query()
    |> order_by(^admin_user_sort(opts))
    |> Gamend.Query.page(opts)
    |> Repo.all()
  end

  @doc "Row count for `list_all_users/2` under the same filters."
  @spec count_list_all_users(map()) :: non_neg_integer()
  def count_list_all_users(filters \\ %{}) do
    filters |> all_users_query() |> Repo.aggregate(:count, :id)
  end

  defp all_users_query(filters) do
    search = to_string(filter_get(filters, :search) || "")
    facets = filter_get(filters, :facets) || []

    from(u in User)
    |> filter_users_by_admin_search(String.trim(search))
    |> filter_users_by_facets(facets)
  end

  defp filter_get(filters, key), do: Map.get(filters, key) || Map.get(filters, to_string(key))

  defp filter_users_by_admin_search(query, ""), do: query

  defp filter_users_by_admin_search(query, term) do
    case Gamend.Parse.uuid(term) do
      nil ->
        from u in query, where: ^admin_search_match(term)

      # A full id: exact match (mirrors the id lookup in search_users/2).
      id ->
        from u in query, where: u.id == ^id
    end
  end

  # A name or email holding the term, or an id equal to it. Contains-matching
  # every id column too read every account per search (1.5 s at a million);
  # the names and the email are what an admin types part of, and Postgres
  # finds those through their trigram indexes (`UserNameTrigramIndexes`), the
  # ids through their unique ones.
  defp admin_search_match(term) do
    like = "%" <> Repo.escape_like(String.downcase(term)) <> "%"

    contains =
      dynamic(
        [u],
        fragment("lower(coalesce(?, '')) LIKE ? ESCAPE '\\'", u.username, ^like) or
          fragment("lower(coalesce(?, '')) LIKE ? ESCAPE '\\'", u.display_name, ^like) or
          fragment("lower(coalesce(CAST(? AS TEXT), '')) LIKE ? ESCAPE '\\'", u.email, ^like)
      )

    Enum.reduce(@admin_id_fields, contains, fn field, acc ->
      dynamic([u], ^acc or field(u, ^field) == ^term)
    end)
  end

  defp filter_users_by_facets(query, facets) do
    query
    |> then(fn q -> if "online" in facets, do: where(q, [u], u.is_online == true), else: q end)
    |> then(fn q ->
      if "unactivated" in facets, do: where(q, [u], u.is_activated == false), else: q
    end)
    |> then(fn q ->
      if "banned" in facets,
        do: where(q, [u], u.id in subquery(Gamend.Bans.banned_user_ids())),
        else: q
    end)
    |> then(fn q ->
      if "unverified" in facets,
        do: where(q, [u], not is_nil(u.email) and is_nil(u.confirmed_at)),
        else: q
    end)
    |> apply_provider_presence(facets -- ["online", "unactivated", "unverified", "banned"])
  end

  defp apply_provider_presence(query, providers) do
    combined =
      providers
      |> Enum.map(&provider_presence_clause/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.reduce(nil, fn c, acc -> if acc, do: dynamic([u], ^acc or ^c), else: c end)

    if combined, do: from(u in query, where: ^combined), else: query
  end

  defp provider_presence_clause("discord"),
    do: dynamic([u], not is_nil(u.discord_id) and u.discord_id != "")

  defp provider_presence_clause("google"),
    do: dynamic([u], not is_nil(u.google_id) and u.google_id != "")

  defp provider_presence_clause("apple"),
    do: dynamic([u], not is_nil(u.apple_id) and u.apple_id != "")

  defp provider_presence_clause("facebook"),
    do: dynamic([u], not is_nil(u.facebook_id) and u.facebook_id != "")

  defp provider_presence_clause("github"),
    do: dynamic([u], not is_nil(u.github_id) and u.github_id != "")

  defp provider_presence_clause("steam"),
    do: dynamic([u], not is_nil(u.steam_id) and u.steam_id != "")

  defp provider_presence_clause("device"),
    do: dynamic([u], not is_nil(u.device_id) and u.device_id != "")

  defp provider_presence_clause("email"),
    do: dynamic([u], not is_nil(u.hashed_password) and u.hashed_password != "")

  defp provider_presence_clause(_), do: nil

  defp admin_user_sort(opts) do
    dir = if Keyword.get(opts, :sort_dir) == "asc", do: :asc, else: :desc

    field =
      case Keyword.get(opts, :sort_field) do
        "updated_at" -> :updated_at
        "last_seen_at" -> :last_seen_at
        _ -> :inserted_at
      end

    [{dir, field}]
  end
end
