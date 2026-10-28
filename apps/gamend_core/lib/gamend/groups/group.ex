defmodule Gamend.Groups.Group do
  @moduledoc """
  Ecto schema for the `groups` table.

  A group is a persistent community that users can join. Unlike lobbies (which
  are ephemeral game sessions), groups are long-lived and support admin roles,
  join-request workflows, and invitation flows.

  ## Fields

  - `title` – human-readable display title (unique)
  - `description` – optional longer description
  - `icon_url` – optional icon; `nil` means clients show their default group icon
  - `type` – visibility: `"public"`, `"private"`, or `"hidden"`
  - `max_members` – maximum number of members (default 100)
  - `metadata` – arbitrary server-managed key/value map
  - `creator_id` – the user who originally created the group
  """
  use Gamend.Schema
  import Ecto.Changeset

  alias Gamend.Accounts.User
  alias Gamend.Groups.GroupMember

  @type t :: %__MODULE__{}

  schema "groups" do
    field :title, :string
    field :description, :string, default: ""
    field :icon_url, :string
    field :type, :string, default: "public"
    field :max_members, :integer, default: 100
    field :metadata, :map, default: %{}
    field :slowdown, :integer, default: 0

    belongs_to :creator, User
    has_many :members, GroupMember

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(title)a
  @optional_fields ~w(description icon_url type max_members metadata slowdown)a

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(group, attrs) do
    group
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:title, min: 1, max: Gamend.Limits.get(:max_group_title))
    |> validate_length(:description, max: Gamend.Limits.get(:max_group_description))
    |> validate_length(:icon_url, max: Gamend.Limits.get(:max_profile_url))
    |> put_default_type()
    |> validate_inclusion(:type, Gamend.Groups.types())
    |> validate_number(:max_members,
      greater_than: 0,
      less_than_or_equal_to: Gamend.Limits.get(:max_group_members)
    )
    |> validate_number(:slowdown, greater_than_or_equal_to: 0, less_than_or_equal_to: 3600)
    |> unique_constraint(:title)
    |> Gamend.Limits.validate_metadata_size(:metadata)
  end

  # A new group given no type is the host's default (`Gamend.Groups.types/0`),
  # which is the schema's "public" unless the host does not allow it. One
  # given "public" is checked here: it equals the schema's default, so `cast`
  # records no change and `validate_inclusion/3` would never see it.
  defp put_default_type(%{data: %{__meta__: %{state: :built}}} = changeset) do
    types = Gamend.Groups.types()

    case changeset.params do
      %{"type" => type} when is_binary(type) and type != "" ->
        if type in types,
          do: changeset,
          else: add_error(changeset, :type, "is invalid", validation: :inclusion, enum: types)

      _none ->
        put_change(changeset, :type, hd(types))
    end
  end

  defp put_default_type(changeset), do: changeset
end

# Hand-written rather than @derive so optional strings encode as "" instead of
# null — game clients (Godot) choke on null where they expect a string.
defimpl Jason.Encoder, for: Gamend.Groups.Group do
  def encode(group, opts) do
    Gamend.SchemaJSON.encode(
      group,
      [
        :id,
        :title,
        :description,
        :icon_url,
        :type,
        :max_members,
        :metadata,
        :creator_id,
        :inserted_at,
        :updated_at
      ],
      opts
    )
  end
end
