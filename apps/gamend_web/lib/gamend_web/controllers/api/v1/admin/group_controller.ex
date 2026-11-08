defmodule GamendWeb.Api.V1.Admin.GroupController do
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import GamendWeb.Helpers.ParamParser

  alias Gamend.Groups
  alias Gamend.Groups.GroupType
  alias GamendWeb.Schemas
  alias GamendWeb.Schemas.{GroupPage, GroupResponse, OkResponse}
  alias GamendWeb.Serializers
  alias OpenApiSpex.Schema

  require Gamend.SortKey, as: SortKey

  tags(["Admin – Groups"])

  operation(:index,
    operation_id: "admin_list_groups",
    summary: "List all groups (admin)",
    description: "List all groups including hidden. Supports filters.",
    security: [%{"authorization" => []}],
    parameters: [
      title: [in: :query, schema: %Schema{type: :string}],
      type: [
        in: :query,
        schema: %Schema{
          type: :string,
          enum: GroupType.all()
        }
      ],
      min_members: [in: :query, schema: %Schema{type: :integer}],
      max_members: [in: :query, schema: %Schema{type: :integer}],
      sort_by: [
        in: :query,
        schema: %Schema{
          type: :string,
          enum: [
            SortKey.updated_at(),
            SortKey.updated_at_asc(),
            SortKey.inserted_at(),
            SortKey.inserted_at_asc(),
            SortKey.title(),
            SortKey.title_desc(),
            SortKey.max_members(),
            SortKey.max_members_asc()
          ]
        }
      ],
      page: [in: :query, schema: %Schema{type: :integer}],
      page_size: [in: :query, schema: %Schema{type: :integer}]
    ],
    responses: [
      ok: {"Groups list", "application/json", GroupPage}
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
          slug: %Schema{type: :string, description: "Unique among the creator's groups"},
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
      ok: {"Updated", "application/json", GroupResponse},
      not_found: Schemas.error("Not found"),
      forbidden: Schemas.error("Vetoed by a hook (rejected)"),
      conflict: Schemas.error("The slug is taken among the creator's groups (validation_failed)"),
      unprocessable_entity: Schemas.error("Validation error")
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
      ok: {"Deleted", "application/json", OkResponse},
      not_found: Schemas.error("Not found"),
      forbidden: Schemas.error("Vetoed by a hook (rejected)"),
      unprocessable_entity: Schemas.error("Validation failed")
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

    {page, page_size} = GamendWeb.Pagination.params(params)
    sort_by = Map.get(params, "sort_by")

    groups =
      Groups.list_all_groups(filters,
        page: page,
        page_size: page_size,
        sort_by: sort_by
      )

    serialized = Enum.map(groups, &serialize_group/1)
    total_count = Groups.count_all_groups(filters)

    reply_page(conn, serialized, page, page_size, total_count)
  end

  def update(conn, %{"id" => id} = params) do
    case parse_id(id) do
      nil ->
        reply_error(conn, :not_found, "not_found")

      group_id ->
        group = Groups.get_group(group_id)

        if is_nil(group) do
          reply_error(conn, :not_found, "not_found")
        else
          attrs = Map.drop(params, ["id"])

          case Groups.admin_update_group(group, attrs) do
            {:ok, updated} ->
              reply_data(conn, serialize_group(updated))

            {:error, reason} ->
              reply_reason(conn, reason)
          end
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    case parse_id(id) do
      nil ->
        reply_error(conn, :not_found, "not_found")

      group_id ->
        if Groups.get_group(group_id), do: do_delete(conn, group_id), else: not_found(conn)
    end
  end

  # Once the group exists, a refusal is the `before_group_delete` hook's veto:
  # 403 `rejected`. It used to be reported as not_found.
  defp do_delete(conn, group_id) do
    case Groups.admin_delete_group(group_id) do
      {:ok, _} -> reply_ok(conn)
      {:error, reason} -> reply_reason(conn, reason)
    end
  end

  defp not_found(conn), do: reply_error(conn, :not_found, "not_found")

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
