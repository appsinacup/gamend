defmodule GamendWeb.Schemas.KvEntry do
  @moduledoc """
  A key/value entry, the same fields the realtime `kv_updated` event carries
  (the proto's `KvEntry`), with an unset owner as `""` rather than absent.
  """
  require OpenApiSpex
  alias GamendWeb.Schemas.FreeForm
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "KvEntry",
    description: "A key/value entry",
    type: :object,
    properties: %{
      key: %Schema{type: :string},
      user_id: %Schema{type: :string, description: "Owning user; empty when not user-scoped"},
      lobby_id: %Schema{type: :string, description: "Owning lobby; empty when not lobby-scoped"},
      data: FreeForm.kv_value(description: "The stored value"),
      metadata: FreeForm.metadata()
    },
    required: [:key, :user_id, :lobby_id, :data, :metadata]
  })
end

defmodule GamendWeb.Schemas.KvEntryResponse do
  @moduledoc "One key/value entry under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.KvEntry
end
