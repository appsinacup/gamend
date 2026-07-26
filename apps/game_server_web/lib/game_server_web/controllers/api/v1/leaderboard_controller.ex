defmodule GameServerWeb.Api.V1.LeaderboardController do
  use GameServerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias GameServer.Leaderboards
  alias GameServer.Leaderboards.Leaderboard
  alias GameServerWeb.Pagination
  alias OpenApiSpex.Schema

  tags(["Leaderboards"])

  # Shared schema for leaderboard response
  @leaderboard_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid, description: "Leaderboard ID"},
      slug: %Schema{
        type: :string,
        description: "Human-readable identifier (reusable across seasons)"
      },
      title: %Schema{type: :string, description: "Display title"},
      description: %Schema{type: :string, description: "Description"},
      icon_url: %Schema{
        type: :string,
        description: "Icon URL; empty when unset (the client applies its own default)"
      },
      sort_order: %Schema{
        type: :string,
        enum: ["desc", "asc"],
        description: "Sort order - desc (higher is better) or asc (lower is better)"
      },
      operator: %Schema{
        type: :string,
        enum: ["set", "best", "incr", "decr"],
        description: "Score operator"
      },
      starts_at: %Schema{type: :string, format: "date-time", nullable: true},
      ends_at: %Schema{type: :string, format: "date-time", nullable: true},
      is_active: %Schema{type: :boolean, description: "Whether the leaderboard is still active"},
      metadata: %Schema{type: :object, description: "Arbitrary metadata"},
      inserted_at: %Schema{type: :string, format: "date-time"},
      updated_at: %Schema{type: :string, format: "date-time"}
    },
    example: %{
      id: "0198c0de-0001-7000-8000-000000000001",
      slug: "weekly_kills",
      title: "Weekly Kills",
      description: "Get the most kills this week!",
      sort_order: "desc",
      operator: "incr",
      starts_at: "2025-12-02T00:00:00Z",
      ends_at: nil,
      is_active: true,
      metadata: %{},
      inserted_at: "2025-12-02T10:00:00Z",
      updated_at: "2025-12-02T10:00:00Z"
    }
  }

  @record_schema %Schema{
    type: :object,
    properties: %{
      rank: %Schema{type: :integer, description: "Player's rank on this leaderboard"},
      user_id: %Schema{
        type: :string,
        format: :uuid,
        description: "User ID (empty for label-based records)"
      },
      username: %Schema{
        type: :string,
        description: "Unique username handle (empty for label-based records)"
      },
      display_name: %Schema{
        type: :string,
        description: "Human-readable name (user display name or label text)"
      },
      score: %Schema{type: :integer, description: "Score value"},
      metadata: %Schema{type: :object, description: "Per-record metadata"},
      updated_at: %Schema{type: :string, format: "date-time"}
    },
    example: %{
      rank: 1,
      user_id: "0198c0de-0002-7000-8000-000000000002",
      username: "progamer123-4821",
      display_name: "ProGamer123",
      score: 5000,
      metadata: %{weapon: "sword"},
      updated_at: "2025-12-02T10:00:00Z"
    }
  }

  @meta_schema %Schema{
    type: :object,
    properties: %{
      page: %Schema{type: :integer},
      page_size: %Schema{type: :integer},
      count: %Schema{type: :integer},
      total_count: %Schema{type: :integer},
      total_pages: %Schema{type: :integer},
      has_more: %Schema{type: :boolean}
    }
  }

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
      ok:
        {"List of leaderboards", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{type: :array, items: @leaderboard_schema},
             meta: @meta_schema
           }
         }}
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

    json(
      conn,
      Pagination.envelope(
        Enum.map(leaderboards, &serialize_leaderboard/1),
        page,
        page_size,
        total_count
      )
    )
  end

  # ---------------------------------------------------------------------------
  # Get Leaderboard by ID
  # ---------------------------------------------------------------------------

  operation(:show,
    operation_id: "get_leaderboard",
    summary: "Get a leaderboard by ID",
    description: "Return details for a specific leaderboard by its integer ID.",
    parameters: [
      id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        description: "Leaderboard ID",
        required: true
      ]
    ],
    responses: [
      ok: {"Leaderboard details", "application/json", @leaderboard_schema},
      not_found: {"Leaderboard not found", "application/json", %Schema{type: :object}}
    ]
  )

  def show(conn, %{"id" => id}) do
    case Leaderboards.get_leaderboard(to_string(id)) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Leaderboard not found"})

      leaderboard ->
        json(conn, %{data: serialize_leaderboard(leaderboard)})
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
      ok:
        {"Resolved leaderboards", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{
               type: :object,
               description: "Map of slug → leaderboard object. Unresolved slugs are omitted.",
               additionalProperties: @leaderboard_schema
             }
           },
           example: %{
             data: %{
               "weekly_kills" => %{
                 id: "0198c0de-0001-7000-8000-000000000001",
                 slug: "weekly_kills",
                 title: "Weekly Kills",
                 is_active: true
               }
             }
           }
         }},
      bad_request:
        {"Invalid request", "application/json",
         %Schema{type: :object, properties: %{error: %Schema{type: :string}}}}
    ]
  )

  def resolve(conn, %{"slugs" => slugs}) when is_list(slugs) do
    resolved = Leaderboards.resolve_slugs(slugs)

    data =
      Map.new(resolved, fn {slug, lb} -> {slug, serialize_leaderboard(lb)} end)

    json(conn, %{data: data})
  end

  def resolve(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Request body must include a \"slugs\" array"})
  end

  # ---------------------------------------------------------------------------
  # List Records
  # ---------------------------------------------------------------------------

  operation(:records,
    operation_id: "list_leaderboard_records",
    summary: "List leaderboard records",
    description: "Return ranked records for a leaderboard by its integer ID.",
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
      ok:
        {"List of records", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{type: :array, items: @record_schema},
             meta: @meta_schema
           }
         }},
      not_found: {"Leaderboard not found", "application/json", %Schema{type: :object}}
    ]
  )

  def records(conn, %{"id" => id} = params) do
    case Leaderboards.get_leaderboard(to_string(id)) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Leaderboard not found"})

      leaderboard ->
        {page, page_size} = Pagination.params(params)

        records = Leaderboards.list_records(leaderboard.id, page: page, page_size: page_size)
        total_count = Leaderboards.count_records(leaderboard.id)

        json(
          conn,
          Pagination.envelope(
            Enum.map(records, &serialize_record/1),
            page,
            page_size,
            total_count
          )
        )
    end
  end

  # ---------------------------------------------------------------------------
  # Records Around User
  # ---------------------------------------------------------------------------

  operation(:around,
    operation_id: "list_records_around_user",
    summary: "List records around a user",
    description: "Return records centered around a specific user's rank.",
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
      ok:
        {"List of records around user", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{type: :array, items: @record_schema}
           }
         }},
      not_found: {"Leaderboard or user not found", "application/json", %Schema{type: :object}}
    ],
    security: [%{"bearer" => []}]
  )

  def around(conn, %{"id" => id, "user_id" => user_id_str} = params) do
    user_id = GameServer.UUIDv7.cast_or_nil(user_id_str)
    limit = parse_int(params["limit"], 11)

    case Leaderboards.get_leaderboard(to_string(id)) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Leaderboard not found"})

      leaderboard ->
        records = Leaderboards.list_records_around_user(leaderboard.id, user_id, limit: limit)

        json(conn, %{
          data: Enum.map(records, &serialize_record/1)
        })
    end
  end

  # ---------------------------------------------------------------------------
  # Current User's Record
  # ---------------------------------------------------------------------------

  operation(:me,
    operation_id: "get_my_record",
    summary: "Get current user's record",
    description: "Return the authenticated user's record and rank on this leaderboard.",
    parameters: [
      id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        description: "Leaderboard ID",
        required: true
      ]
    ],
    responses: [
      ok:
        {"User's record with rank", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: @record_schema
           }
         }},
      not_found: {"Leaderboard or record not found", "application/json", %Schema{type: :object}}
    ],
    security: [%{"bearer" => []}]
  )

  def me(conn, %{"id" => id}) do
    user_id = conn.assigns.current_scope.user_id

    case Leaderboards.get_leaderboard(to_string(id)) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Leaderboard not found"})

      leaderboard ->
        case Leaderboards.get_user_record(leaderboard.id, user_id) do
          {:ok, record} ->
            json(conn, %{data: serialize_record(record)})

          {:error, :not_found} ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "No record found for this user"})
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp serialize_leaderboard(lb) do
    %{
      id: lb.id,
      slug: lb.slug,
      title: lb.title,
      description: lb.description || "",
      icon_url: lb.icon_url || "",
      sort_order: to_string(lb.sort_order),
      operator: to_string(lb.operator),
      starts_at: lb.starts_at,
      ends_at: lb.ends_at,
      is_active: Leaderboard.active?(lb),
      metadata: lb.metadata || %{},
      inserted_at: lb.inserted_at,
      updated_at: lb.updated_at
    }
  end

  defp serialize_record(record) do
    base = %{
      rank: record.rank,
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

  defp parse_int(nil, default), do: default

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {int, _} -> int
      :error -> default
    end
  end

  defp parse_int(val, _default) when is_integer(val), do: val

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
