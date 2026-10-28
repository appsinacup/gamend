defmodule GamendWeb.Api.V1.Admin.GroupController do
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import GamendWeb.Helpers.ParamParser

  alias Gamend.Groups
  alias GamendWeb.Schemas
  alias GamendWeb.Schemas.{GroupPage, GroupResponse, OkResponse}
  alias GamendWeb.Serializers
  alias OpenApiSpex.Schema

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

            {:error, changeset} ->
              unprocessable(conn, changeset)
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

  # The only refusal left once the group exists is the `before_group_delete`
  # hook's veto; it used to be reported as not_found.
  defp do_delete(conn, group_id) do
    case Groups.admin_delete_group(group_id) do
      {:ok, _} -> reply_ok(conn)
      {:error, :not_found} -> not_found(conn)
      {:error, %Ecto.Changeset{} = changeset} -> unprocessable(conn, changeset)
      {:error, reason} -> reply_rejected(conn, reason)
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
