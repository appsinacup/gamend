defmodule GameServer.Leaderboards.Record do
  @moduledoc """
  Ecto schema for the `leaderboard_records` table.

  A record represents a single score entry in a leaderboard.
  Records can be either **user-based** (one per user per leaderboard)
  or **label-based** (one per label per leaderboard, no user required).

  - User-based: `user_id` is set, `label` is nil. Uniqueness on `(leaderboard_id, user_id)`.
  - Label-based: `label` is set, `user_id` is nil. Uniqueness on `(leaderboard_id, label)`.
  """
  use GameServer.Schema

  @type t :: %__MODULE__{}
  import Ecto.Changeset

  alias GameServer.Accounts.User
  alias GameServer.Leaderboards.Leaderboard

  schema "leaderboard_records" do
    belongs_to :leaderboard, Leaderboard
    belongs_to :user, User

    field :label, :string
    field :score, :integer, default: 0
    field :metadata, :map, default: %{}

    # Virtual field for rank (computed in queries)
    field :rank, :integer, virtual: true

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(leaderboard_id score)a
  @optional_fields ~w(user_id label metadata)a

  @doc """
  Changeset for creating a new record.
  Either `user_id` or `label` must be provided (but not both).
  """
  def changeset(record, attrs) do
    record
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_user_or_label()
    |> foreign_key_constraint(:leaderboard_id)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint([:leaderboard_id, :user_id])
    |> unique_constraint([:leaderboard_id, :label])
    |> GameServer.Limits.validate_metadata_size(:metadata)
  end

  @doc """
  Changeset for updating an existing record's score.
  """
  def update_changeset(record, attrs) do
    record
    |> cast(attrs, [:score, :metadata])
    |> validate_required([:score])
    |> GameServer.Limits.validate_metadata_size(:metadata)
  end

  # Validate that exactly one of user_id or label is set.
  defp validate_user_or_label(changeset) do
    user_id = get_field(changeset, :user_id)
    label = get_field(changeset, :label)

    cond do
      is_nil(user_id) and (is_nil(label) or label == "") ->
        add_error(changeset, :base, "either user_id or label must be provided")

      not is_nil(user_id) and not is_nil(label) and label != "" ->
        add_error(changeset, :base, "cannot set both user_id and label")

      true ->
        changeset
    end
  end
end

# Hand-written rather than @derive so nil strings encode as "" (see
# GameServer.SchemaJSON — game clients choke on null).
defimpl Jason.Encoder, for: GameServer.Leaderboards.Record do
  def encode(record, opts) do
    GameServer.SchemaJSON.encode(
      record,
      [
        :id,
        :leaderboard_id,
        :user_id,
        :label,
        :score,
        :rank,
        :metadata,
        :inserted_at,
        :updated_at
      ],
      opts
    )
  end
end
