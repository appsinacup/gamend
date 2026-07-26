defmodule GameServer.SchemaJSON do
  @moduledoc """
  JSON encoding for Ecto schemas under the API's null policy: string fields
  encode as `""` when nil and map fields as `%{}` — game clients (Godot in
  particular) choke on `null` where they expect a string. Datetimes, numbers
  and booleans keep `null`, where absence is semantic.

  Used from a hand-written `Jason.Encoder` impl instead of `@derive`:

      defimpl Jason.Encoder, for: MySchema do
        def encode(struct, opts) do
          GameServer.SchemaJSON.encode(struct, [:id, :title, :icon_url], opts)
        end
      end
  """

  @doc "Encode `fields` of `struct`, coalescing nil strings/maps."
  def encode(%module{} = struct, fields, opts) do
    fields
    |> Map.new(fn field ->
      {field, coalesce(Map.get(struct, field), module.__schema__(:type, field))}
    end)
    |> Jason.Encode.map(opts)
  end

  defp coalesce(nil, :string), do: ""
  defp coalesce(nil, :map), do: %{}
  defp coalesce(value, _type), do: value
end
