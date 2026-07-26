defmodule GameServerWeb.Api.V1.Admin.KvEntryController do
  use GameServerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import GameServerWeb.Helpers.ParamParser

  alias GameServer.KV
  alias GameServerWeb.Pagination
  alias OpenApiSpex.Schema

  tags(["Admin – KV"])

  @error_schema %Schema{type: :object, properties: %{error: %Schema{type: :string}}}

  @kv_entry_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      key: %Schema{type: :string},
      user_id: %Schema{
        type: :string,
        format: :uuid,
        nullable: false,
        description: "Owner user id; -1 means global/unowned",
        example: -1,
        minimum: -1
      },
      lobby_id: %Schema{
        type: :string,
        format: :uuid,
        nullable: true,
        description: "Owner lobby id; -1 means global/unowned",
        example: -1,
        minimum: -1
      },
      data: %Schema{type: :object},
      metadata: %Schema{type: :object},
      inserted_at: %Schema{type: :string, format: "date-time"},
      updated_at: %Schema{type: :string, format: "date-time"}
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

  operation(:index,
    operation_id: "admin_list_kv_entries",
    summary: "List KV entries (admin)",
    security: [%{"authorization" => []}],
    parameters: [
      page: [in: :query, schema: %Schema{type: :integer}, required: false],
      page_size: [in: :query, schema: %Schema{type: :integer}, required: false],
      key: [in: :query, schema: %Schema{type: :string}, required: false],
      user_id: [in: :query, schema: %Schema{type: :string, format: :uuid}, required: false],
      lobby_id: [in: :query, schema: %Schema{type: :string, format: :uuid}, required: false],
      global_only: [
        in: :query,
        schema: %Schema{type: :boolean},
        required: false
      ]
    ],
    responses: [
      ok:
        {"KV entries (paginated)", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{type: :array, items: @kv_entry_schema},
             meta: @meta_schema
           }
         }},
      unauthorized: {"Not authenticated", "application/json", @error_schema},
      forbidden: {"Admin required", "application/json", @error_schema}
    ]
  )

  def index(conn, params) do
    {page, page_size} = GameServerWeb.Pagination.params(params)

    opts =
      []
      |> Keyword.put(:page, page)
      |> Keyword.put(:page_size, page_size)
      |> maybe_put_int_opt(:user_id, params["user_id"])
      |> maybe_put_int_opt(:lobby_id, params["lobby_id"])
      |> maybe_put_string_opt(:key, params["key"])
      |> maybe_put_bool_opt(:global_only, params["global_only"])

    entries = KV.list_entries(opts)
    total_count = KV.count_entries(Keyword.drop(opts, [:page, :page_size]))

    json(conn, %{
      data: Enum.map(entries, &serialize_entry/1),
      meta: Pagination.meta(page, page_size, length(entries), total_count)
    })
  end

  operation(:create,
    operation_id: "admin_create_kv_entry",
    summary: "Create KV entry (admin)",
    security: [%{"authorization" => []}],
    request_body: {
      "KV entry",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          key: %Schema{type: :string},
          user_id: %Schema{type: :string, format: :uuid, nullable: true},
          lobby_id: %Schema{type: :string, format: :uuid, nullable: true},
          data: %Schema{type: :object},
          metadata: %Schema{type: :object}
        },
        required: [:key, :data]
      }
    },
    responses: [
      ok:
        {"KV entry", "application/json",
         %Schema{type: :object, properties: %{data: @kv_entry_schema}}},
      unauthorized: {"Not authenticated", "application/json", @error_schema},
      forbidden: {"Admin required", "application/json", @error_schema},
      unprocessable_entity: {"Validation failed", "application/json", %Schema{type: :object}}
    ]
  )

  def create(conn, params) do
    attrs = normalize_entry_attrs(params)

    case KV.create_entry(attrs) do
      {:ok, entry} ->
        json(conn, %{data: serialize_entry(entry)})

      {:error, %Ecto.Changeset{} = cs} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation_failed", errors: Ecto.Changeset.traverse_errors(cs, & &1)})
    end
  end

  operation(:update,
    operation_id: "admin_update_kv_entry",
    summary: "Update KV entry by id (admin)",
    security: [%{"authorization" => []}],
    parameters: [
      id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]
    ],
    request_body: {
      "KV entry patch",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          key: %Schema{type: :string},
          user_id: %Schema{type: :string, format: :uuid, nullable: true},
          lobby_id: %Schema{type: :string, format: :uuid, nullable: true},
          data: %Schema{type: :object},
          metadata: %Schema{type: :object}
        }
      }
    },
    responses: [
      ok:
        {"KV entry", "application/json",
         %Schema{type: :object, properties: %{data: @kv_entry_schema}}},
      unauthorized: {"Not authenticated", "application/json", @error_schema},
      forbidden: {"Admin required", "application/json", @error_schema},
      not_found: {"Not found", "application/json", @error_schema},
      unprocessable_entity: {"Validation failed", "application/json", %Schema{type: :object}}
    ]
  )

  def update(conn, %{"id" => id} = params) do
    attrs = normalize_entry_attrs(Map.delete(params, "id"))

    case KV.update_entry(id, attrs) do
      {:ok, entry} ->
        json(conn, %{data: serialize_entry(entry)})

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "not_found"})

      {:error, %Ecto.Changeset{} = cs} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation_failed", errors: Ecto.Changeset.traverse_errors(cs, & &1)})
    end
  end

  operation(:delete,
    operation_id: "admin_delete_kv_entry",
    summary: "Delete KV entry by id (admin)",
    security: [%{"authorization" => []}],
    parameters: [
      id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]
    ],
    responses: [
      ok: {"Deleted", "application/json", %Schema{type: :object}},
      unauthorized: {"Not authenticated", "application/json", @error_schema},
      forbidden: {"Admin required", "application/json", @error_schema}
    ]
  )

  def delete(conn, %{"id" => id}) do
    :ok = KV.delete_entry(id)
    json(conn, %{})
  end

  defp serialize_entry(entry) do
    %{
      id: entry.id,
      key: entry.key,
      user_id: entry.user_id || "",
      lobby_id: entry.lobby_id || "",
      data: entry.value,
      metadata: entry.metadata || %{},
      inserted_at: entry.inserted_at,
      updated_at: entry.updated_at
    }
  end

  defp normalize_entry_attrs(params) when is_map(params) do
    params
    |> Map.take([
      "key",
      "user_id",
      "lobby_id",
      "data",
      "value",
      "metadata",
      :key,
      :user_id,
      :lobby_id,
      :data,
      :value,
      :metadata
    ])
    |> normalize_data_field()
    |> normalize_user_id()
    |> normalize_lobby_id()
  end

  defp normalize_data_field(attrs) do
    data = Map.get(attrs, "data") || Map.get(attrs, :data)

    cond do
      is_nil(data) ->
        attrs

      Map.has_key?(attrs, "value") or Map.has_key?(attrs, :value) ->
        attrs
        |> Map.delete("data")
        |> Map.delete(:data)

      true ->
        attrs
        |> Map.delete("data")
        |> Map.delete(:data)
        |> Map.put("value", data)
    end
  end

  defp normalize_user_id(attrs) do
    user_id = Map.get(attrs, "user_id") || Map.get(attrs, :user_id)

    normalized =
      case user_id do
        nil ->
          :no_change

        "" ->
          nil

        v when is_binary(v) ->
          case Ecto.UUID.cast(v) do
            {:ok, uuid} -> uuid
            :error -> :no_change
          end

        _ ->
          :no_change
      end

    cond do
      normalized == :no_change -> attrs
      Map.has_key?(attrs, "user_id") -> Map.put(attrs, "user_id", normalized)
      Map.has_key?(attrs, :user_id) -> Map.put(attrs, :user_id, normalized)
      true -> Map.put(attrs, :user_id, normalized)
    end
  end

  defp normalize_lobby_id(attrs) do
    lobby_id = Map.get(attrs, "lobby_id") || Map.get(attrs, :lobby_id)

    normalized =
      case lobby_id do
        nil ->
          :no_change

        "" ->
          nil

        v when is_binary(v) ->
          case Ecto.UUID.cast(v) do
            {:ok, uuid} -> uuid
            :error -> :no_change
          end

        _ ->
          :no_change
      end

    cond do
      normalized == :no_change -> attrs
      Map.has_key?(attrs, "lobby_id") -> Map.put(attrs, "lobby_id", normalized)
      Map.has_key?(attrs, :lobby_id) -> Map.put(attrs, :lobby_id, normalized)
      true -> Map.put(attrs, :lobby_id, normalized)
    end
  end
end
