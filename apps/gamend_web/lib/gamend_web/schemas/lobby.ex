defmodule GamendWeb.Schemas.Lobby do
  @moduledoc """
  A lobby as `GamendWeb.Serializers.serialize_lobby/2` sends it. The fields
  that serializer adds only on request (`include_passworded`,
  `include_slowdown`, `include_spectator_count`, `include_members`) are
  declared but not required.
  """
  require OpenApiSpex
  alias GamendWeb.Schemas.UserBrief
  alias OpenApiSpex.Schema

  require Gamend.Lobbies.LobbyState, as: LobbyState

  OpenApiSpex.schema(%{
    title: "Lobby",
    description: "A lobby",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      title: %Schema{type: :string, description: "Display title"},
      host_id: %Schema{
        type: :string,
        description: "User id of the host; empty for a hostless lobby"
      },
      host_name: %Schema{type: :string, description: "Display name of the host, or empty"},
      hostless: %Schema{type: :boolean, description: "Server-managed, with no host"},
      max_users: %Schema{type: :integer, description: "Maximum number of users"},
      is_hidden: %Schema{type: :boolean, description: "Hidden from public listings"},
      is_locked: %Schema{type: :boolean, description: "Locked: no new joins"},
      state: %Schema{
        type: :string,
        description:
          "Lifecycle state in the game's vocabulary (core documents created, starting, playing, ended)"
      },
      state_changed_at: %Schema{
        type: :string,
        format: :"date-time",
        nullable: true,
        description: "When `state` last changed; null if it never has"
      },
      metadata: %Schema{type: :object, description: "Arbitrary metadata"},
      is_passworded: %Schema{type: :boolean, description: "Joining requires a password"},
      slowdown: %Schema{type: :integer, description: "Chat slowdown in seconds (0 = off)"},
      spectator_count: %Schema{type: :integer, description: "Current spectators"},
      members: %Schema{type: :array, items: UserBrief, description: "Current members"}
    },
    required: [
      :id,
      :title,
      :host_id,
      :host_name,
      :hostless,
      :max_users,
      :is_hidden,
      :is_locked,
      :state,
      :state_changed_at,
      :metadata
    ],
    example: %{
      id: "0198c0de-0001-7000-8000-000000000001",
      title: "My Game Lobby",
      host_id: "0198c0de-0002-7000-8000-000000000002",
      host_name: "PlayerOne",
      hostless: false,
      max_users: 8,
      is_hidden: false,
      is_locked: false,
      state: LobbyState.created(),
      state_changed_at: nil,
      metadata: %{},
      is_passworded: false,
      slowdown: 0
    }
  })
end

defmodule GamendWeb.Schemas.LobbyPage do
  @moduledoc "A page of lobbies."
  use GamendWeb.Schemas.Envelope, page: GamendWeb.Schemas.Lobby
end

defmodule GamendWeb.Schemas.LobbyStats do
  @moduledoc "The counters `Gamend.Lobbies.stats/0` returns."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "LobbyStats",
    description: "Lobby counts, cached for up to a minute",
    type: :object,
    properties: %{
      lobbies_total: %Schema{type: :integer},
      spectators: %Schema{type: :integer},
      by_state: %Schema{
        type: :object,
        description: "Lobby count per lifecycle state",
        additionalProperties: %Schema{type: :integer}
      }
    },
    required: [:lobbies_total, :spectators, :by_state]
  })
end

defmodule GamendWeb.Schemas.LobbyStatsResponse do
  @moduledoc "Lobby counts under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.LobbyStats
end

defmodule GamendWeb.Schemas.LobbyResponse do
  @moduledoc "One lobby under `data`; `get_lobby` includes its members and spectator count."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.Lobby
end
