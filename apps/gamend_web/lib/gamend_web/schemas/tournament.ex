defmodule GamendWeb.Schemas.TournamentEntry do
  @moduledoc """
  A registration, as `GamendWeb.Api.V1.TournamentController` sends it. The
  entry's leader is the user who registered it; `seed` and `bracket_index`
  are set by the draw.
  """
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "TournamentEntry",
    description: "An entry in a tournament",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      leader_id: %Schema{type: :string, format: :uuid},
      seed: %Schema{type: :integer, nullable: true, description: "Null until the draw"},
      bracket_index: %Schema{
        type: :integer,
        nullable: true,
        description: "Null until the draw"
      },
      wins: %Schema{type: :integer},
      state: %Schema{type: :string, enum: ["registered", "active", "eliminated", "winner"]},
      metadata: %Schema{type: :object}
    },
    required: [:id, :leader_id, :seed, :bracket_index, :wins, :state, :metadata]
  })
end

defmodule GamendWeb.Schemas.Tournament do
  @moduledoc "A tournament occurrence, as `GamendWeb.Api.V1.TournamentController` sends it."
  require OpenApiSpex
  alias GamendWeb.Schemas.TournamentEntry
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "Tournament",
    description: "A tournament occurrence",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      slug: %Schema{
        type: :string,
        description: "In any script, shared by every recurring occurrence"
      },
      title: %Schema{type: :string},
      description: %Schema{type: :string},
      icon_url: %Schema{
        type: :string,
        description: "Empty when unset (the client applies its own default)"
      },
      state: %Schema{
        type: :string,
        enum: ["scheduled", "registration", "running", "finished", "cancelled"]
      },
      registration_opens_at: %Schema{type: :string, format: :"date-time", nullable: true},
      starts_at: %Schema{
        type: :string,
        format: :"date-time",
        nullable: true,
        description: "Null when an admin starts it by hand"
      },
      ends_at: %Schema{type: :string, format: :"date-time", nullable: true},
      recur: %Schema{type: :string, description: "Cron expression; empty for a one-shot"},
      max_entries: %Schema{type: :integer, nullable: true, description: "Null for no cap"},
      team_size: %Schema{type: :integer, description: "Advisory; enforced by game hooks"},
      bracket_size: %Schema{type: :integer},
      round_window_sec: %Schema{type: :integer},
      entry_count: %Schema{type: :integer},
      metadata: %Schema{type: :object},
      my_entry: %Schema{
        allOf: [TournamentEntry],
        nullable: true,
        description:
          "The caller's entry. Only `GET /tournaments/{id}` sends it; null when the " <>
            "caller has none or is not signed in."
      }
    },
    required: [
      :id,
      :slug,
      :title,
      :description,
      :icon_url,
      :state,
      :registration_opens_at,
      :starts_at,
      :ends_at,
      :recur,
      :max_entries,
      :team_size,
      :bracket_size,
      :round_window_sec,
      :entry_count,
      :metadata
    ]
  })
end

defmodule GamendWeb.Schemas.TournamentMatch do
  @moduledoc """
  One match of a bracket. A slot not yet filled has empty entry and leader
  ids; `winner_entry_id` stays empty and `resolved_at` null until it is
  decided.
  """
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "TournamentMatch",
    description: "A match between two entries",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      bracket_index: %Schema{type: :integer},
      round: %Schema{type: :integer, description: "1 is the first round"},
      slot: %Schema{type: :integer, description: "Position within the round"},
      a_entry_id: %Schema{type: :string, description: "Empty until the slot is filled"},
      b_entry_id: %Schema{type: :string, description: "Empty until the slot is filled"},
      a_leader_id: %Schema{type: :string, description: "Empty until the slot is filled"},
      b_leader_id: %Schema{type: :string, description: "Empty until the slot is filled"},
      winner_entry_id: %Schema{type: :string, description: "Empty until decided"},
      deadline_at: %Schema{type: :string, format: :"date-time", nullable: true},
      resolved_at: %Schema{type: :string, format: :"date-time", nullable: true},
      metadata: %Schema{type: :object}
    },
    required: [
      :id,
      :bracket_index,
      :round,
      :slot,
      :a_entry_id,
      :b_entry_id,
      :a_leader_id,
      :b_leader_id,
      :winner_entry_id,
      :deadline_at,
      :resolved_at,
      :metadata
    ]
  })
end

defmodule GamendWeb.Schemas.TournamentBracket do
  @moduledoc """
  One bracket with its matches, and the entries those matches name, so a
  client draws the bracket from one row.
  """
  require OpenApiSpex
  alias GamendWeb.Schemas.{TournamentEntry, TournamentMatch}
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "TournamentBracket",
    description: "A bracket, its matches and their entries",
    type: :object,
    properties: %{
      index: %Schema{type: :integer},
      size: %Schema{type: :integer, description: "Entries the bracket seats"},
      matches: %Schema{
        type: :array,
        items: TournamentMatch,
        description: "By round, then slot"
      },
      entries: %Schema{
        type: :array,
        items: TournamentEntry,
        description: "The entries appearing in `matches`"
      }
    },
    required: [:index, :size, :matches, :entries]
  })
end

defmodule GamendWeb.Schemas.TournamentPlacement do
  @moduledoc "An entry's final standing."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "TournamentPlacement",
    description: "An entry's placement: winners first, then by wins",
    type: :object,
    properties: %{
      placement: %Schema{type: :integer, description: "1 is first"},
      entry_id: %Schema{type: :string, format: :uuid},
      leader_id: %Schema{type: :string, format: :uuid},
      wins: %Schema{type: :integer},
      state: %Schema{type: :string, enum: ["registered", "active", "eliminated", "winner"]},
      bracket_index: %Schema{type: :integer, nullable: true}
    },
    required: [:placement, :entry_id, :leader_id, :wins, :state, :bracket_index]
  })
end

defmodule GamendWeb.Schemas.TournamentStandings do
  @moduledoc "Champions and every entry's placement."
  require OpenApiSpex
  alias GamendWeb.Schemas.{TournamentEntry, TournamentPlacement}
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "TournamentStandings",
    description: "Champions (one per bracket once decided) and every placement",
    type: :object,
    properties: %{
      champions: %Schema{type: :array, items: TournamentEntry},
      placements: %Schema{type: :array, items: TournamentPlacement}
    },
    required: [:champions, :placements]
  })
end

defmodule GamendWeb.Schemas.TournamentPage do
  @moduledoc "A page of tournaments."
  use GamendWeb.Schemas.Envelope, page: GamendWeb.Schemas.Tournament
end

defmodule GamendWeb.Schemas.TournamentResponse do
  @moduledoc "One tournament under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.Tournament
end

defmodule GamendWeb.Schemas.TournamentEntryPage do
  @moduledoc "A page of tournament entries."
  use GamendWeb.Schemas.Envelope, page: GamendWeb.Schemas.TournamentEntry
end

defmodule GamendWeb.Schemas.TournamentEntryResponse do
  @moduledoc "One tournament entry under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.TournamentEntry
end

defmodule GamendWeb.Schemas.TournamentBracketPage do
  @moduledoc "A page of brackets."
  use GamendWeb.Schemas.Envelope, page: GamendWeb.Schemas.TournamentBracket
end

defmodule GamendWeb.Schemas.TournamentMatchResponse do
  @moduledoc "One match under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.TournamentMatch
end

defmodule GamendWeb.Schemas.TournamentStandingsResponse do
  @moduledoc "Standings under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.TournamentStandings
end
