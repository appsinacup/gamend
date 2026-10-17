defmodule GamendWeb.Schemas.Leaderboard do
  @moduledoc "A leaderboard as `GamendWeb.Api.V1.LeaderboardController` sends it."
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "Leaderboard",
    description: "A leaderboard (one season of a slug)",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      slug: %Schema{
        type: :string,
        description: "Human-readable identifier, shared by every season"
      },
      title: %Schema{type: :string},
      description: %Schema{type: :string},
      icon_url: %Schema{
        type: :string,
        description: "Empty when unset (the client applies its own default)"
      },
      sort_order: %Schema{
        type: :string,
        enum: ["desc", "asc"],
        description: "`desc`: higher is better; `asc`: lower is better"
      },
      operator: %Schema{
        type: :string,
        enum: ["set", "best", "incr", "decr"],
        description: "How a submitted score combines with the stored one"
      },
      starts_at: %Schema{type: :string, format: :"date-time", nullable: true},
      ends_at: %Schema{
        type: :string,
        format: :"date-time",
        nullable: true,
        description: "Null for a permanent leaderboard"
      },
      is_active: %Schema{type: :boolean, description: "Still accepting scores"},
      metadata: %Schema{type: :object},
      inserted_at: %Schema{type: :string, format: :"date-time"},
      updated_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [
      :id,
      :slug,
      :title,
      :description,
      :icon_url,
      :sort_order,
      :operator,
      :starts_at,
      :ends_at,
      :is_active,
      :metadata,
      :inserted_at,
      :updated_at
    ],
    example: %{
      id: "0198c0de-0001-7000-8000-000000000001",
      slug: "weekly_kills",
      title: "Weekly Kills",
      description: "Get the most kills this week!",
      icon_url: "",
      sort_order: "desc",
      operator: "incr",
      starts_at: "2025-12-02T00:00:00Z",
      ends_at: nil,
      is_active: true,
      metadata: %{},
      inserted_at: "2025-12-02T10:00:00Z",
      updated_at: "2025-12-02T10:00:00Z"
    }
  })
end

defmodule GamendWeb.Schemas.LeaderboardRecord do
  @moduledoc """
  One ranked row. A record is a user's, or a label's (a team, a guild): a
  label record has empty `user_id` and `username`, and its text in
  `display_name`.
  """
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "LeaderboardRecord",
    description: "A ranked leaderboard record",
    type: :object,
    properties: %{
      rank: %Schema{type: :integer, description: "1 is the top of the board"},
      hidden: %Schema{
        type: :boolean,
        description:
          "True on a guest's own record that the board does not list (the server " <>
            "requires an account to be listed): `rank` is where it would stand. " <>
            "Register to be listed."
      },
      user_id: %Schema{type: :string, description: "Empty for a label record"},
      username: %Schema{type: :string, description: "Empty for a label record"},
      display_name: %Schema{
        type: :string,
        description: "The user's display name, or the label's text"
      },
      score: %Schema{type: :integer},
      metadata: %Schema{type: :object, description: "Per-record metadata"},
      updated_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [
      :rank,
      :hidden,
      :user_id,
      :username,
      :display_name,
      :score,
      :metadata,
      :updated_at
    ],
    example: %{
      rank: 1,
      hidden: false,
      user_id: "0198c0de-0002-7000-8000-000000000002",
      username: "progamer123-4821",
      display_name: "ProGamer123",
      score: 5000,
      metadata: %{weapon: "sword"},
      updated_at: "2025-12-02T10:00:00Z"
    }
  })
end

defmodule GamendWeb.Schemas.LeaderboardsBySlug do
  @moduledoc "The active season of each resolved slug, keyed by slug."
  require OpenApiSpex
  alias GamendWeb.Schemas.Leaderboard

  OpenApiSpex.schema(%{
    title: "LeaderboardsBySlug",
    description: "Slug to its active leaderboard; a slug with none is left out",
    type: :object,
    additionalProperties: Leaderboard
  })
end

defmodule GamendWeb.Schemas.LeaderboardPage do
  @moduledoc "A page of leaderboards."
  use GamendWeb.Schemas.Envelope, page: GamendWeb.Schemas.Leaderboard
end

defmodule GamendWeb.Schemas.LeaderboardResponse do
  @moduledoc "One leaderboard under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.Leaderboard
end

defmodule GamendWeb.Schemas.LeaderboardsBySlugResponse do
  @moduledoc "Resolved slugs under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.LeaderboardsBySlug
end

defmodule GamendWeb.Schemas.LeaderboardRecordPage do
  @moduledoc "A page of leaderboard records."
  use GamendWeb.Schemas.Envelope, page: GamendWeb.Schemas.LeaderboardRecord
end

defmodule GamendWeb.Schemas.LeaderboardRecordResponse do
  @moduledoc "One leaderboard record under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.LeaderboardRecord
end
