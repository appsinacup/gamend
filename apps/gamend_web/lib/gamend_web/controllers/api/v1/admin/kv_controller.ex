defmodule GamendWeb.Api.V1.Admin.KvController do
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gamend.KV
  alias GamendWeb.Schemas
  alias GamendWeb.Schemas.{AdminKvEntryResponse, FreeForm, OkResponse}
  alias GamendWeb.Serializers
  alias OpenApiSpex.Schema

  tags(["Admin – KV"])

  operation(:upsert,
    operation_id: "admin_upsert_kv",
    summary: "Upsert KV by key (admin)",
    security: [%{"authorization" => []}],
    request_body: {
      "KV upsert",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          key: %Schema{type: :string},
          user_id: %Schema{type: :string, description: "Owning user; omit or empty for none"},
          lobby_id: %Schema{type: :string, description: "Owning lobby; omit or empty for none"},
          data: FreeForm.kv_value(),
          value: FreeForm.kv_value(description: "The same as `data`, read when `data` is absent"),
          metadata: FreeForm.metadata()
        },
        # `data` or `value`: the action answers 422 when both are missing.
        required: [:key]
      }
    },
    responses: [
      ok: {"KV entry", "application/json", AdminKvEntryResponse},
      unauthorized: Schemas.error("Not authenticated"),
      forbidden: Schemas.error("Admin required"),
      unprocessable_entity: Schemas.error("Validation failed")
    ]
  )

  def upsert(conn, %{"key" => key} = params) do
    data = Map.get(params, "data") || Map.get(params, "value")

    if is_nil(data) do
      unprocessable(conn, %{data: "can't be blank"})
    else
      metadata = Map.get(params, "metadata") || %{}

      user_id =
        case Map.get(params, "user_id") do
          nil ->
            nil

          "" ->
            nil

          v when is_binary(v) ->
            case Ecto.UUID.cast(v) do
              {:ok, uuid} -> uuid
              :error -> nil
            end

          _ ->
            nil
        end

      lobby_id =
        case Map.get(params, "lobby_id") do
          nil ->
            nil

          "" ->
            nil

          v when is_binary(v) ->
            case Ecto.UUID.cast(v) do
              {:ok, uuid} -> uuid
              :error -> nil
            end

          _ ->
            nil
        end

      case KV.put(key, data, metadata, user_id: user_id, lobby_id: lobby_id) do
        {:ok, entry} ->
          reply_data(conn, Serializers.serialize_kv_entry(entry))

        {:error, %Ecto.Changeset{} = cs} ->
          unprocessable(conn, cs)
      end
    end
  end

  operation(:delete,
    operation_id: "admin_delete_kv",
    summary: "Delete KV by key (admin)",
    security: [%{"authorization" => []}],
    parameters: [
      key: [in: :query, schema: %Schema{type: :string}, required: true],
      user_id: [in: :query, schema: %Schema{type: :string, format: :uuid}, required: false],
      lobby_id: [in: :query, schema: %Schema{type: :string, format: :uuid}, required: false]
    ],
    responses: [
      ok: {"Deleted", "application/json", OkResponse},
      unauthorized: Schemas.error("Not authenticated"),
      forbidden: Schemas.error("Admin required")
    ]
  )

  def delete(conn, %{"key" => key} = params) do
    user_id =
      case Map.get(params, "user_id") do
        nil ->
          nil

        "" ->
          nil

        v when is_binary(v) ->
          case Ecto.UUID.cast(v) do
            {:ok, uuid} -> uuid
            :error -> nil
          end

        _ ->
          nil
      end

    lobby_id =
      case Map.get(params, "lobby_id") do
        nil ->
          nil

        "" ->
          nil

        v when is_binary(v) ->
          case Ecto.UUID.cast(v) do
            {:ok, uuid} -> uuid
            :error -> nil
          end

        _ ->
          nil
      end

    :ok = KV.delete(key, user_id: user_id, lobby_id: lobby_id)
    reply_ok(conn)
  end
end
