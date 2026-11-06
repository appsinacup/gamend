defmodule GamendWeb.Api.V1.Admin.KvEntryController do
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import GamendWeb.Helpers.ParamParser

  alias Gamend.KV
  alias GamendWeb.Schemas
  alias GamendWeb.Schemas.{AdminKvEntryPage, AdminKvEntryResponse, OkResponse}
  alias GamendWeb.Serializers
  alias OpenApiSpex.Schema

  tags(["Admin – KV"])

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
      ok: {"KV entries", "application/json", AdminKvEntryPage},
      unauthorized: Schemas.error("Not authenticated"),
      forbidden: Schemas.error("Admin required")
    ]
  )

  def index(conn, params) do
    {page, page_size} = GamendWeb.Pagination.params(params)

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

    reply_page(
      conn,
      Enum.map(entries, &Serializers.serialize_kv_entry/1),
      page,
      page_size,
      total_count
    )
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
          user_id: %Schema{type: :string, description: "Owning user; omit or empty for none"},
          lobby_id: %Schema{type: :string, description: "Owning lobby; omit or empty for none"},
          data: %Schema{type: :object},
          metadata: %Schema{type: :object}
        },
        required: [:key, :data]
      }
    },
    responses: [
      created: {"Created", "application/json", AdminKvEntryResponse},
      unauthorized: Schemas.error("Not authenticated"),
      forbidden:
        Schemas.error(
          "Admin required, or the user already holds max_kv_entries_per_user entries (too_many_entries)"
        ),
      unprocessable_entity: Schemas.error("Validation failed")
    ]
  )

  def create(conn, params) do
    attrs = normalize_entry_attrs(params)

    case KV.create_entry(attrs) do
      {:ok, entry} ->
        reply_data(conn, :created, Serializers.serialize_kv_entry(entry))

      {:error, :too_many_entries} ->
        reply_error(conn, :forbidden, "too_many_entries")

      {:error, %Ecto.Changeset{} = cs} ->
        unprocessable(conn, cs)
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
          user_id: %Schema{type: :string, description: "Owning user; omit or empty for none"},
          lobby_id: %Schema{type: :string, description: "Owning lobby; omit or empty for none"},
          data: %Schema{type: :object},
          metadata: %Schema{type: :object}
        }
      }
    },
    responses: [
      ok: {"Updated", "application/json", AdminKvEntryResponse},
      unauthorized: Schemas.error("Not authenticated"),
      forbidden: Schemas.error("Admin required"),
      not_found: Schemas.error("Not found"),
      unprocessable_entity: Schemas.error("Validation failed")
    ]
  )

  def update(conn, %{"id" => id} = params) do
    attrs = normalize_entry_attrs(Map.delete(params, "id"))

    case KV.update_entry(id, attrs) do
      {:ok, entry} ->
        reply_data(conn, Serializers.serialize_kv_entry(entry))

      {:error, :not_found} ->
        reply_error(conn, :not_found, "not_found")

      {:error, %Ecto.Changeset{} = cs} ->
        unprocessable(conn, cs)
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
      ok: {"Deleted", "application/json", OkResponse},
      unauthorized: Schemas.error("Not authenticated"),
      forbidden: Schemas.error("Admin required")
    ]
  )

  def delete(conn, %{"id" => id}) do
    :ok = KV.delete_entry(id)
    reply_ok(conn)
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
