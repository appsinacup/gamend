defmodule GameServer.Leaderboards.Leaderboard do
  @moduledoc """
  Ecto schema for the `leaderboards` table.

  A leaderboard is a self-contained scoreboard that can be permanent or time-limited.
  Each leaderboard has its own settings for sort order and score operator.

  ## Slug
  The `slug` is a human-readable identifier (e.g., "weekly_kills") that can be reused
  across multiple leaderboard instances (seasons). Use the slug to always target the
  currently active leaderboard, or use the integer `id` for a specific instance.

  ## Icon
  `icon_url` is optional; when nil, clients show their default leaderboard
  icon (the web UI uses `GameServerWeb.Icons.default(:leaderboard)`).

  ## Sort Order
  - `:desc` — Higher scores rank first (default)
  - `:asc` — Lower scores rank first (e.g., fastest time)

  ## Operators
  - `:set` — Always replace with new score
  - `:best` — Only update if new score is better (default)
  - `:incr` — Add to existing score
  - `:decr` — Subtract from existing score
  """
  use GameServer.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}
  @type sort_order :: :desc | :asc
  @type operator :: :set | :best | :incr | :decr

  @sort_orders ~w(desc asc)a
  @operators ~w(set best incr decr)a

  schema "leaderboards" do
    field :slug, :string
    field :title, :string
    field :description, :string, default: ""
    field :icon_url, :string
    field :sort_order, Ecto.Enum, values: @sort_orders, default: :desc
    field :operator, Ecto.Enum, values: @operators, default: :best
    field :starts_at, :utc_datetime
    field :ends_at, :utc_datetime
    field :metadata, :map, default: %{}

    has_many :records, GameServer.Leaderboards.Record

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(slug title)a
  @optional_fields ~w(description icon_url sort_order operator starts_at ends_at metadata)a

  @doc """
  Changeset for creating a new leaderboard.
  """
  def changeset(leaderboard, attrs) do
    leaderboard
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:slug, min: 1, max: GameServer.Limits.get(:max_leaderboard_slug))
    |> validate_length(:icon_url, max: GameServer.Limits.get(:max_profile_url))
    |> validate_format(:slug, ~r/^[a-z0-9_]+$/,
      message: "must be lowercase alphanumeric with underscores"
    )
    |> validate_length(:title, min: 1, max: GameServer.Limits.get(:max_leaderboard_title))
    |> validate_inclusion(:sort_order, @sort_orders)
    |> validate_inclusion(:operator, @operators)
    |> validate_length(:description, max: GameServer.Limits.get(:max_leaderboard_description))
    |> GameServer.Limits.validate_metadata_size(:metadata)
  end

  @doc """
  Changeset for updating an existing leaderboard.
  Does not allow changing slug, sort_order, or operator after creation.
  """
  def update_changeset(leaderboard, attrs) do
    leaderboard
    |> cast(attrs, [:title, :description, :icon_url, :starts_at, :ends_at, :metadata])
    |> validate_length(:icon_url, max: GameServer.Limits.get(:max_profile_url))
    |> validate_length(:title, min: 1, max: GameServer.Limits.get(:max_leaderboard_title))
    |> validate_length(:description, max: GameServer.Limits.get(:max_leaderboard_description))
    |> GameServer.Limits.validate_metadata_size(:metadata)
  end

  @doc """
  Returns true if the leaderboard is currently active (not ended).
  """
  def active?(%__MODULE__{ends_at: nil}), do: true

  def active?(%__MODULE__{ends_at: ends_at}),
    do: DateTime.compare(ends_at, DateTime.utc_now()) == :gt

  @doc """
  Returns true if the leaderboard has ended.
  """
  def ended?(%__MODULE__{} = lb), do: not active?(lb)
end

# Hand-written rather than @derive so optional strings encode as "" instead of
# null — game clients (Godot) choke on null where they expect a string.
defimpl Jason.Encoder, for: GameServer.Leaderboards.Leaderboard do
  def encode(lb, opts) do
    GameServer.SchemaJSON.encode(
      lb,
      [
        :id,
        :slug,
        :title,
        :description,
        :icon_url,
        :sort_order,
        :operator,
        :starts_at,
        :ends_at,
        :metadata,
        :inserted_at,
        :updated_at
      ],
      opts
    )
  end
end
