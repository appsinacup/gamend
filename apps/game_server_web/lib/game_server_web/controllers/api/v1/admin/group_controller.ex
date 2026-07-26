defmodule GameServerWeb.Api.V1.Admin.GroupController do
  use GameServerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import GameServerWeb.Helpers.ParamParser

  alias GameServer.Groups
  alias GameServerWeb.Serializers
  alias OpenApiSpex.Schema

  tags(["Admin – Groups"])

  @error_schema %Schema{
    type: :object,
    properties: %{error: %Schema{type: :string}}
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

  @group_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      title: %Schema{type: :string},
      description: %Schema{type: :string},
      type: %Schema{type: :string},
      max_members: %Schema{type: :integer},
      metadata: %Schema{type: :object},
      creator_id: %Schema{
        type: :string,
        format: :uuid,
        description: "User ID of the creator, or -1 for system groups"
      },
      creator_name: %Schema{type: :string},
      member_count: %Schema{type: :integer},
      slowdown: %Schema{type: :integer, description: "Chat slowdown in seconds (0 = disabled)"},
      inserted_at: %Schema{type: :string, format: :"date-time"},
      updated_at: %Schema{type: :string, format: :"date-time"}
    }
  }

  operation(:index,
    operation_id: "admin_list_groups",
    summary: "List all groups (admin)",
    description: "List all groups including hidden. Supports filters.",
    security: [%{"authorization" => []}],
    parameters: [
      title: [in: :query, schema: %Schema{type: :string}],
      type: [
        in: :query,
        schema: %Schema{type: :string, enum: ["public", "private", "hidden"]}
      ],
      min_members: [in: :query, schema: %Schema{type: :integer}],
      max_members: [in: :query, schema: %Schema{type: :integer}],
      sort_by: [
        in: :query,
        schema: %Schema{
          type: :string,
          enum: [
            "updated_at",
            "updated_at_asc",
            "inserted_at",
            "inserted_at_asc",
            "title",
            "title_desc",
            "max_members",
            "max_members_asc"
          ]
        }
      ],
      page: [in: :query, schema: %Schema{type: :integer}],
      page_size: [in: :query, schema: %Schema{type: :integer}]
    ],
    responses: [
      ok:
        {"Groups list", "application/json",
         %Schema{
           type: :object,
           properties: %{data: %Schema{type: :array, items: @group_schema}, meta: @meta_schema}
         }}
    ]
  )

  operation(:update,
    operation_id: "admin_update_group",
    summary: "Update a group (admin)",
    description: "Admin-level group update. No membership check.",
    security: [%{"authorization" => []}],
    parameters: [
      id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]
    ],
    request_body: {
      "Update parameters",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          title: %Schema{type: :string},
          description: %Schema{type: :string},
          type: %Schema{type: :string},
          max_members: %Schema{type: :integer},
          metadata: %Schema{type: :object},
          slowdown: %Schema{
            type: :integer,
            description: "Chat slowdown in seconds (0 = disabled, max 3600)"
          }
        }
      }
    },
    responses: [
      ok: {"Updated", "application/json", @group_schema},
      not_found: {"Not found", "application/json", @error_schema},
      unprocessable_entity: {"Validation error", "application/json", @error_schema}
    ]
  )

  operation(:delete,
    operation_id: "admin_delete_group",
    summary: "Delete a group (admin)",
    description: "Admin-level group deletion.",
    security: [%{"authorization" => []}],
    parameters: [
      id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]
    ],
    responses: [
      ok: {"Deleted", "application/json", %Schema{type: :object}},
      not_found: {"Not found", "application/json", @error_schema}
    ]
  )

  # ---------------------------------------------------------------------------
  # Actions
  # ---------------------------------------------------------------------------

  def index(conn, params) do
    filters =
      %{}
      |> maybe_put_param_filter(:title, params)
      |> maybe_put_param_filter(:type, params)
      |> maybe_put_param_filter(:min_members, params)
      |> maybe_put_param_filter(:max_members, params)

    {page, page_size} = GameServerWeb.Pagination.params(params)
    sort_by = Map.get(params, "sort_by")

    groups =
      Groups.list_all_groups(filters,
        page: page,
        page_size: page_size,
        sort_by: sort_by
      )

    serialized = Enum.map(groups, &serialize_group/1)
    count = length(serialized)
    total_count = Groups.count_all_groups(filters)

    json(conn, %{
      data: serialized,
      meta: GameServerWeb.Pagination.meta(page, page_size, count, total_count)
    })
  end

  def update(conn, %{"id" => id} = params) do
    case parse_id(id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})

      group_id ->
        group = Groups.get_group(group_id)

        if is_nil(group) do
          conn |> put_status(:not_found) |> json(%{error: "not_found"})
        else
          attrs = Map.drop(params, ["id"])

          case Groups.admin_update_group(group, attrs) do
            {:ok, updated} ->
              json(conn, serialize_group(updated))

            {:error, changeset} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{
                error: Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
              })
          end
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    case parse_id(id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})

      group_id ->
        case Groups.admin_delete_group(group_id) do
          {:ok, _} -> json(conn, %{})
          {:error, _} -> conn |> put_status(:not_found) |> json(%{error: "not_found"})
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp serialize_group(group),
    do:
      Serializers.serialize_group(group,
        include_member_count: true,
        include_slowdown: true,
        include_timestamps: true
      )
end
