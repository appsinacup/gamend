defmodule GamendWeb.Schemas.ClientLogEntry do
  @moduledoc """
  One line from a game client.

  `at` and `seq` come from the client and are kept as sent. Neither is
  trustworthy — phone clocks drift, and a client can renumber — which is
  exactly why they are worth having next to the server's own receive order:
  the disagreement is the diagnostic.
  """
  require OpenApiSpex
  alias OpenApiSpex.Schema

  require Gamend.ClientLogs.LogLevel, as: LogLevel

  @game "game"

  OpenApiSpex.schema(%{
    title: "ClientLogEntry",
    description: "A single client log entry",
    type: :object,
    properties: %{
      seq: %Schema{
        type: :integer,
        description:
          "Monotonic counter within the session. A gap tells the server entries were lost.",
        example: 42
      },
      at: %Schema{
        type: :number,
        description: "Client clock, seconds since the Unix epoch.",
        example: 1_755_600_000.5
      },
      level: %Schema{
        type: :string,
        enum: LogLevel.all(),
        description: "Client level. Carried through as data; see the capture policy.",
        example: LogLevel.info()
      },
      category: %Schema{
        type: :string,
        description: "Free-form subsystem tag owned by the game, e.g. game, network, perf.",
        example: @game
      },
      message: %Schema{type: :string, description: "The line itself.", example: "Game starting"},
      lobby_id: %Schema{
        type: :string,
        description:
          "Lobby the client was in, if any. The join key to server-side lobby history.",
        example: ""
      },
      screen: %Schema{
        type: :string,
        description: "Where the player was, used to band a session into phases.",
        example: "world_map"
      }
    },
    required: [:message]
  })
end

defmodule GamendWeb.Schemas.ClientLogSession do
  @moduledoc """
  The run a batch belongs to. Sent with every batch so the server can create
  the session on first contact without a prior handshake — a client that has to
  register before it can log cannot report a failure that happens before it
  registers.
  """
  require OpenApiSpex
  alias Gamend.ClientLogs.Session
  alias OpenApiSpex.Schema

  require Gamend.ClientLogs.BuildKind, as: BuildKind
  require Gamend.ClientLogs.LogLevel, as: LogLevel

  @ro "ro"

  OpenApiSpex.schema(%{
    title: "ClientLogSession",
    description: "Identity and environment of the client run",
    type: :object,
    properties: %{
      client_session_id: %Schema{
        type: :string,
        description:
          "Client-generated id, unique per run. Bound to the first caller that uses it; " <>
            "a later batch from a different user is refused.",
        minLength: 8,
        maxLength: 128,
        example: "0f1e2d3c4b5a69788796a5b4c3d2e1f0"
      },
      device_id: %Schema{type: :string, description: "Stable device identifier.", example: ""},
      platform: %Schema{
        type: :string,
        enum: Session.platforms(),
        example: "android"
      },
      app_version: %Schema{type: :string, example: "1.4.2"},
      build: %Schema{
        type: :string,
        enum: [LogLevel.debug(), BuildKind.release()],
        example: BuildKind.release()
      },
      locale: %Schema{type: :string, example: @ro},
      started_at: %Schema{
        type: :number,
        description: "When the run began, client clock, seconds since the Unix epoch."
      },
      meta: %Schema{
        type: :object,
        description: "Free-form device facts: model, GPU, screen size. Capped server-side.",
        additionalProperties: true
      }
    },
    required: [:client_session_id]
  })
end

defmodule GamendWeb.Schemas.ClientLogBatch do
  @moduledoc """
  A batch upload: the run, and the lines collected since the last flush.
  """
  require OpenApiSpex
  alias GamendWeb.Schemas.ClientLogEntry
  alias GamendWeb.Schemas.ClientLogSession
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "ClientLogBatch",
    description: "A batch of client log entries with the session they belong to",
    type: :object,
    properties: %{
      session: ClientLogSession,
      entries: %Schema{
        type: :array,
        items: ClientLogEntry,
        description: "At most 200 per call; the surplus is discarded and counted as dropped."
      }
    },
    required: [:session, :entries]
  })
end

defmodule GamendWeb.Schemas.ClientLogResult do
  @moduledoc """
  What the server did with a batch.

  `dropped` is the honest count, covering both entries the client never sent
  (a gap in its sequence) and entries this call discarded. A client that sees it
  climb is losing logs and should flush more often.
  """
  require OpenApiSpex
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(%{
    title: "ClientLogResult",
    description: "Outcome of a client log upload",
    type: :object,
    properties: %{
      client_session_id: %Schema{type: :string, example: "0f1e2d3c4b5a6978"},
      accepted: %Schema{type: :integer, description: "Entries recorded.", example: 12},
      dropped: %Schema{
        type: :integer,
        description: "Entries lost before or during this call.",
        example: 0
      },
      errors: %Schema{
        type: :integer,
        description: "Error-level entries in this batch.",
        example: 0
      }
    },
    required: [:client_session_id, :accepted, :dropped, :errors]
  })
end

defmodule GamendWeb.Schemas.ClientLogPolicy do
  @moduledoc """
  What the server wants collected. The client gates its own uploads on this, so
  verbosity is a server-side decision that needs no new build to change.
  """
  require OpenApiSpex
  alias OpenApiSpex.Schema

  require Gamend.ClientLogs.LogLevel, as: LogLevel

  OpenApiSpex.schema(%{
    title: "ClientLogPolicy",
    description: "Capture policy for game clients",
    type: :object,
    properties: %{
      enabled: %Schema{type: :boolean, description: "Collect at all.", example: true},
      level: %Schema{
        type: :string,
        enum: LogLevel.all(),
        description: "Lowest level to upload.",
        example: LogLevel.info()
      },
      categories: %Schema{
        type: :object,
        description:
          "Per-category overrides of the floor, e.g. {\"perf\": \"off\"}. off drops the category.",
        additionalProperties: %Schema{type: :string}
      },
      batch_max: %Schema{type: :integer, description: "Entries accepted per call.", example: 200},
      message_max_bytes: %Schema{
        type: :integer,
        description: "Longer messages are truncated server-side.",
        example: 2000
      }
    },
    required: [:enabled, :level, :categories, :batch_max, :message_max_bytes]
  })
end

defmodule GamendWeb.Schemas.ClientLogPolicyResponse do
  @moduledoc "The capture policy under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.ClientLogPolicy
end

defmodule GamendWeb.Schemas.ClientLogResultResponse do
  @moduledoc "An upload's outcome under `data`."
  use GamendWeb.Schemas.Envelope, data: GamendWeb.Schemas.ClientLogResult
end
