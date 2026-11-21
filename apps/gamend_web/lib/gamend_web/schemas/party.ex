defmodule GamendWeb.Schemas.Party do
  @moduledoc """
  A party as `GamendWeb.Serializers.serialize_party/2` sends it, members
  included. The party endpoints ask for the timestamps; other callers leave
  them out, so they are not required.
  """
  require OpenApiSpex
  alias GamendWeb.Schemas.UserBrief
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "Party",
    description: "A party",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      leader_id: %Schema{type: :string, format: :uuid},
      leader_name: %Schema{type: :string, description: "Leader's display name"},
      max_size: %Schema{type: :integer, description: "Maximum members"},
      metadata: GamendWeb.Schemas.FreeForm.metadata(),
      members: %Schema{type: :array, items: UserBrief},
      inserted_at: %Schema{type: :string, format: :"date-time"},
      updated_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [:id, :leader_id, :leader_name, :max_size, :metadata, :members]
  })
end

defmodule GamendWeb.Schemas.PartyInvite do
  @moduledoc "An invitation to a party, as `Gamend.Parties` lists it."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "PartyInvite",
    description: "An invitation to join a party",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      party_id: %Schema{type: :string, format: :uuid},
      sender_id: %Schema{type: :string, format: :uuid},
      sender_name: %Schema{type: :string},
      recipient_id: %Schema{type: :string, format: :uuid},
      recipient_name: %Schema{type: :string},
      status: %Schema{type: :string},
      inserted_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [
      :id,
      :party_id,
      :sender_id,
      :sender_name,
      :recipient_id,
      :recipient_name,
      :status,
      :inserted_at
    ]
  })
end

defmodule GamendWeb.Schemas.PartyStats do
  @moduledoc "The counters `Gamend.Parties.stats/0` returns."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "PartyStats",
    description: "Party counts, cached for up to a minute",
    type: :object,
    properties: %{
      parties_active: %Schema{type: :integer},
      players_in_parties: %Schema{type: :integer}
    },
    required: [:parties_active, :players_in_parties]
  })
end

defmodule GamendWeb.Schemas.PartyStatsResponse do
  @moduledoc "Party counts under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.PartyStats
end

defmodule GamendWeb.Schemas.PartyResponse do
  @moduledoc "One party under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.Party
end

defmodule GamendWeb.Schemas.PartyInvitePage do
  @moduledoc "A page of party invitations."
  use GamendWeb.Schemas.Envelope, page: GamendWeb.Schemas.PartyInvite
end
