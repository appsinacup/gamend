defmodule Gamend.Leaderboards.Record do
  @moduledoc """
  Ecto schema for the `leaderboard_records` table.

  A record represents a single score entry in a leaderboard.
  Records can be either **user-based** (one per user per leaderboard)
  or **label-based** (one per label per leaderboard, no user required).

  - User-based: `user_id` is set, `label` is nil. Uniqueness on `(leaderboard_id, user_id, key)`.
  - Label-based: `label` is set, `user_id` is nil. Uniqueness on `(leaderboard_id, label, key)`.

  `key` splits a board into separate rankings: one record per user (or
  label) per key, each key ranked on its own. `""`, the default, is a board
  with one ranking. The record's metadata says what its key stands for.
  """
  use Gamend.Schema

  @type t :: %__MODULE__{}
  import Ecto.Changeset

  alias Gamend.Accounts.User
  alias Gamend.Leaderboards.Leaderboard

  schema "leaderboard_records" do
    belongs_to :leaderboard, Leaderboard
    belongs_to :user, User

    field :label, :string
    field :key, :string, default: ""
    field :score, :integer, default: 0
    field :metadata, :map, default: %{}

    # Virtual field for rank (computed in queries)
    field :rank, :integer, virtual: true

    # A guest's own record on a public board that lists registered players
    # only (`Gamend.AccountRequired`): its rank is where it would stand.
    field :hidden, :boolean, virtual: true, default: false

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(leaderboard_id score)a
  @optional_fields ~w(user_id label key metadata)a

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
    |> validate_length(:key, max: 255)
    |> unique_constraint([:leaderboard_id, :user_id, :key])
    |> unique_constraint([:leaderboard_id, :label, :key])
    |> Gamend.Limits.validate_metadata_size(:metadata)
  end

  @doc """
  Changeset for updating an existing record's score.
  """
  def update_changeset(record, attrs) do
    record
    |> cast(attrs, [:score, :metadata])
    |> validate_required([:score])
    |> Gamend.Limits.validate_metadata_size(:metadata)
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
# Gamend.SchemaJSON — game clients choke on null).
defimpl Jason.Encoder, for: Gamend.Leaderboards.Record do
  def encode(record, opts) do
    Gamend.SchemaJSON.encode(
      record,
      [
        :id,
        :leaderboard_id,
        :user_id,
        :label,
        :key,
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
