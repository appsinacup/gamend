defmodule GamendWeb.Schemas.ReadyCheckParticipant do
  @moduledoc "One participant's answer, as the realtime proto's `ReadyCheckParticipant`."
  require OpenApiSpex
  alias Gamend.ReadyChecks.ParticipantState
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "ReadyCheckParticipant",
    description: "A participant's answer",
    type: :object,
    properties: %{
      user_id: %Schema{type: :string, format: :uuid},
      display_name: %Schema{type: :string},
      state: %Schema{
        type: :string,
        enum: ParticipantState.all()
      },
      responded_at: %Schema{type: :string, format: :"date-time", nullable: true}
    },
    required: [:user_id, :display_name, :state, :responded_at]
  })
end

defmodule GamendWeb.Schemas.ReadyCheckState do
  @moduledoc """
  A ready check as the caller sees it, as `GamendWeb.Serializers.serialize_ready_check/2`
  sends it over REST and realtime (the proto's `ReadyCheckState`). A lobby or
  party board sets one of `lobby_id`/`party_id`; a matchmaking accept check
  neither, and lists no participants.
  """
  require OpenApiSpex
  alias Gamend.ReadyChecks.CheckKind
  alias Gamend.ReadyChecks.CheckStatus
  alias GamendWeb.Schemas.ReadyCheckParticipant
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "ReadyCheckState",
    description: "A ready check",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      kind: %Schema{type: :string, enum: CheckKind.all()},
      status: %Schema{
        type: :string,
        enum: CheckStatus.all()
      },
      lobby_id: %Schema{type: :string, description: "Empty unless a lobby board"},
      party_id: %Schema{type: :string, description: "Empty unless a party board"},
      deadline_at: %Schema{
        type: :string,
        format: :"date-time",
        nullable: true,
        description: "Null for a board with no deadline"
      },
      opened_by: %Schema{type: :string, description: "Empty when the server opened it"},
      reason: %Schema{
        type: :string,
        description: "Why it failed: `declined`, `timeout` or `cancelled`; empty otherwise"
      },
      metadata: %Schema{type: :object},
      total: %Schema{type: :integer},
      ready_count: %Schema{type: :integer},
      your_state: %Schema{
        type: :string,
        description: "The caller's own answer; empty when not a participant"
      },
      participants: %Schema{
        type: :array,
        items: ReadyCheckParticipant,
        description: "Only on kind `ready`: an accept check shows counts alone"
      }
    },
    required: [
      :id,
      :kind,
      :status,
      :lobby_id,
      :party_id,
      :deadline_at,
      :opened_by,
      :reason,
      :metadata,
      :total,
      :ready_count,
      :your_state
    ]
  })
end

defmodule GamendWeb.Schemas.MyReadyChecks do
  @moduledoc "The caller's open check in each lane."
  require OpenApiSpex
  alias GamendWeb.Schemas.ReadyCheckState
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "MyReadyChecks",
    description: "The open check per lane; null where there is none",
    type: :object,
    properties: %{
      lobby: %Schema{
        allOf: [ReadyCheckState],
        nullable: true,
        description: "The match lane: a lobby ready-up or a matchmaking accept"
      },
      party: %Schema{
        allOf: [ReadyCheckState],
        nullable: true,
        description: "The party's standing ready board"
      }
    },
    required: [:lobby, :party]
  })
end

defmodule GamendWeb.Schemas.ReadyCheckStateResponse do
  @moduledoc "One ready check under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.ReadyCheckState
end

defmodule GamendWeb.Schemas.MyReadyChecksResponse do
  @moduledoc "The caller's checks per lane under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.MyReadyChecks
end
