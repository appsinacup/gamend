defmodule GamendWeb.Api.V1.LeaderboardController do
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gamend.Leaderboards
  alias GamendWeb.Pagination
  alias GamendWeb.Schemas

  alias GamendWeb.Schemas.{
    LeaderboardPage,
    LeaderboardRecordPage,
    LeaderboardRecordResponse,
    LeaderboardResponse,
    LeaderboardsBySlugResponse
  }

  alias GamendWeb.Serializers
  alias OpenApiSpex.Schema

  tags(["Leaderboards"])

  # ---------------------------------------------------------------------------
  # List Leaderboards
  # ---------------------------------------------------------------------------

  operation(:index,
    operation_id: "list_leaderboards",
    summary: "List leaderboards",
    description: """
    Return all leaderboards with optional filters. Results are ordered by end date (active/permanent first, then most recently ended).

    **Common use cases:**
    - Get all leaderboards: `GET /api/v1/leaderboards`
    - Get all seasons of a leaderboard: `GET /api/v1/leaderboards?slug=weekly_kills`
    - Get active leaderboard by slug: `GET /api/v1/leaderboards?slug=weekly_kills&active=true`
    - Get only active leaderboards: `GET /api/v1/leaderboards?active=true`
    """,
    parameters: [
      slug: [
        in: :query,
        schema: %Schema{type: :string},
        description:
          "Filter by slug (returns all seasons of that leaderboard, ordered by end date)"
      ],
      active: [
        in: :query,
        schema: %Schema{type: :boolean},
        description: "Filter by active status (omit for all)"
      ],
      order_by: [
        in: :query,
        schema: %Schema{type: :string, enum: ["ends_at", "inserted_at"], default: "ends_at"},
        description:
          "Order results by field. 'ends_at' (default) puts active first, then by end date. 'inserted_at' orders by creation date."
      ],
      starts_after: [
        in: :query,
        schema: %Schema{type: :string, format: "date-time"},
        description: "Only leaderboards that started after this time (ISO 8601)"
      ],
      starts_before: [
        in: :query,
        schema: %Schema{type: :string, format: "date-time"},
        description: "Only leaderboards that started before this time (ISO 8601)"
      ],
      ends_after: [
        in: :query,
        schema: %Schema{type: :string, format: "date-time"},
        description: "Only leaderboards ending after this time (ISO 8601)"
      ],
      ends_before: [
        in: :query,
        schema: %Schema{type: :string, format: "date-time"},
        description: "Only leaderboards ending before this time (ISO 8601)"
      ],
      page: [
        in: :query,
        schema: %Schema{type: :integer, default: 1},
        description: "Page number"
      ],
      page_size: [
        in: :query,
        schema: %Schema{type: :integer, default: 25},
        description: "Page size (max 100)"
      ]
    ],
    responses: [
      ok: {"List of leaderboards", "application/json", LeaderboardPage}
    ]
  )

  def index(conn, params) do
    {page, page_size} = Pagination.params(params)

    opts =
      [page: page, page_size: page_size]
      |> maybe_add_slug_filter(params["slug"])
      |> maybe_add_active_filter(params["active"])
      |> maybe_add_order_by(params["order_by"])
      |> maybe_add_datetime_filter(:starts_after, params["starts_after"])
      |> maybe_add_datetime_filter(:starts_before, params["starts_before"])
      |> maybe_add_datetime_filter(:ends_after, params["ends_after"])
      |> maybe_add_datetime_filter(:ends_before, params["ends_before"])

    # Build count opts (exclude pagination and ordering)
    count_opts = Keyword.drop(opts, [:page, :page_size, :order_by])

    leaderboards = Leaderboards.list_leaderboards(opts)
    total_count = Leaderboards.count_leaderboards(count_opts)

    reply_page(
      conn,
      Enum.map(leaderboards, &serialize_leaderboard/1),
      page,
      page_size,
      total_count
    )
  end

  # ---------------------------------------------------------------------------
  # Get Leaderboard by ID
  # ---------------------------------------------------------------------------

  operation(:show,
    operation_id: "get_leaderboard",
    summary: "Get a leaderboard by ID",
    description: "Return details for a specific leaderboard by its ID.",
    parameters: [
      id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        description: "Leaderboard ID",
        required: true
      ]
    ],
    responses: [
      ok: {"Leaderboard details", "application/json", LeaderboardResponse},
      not_found: Schemas.error("Leaderboard not found")
    ]
  )

  def show(conn, %{"id" => id}) do
    case Leaderboards.get_leaderboard(to_string(id)) do
      nil -> not_found(conn)
      leaderboard -> reply_data(conn, serialize_leaderboard(leaderboard))
    end
  end

  # ---------------------------------------------------------------------------
  # Resolve Slugs (batch)
  # ---------------------------------------------------------------------------

  operation(:resolve,
    operation_id: "resolve_leaderboard_slugs",
    summary: "Resolve multiple slugs to active leaderboards",
    description: """
    Accepts an array of leaderboard slugs and returns the currently active
    leaderboard for each slug. If a slug has seasonal leaderboards, the latest
    active season is returned. Slugs with no active leaderboard are omitted
    from the result.
    """,
    request_body: {
      "Slugs to resolve",
      "application/json",
      %Schema{
        type: :object,
        required: [:slugs],
        properties: %{
          slugs: %Schema{
            type: :array,
            items: %Schema{type: :string},
            description: "List of leaderboard slugs to resolve",
            example: ["weekly_kills", "monthly_score"]
          }
        }
      }
    },
    responses: [
      ok: {"Resolved leaderboards", "application/json", LeaderboardsBySlugResponse},
      bad_request: Schemas.error("`slugs` is missing or not an array (missing_param)")
    ]
  )

  def resolve(conn, %{"slugs" => slugs}) when is_list(slugs) do
    resolved = Leaderboards.resolve_slugs(slugs)

    reply_data(conn, Map.new(resolved, fn {slug, lb} -> {slug, serialize_leaderboard(lb)} end))
  end

  def resolve(conn, _params) do
    reply_error(conn, :bad_request, "missing_param", "slugs must be an array of slugs")
  end

  # ---------------------------------------------------------------------------
  # List Records
  # ---------------------------------------------------------------------------

  operation(:records,
    operation_id: "list_leaderboard_records",
    summary: "List leaderboard records",
    description: "Return ranked records for a leaderboard, best first.",
    parameters: [
      id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        description: "Leaderboard ID",
        required: true
      ],
      page: [
        in: :query,
        schema: %Schema{type: :integer, default: 1},
        description: "Page number"
      ],
      page_size: [
        in: :query,
        schema: %Schema{type: :integer, default: 25},
        description: "Page size (max 100)"
      ]
    ],
    responses: [
      ok: {"List of records", "application/json", LeaderboardRecordPage},
      not_found: Schemas.error("Leaderboard not found")
    ]
  )

  def records(conn, %{"id" => id} = params) do
    case Leaderboards.get_leaderboard(to_string(id)) do
      nil ->
        not_found(conn)

      leaderboard ->
        {page, page_size} = Pagination.params(params)

        records = Leaderboards.list_records(leaderboard.id, page: page, page_size: page_size)
        total_count = Leaderboards.count_records(leaderboard.id)

        reply_page(conn, Enum.map(records, &serialize_record/1), page, page_size, total_count)
    end
  end

  # ---------------------------------------------------------------------------
  # Records Around User
  # ---------------------------------------------------------------------------

  operation(:around,
    operation_id: "list_records_around_user",
    summary: "List records around a user",
    description: """
    Return up to `limit` records centered on a user's rank. The window is
    answered as one complete page (`meta.page` 1, `meta.has_more` false); each
    record's `rank` places it on the board. Empty when the user has no record.
    """,
    parameters: [
      id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        description: "Leaderboard ID",
        required: true
      ],
      user_id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        description: "User ID to center around",
        required: true
      ],
      limit: [
        in: :query,
        schema: %Schema{type: :integer, default: 11},
        description: "Total number of records to return"
      ]
    ],
    responses: [
      ok: {"Records around the user", "application/json", LeaderboardRecordPage},
      not_found: Schemas.error("Leaderboard not found")
    ]
  )

  def around(conn, %{"id" => id, "user_id" => user_id_str} = params) do
    user_id = Gamend.UUIDv7.cast_or_nil(user_id_str)
    # Clamped like every other page size. This went straight into the query, so
    # `?limit=1000000` dumped the whole leaderboard in one unauthenticated
    # request and a negative value reached the database as a negative LIMIT.
    limit = Gamend.Limits.clamp_page_size(params["limit"], 11)

    case Leaderboards.get_leaderboard(to_string(id)) do
      nil ->
        not_found(conn)

      leaderboard ->
        records = Leaderboards.list_records_around_user(leaderboard.id, user_id, limit: limit)
        reply_page(conn, Enum.map(records, &serialize_record/1), 1, limit, length(records))
    end
  end

  # ---------------------------------------------------------------------------
  # Current User's Record
  # ---------------------------------------------------------------------------

  operation(:me,
    operation_id: "get_my_record",
    summary: "Get current user's record",
    description:
      "Return the authenticated user's record and rank on this leaderboard. A guest's " <>
        "record on a public board that lists registered players only comes with " <>
        "`hidden: true`: others never see it, and `rank` is where it would stand.",
    parameters: [
      id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        description: "Leaderboard ID",
        required: true
      ]
    ],
    responses: [
      ok: {"User's record with rank", "application/json", LeaderboardRecordResponse},
      not_found:
        Schemas.error("Leaderboard not found (not_found), or no record yet (record_not_found)"),
      unauthorized: Schemas.error("Not authenticated")
    ],
    security: [%{"authorization" => []}]
  )

  def me(conn, %{"id" => id}) do
    user_id = conn.assigns.current_scope.user_id

    case Leaderboards.get_leaderboard(to_string(id)) do
      nil ->
        not_found(conn)

      leaderboard ->
        case Leaderboards.get_user_record(leaderboard.id, user_id) do
          {:ok, record} -> reply_data(conn, serialize_record(record))
          {:error, :not_found} -> reply_error(conn, :not_found, "record_not_found")
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp not_found(conn), do: reply_error(conn, :not_found, "not_found")

  defp serialize_leaderboard(lb), do: Serializers.serialize_leaderboard(lb)

  defp serialize_record(record) do
    base = %{
      rank: record.rank,
      hidden: record.hidden == true,
      score: record.score,
      metadata: record.metadata || %{},
      updated_at: record.updated_at
    }

    if label = record.label do
      Map.merge(base, %{
        user_id: "",
        username: "",
        display_name: label
      })
    else
      Map.merge(base, %{
        user_id: record.user_id,
        username: (record.user && record.user.username) || "",
        display_name: (record.user && record.user.display_name) || ""
      })
    end
  end

  defp maybe_add_slug_filter(opts, nil), do: opts
  defp maybe_add_slug_filter(opts, ""), do: opts
  defp maybe_add_slug_filter(opts, slug), do: Keyword.put(opts, :slug, slug)

  defp maybe_add_active_filter(opts, true), do: Keyword.put(opts, :active, true)
  defp maybe_add_active_filter(opts, false), do: Keyword.put(opts, :active, false)
  defp maybe_add_active_filter(opts, "true"), do: Keyword.put(opts, :active, true)
  defp maybe_add_active_filter(opts, "false"), do: Keyword.put(opts, :active, false)
  defp maybe_add_active_filter(opts, _), do: opts

  defp maybe_add_order_by(opts, "ends_at"), do: Keyword.put(opts, :order_by, :ends_at)
  defp maybe_add_order_by(opts, "inserted_at"), do: Keyword.put(opts, :order_by, :inserted_at)
  defp maybe_add_order_by(opts, _), do: Keyword.put(opts, :order_by, :ends_at)

  defp maybe_add_datetime_filter(opts, _key, nil), do: opts
  defp maybe_add_datetime_filter(opts, _key, ""), do: opts

  defp maybe_add_datetime_filter(opts, key, value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> Keyword.put(opts, key, datetime)
      {:error, _} -> opts
    end
  end
end
