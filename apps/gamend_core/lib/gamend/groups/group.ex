defmodule Gamend.Groups.Group do
  @moduledoc """
  Ecto schema for the `groups` table.

  A group is a persistent community that users can join. Unlike lobbies (which
  are ephemeral game sessions), groups are long-lived and support admin roles,
  join-request workflows, and invitation flows.

  ## Fields

  - `title` – human-readable display title, unique unless the host turns
    `unique_titles` off (`Gamend.Groups`)
  - `slug` – its name in a URL, unique per creator: `<owner>/<slug>`
    (`Gamend.Groups.full_slug/1`), made from the title when none is given
  - `description` – optional longer description
  - `icon_url` – optional icon; `nil` means clients show their default group icon
  - `icon` – virtual: one of the host's icons by name (`Gamend.Icons`),
    which sets `icon_url` to its `/icons/<name>.svg`
  - `type` – visibility: `"public"`, `"private"`, or `"hidden"`
  - `max_members` – maximum number of members (default 100, or the host's
    fixed `max_members`)
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
    field :slug, :string
    field :description, :string, default: ""
    field :icon_url, :string
    field :icon, :string, virtual: true
    field :type, :string, default: "public"
    field :max_members, :integer, default: 100
    field :metadata, :map, default: %{}
    field :slowdown, :integer, default: 0

    belongs_to :creator, User
    has_many :members, GroupMember

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(title)a
  @optional_fields ~w(slug description icon_url icon type max_members metadata slowdown)a

  @max_slug 80

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(group, attrs) do
    group
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:title, min: 1, max: Gamend.Limits.get(:max_group_title))
    |> update_change(:slug, &normalize_slug/1)
    |> put_default_slug()
    |> validate_required([:slug])
    |> Gamend.Slug.validate(:slug, max: @max_slug, index: :groups_creator_id_slug_index)
    |> validate_length(:description, max: Gamend.Limits.get(:max_group_description))
    |> put_icon()
    |> validate_length(:icon_url, max: Gamend.Limits.get(:max_profile_url))
    |> put_default_type()
    |> validate_inclusion(:type, Gamend.Groups.types())
    |> validate_number(:max_members,
      greater_than: 0,
      less_than_or_equal_to: Gamend.Limits.get(:max_group_members)
    )
    |> validate_number(:slowdown, greater_than_or_equal_to: 0, less_than_or_equal_to: 3600)
    |> validate_unique_title()
    |> Gamend.Limits.validate_metadata_size(:metadata)
  end

  defp normalize_slug(slug) when is_binary(slug), do: slug |> String.trim() |> String.downcase()
  defp normalize_slug(slug), do: slug

  # A new group given no slug gets its title's (`Gamend.Groups.create_group/2`
  # picks a free one first; this is for a group inserted another way).
  defp put_default_slug(%{data: %{__meta__: %{state: :built}}} = changeset) do
    case get_field(changeset, :slug) do
      blank when blank in [nil, ""] ->
        put_change(changeset, :slug, Gamend.Slug.slugify(get_field(changeset, :title), "group"))

      _slug ->
        changeset
    end
  end

  defp put_default_slug(changeset), do: changeset

  # An icon by name is the group's `icon_url`. Its update path takes no
  # `icon_url` (`Gamend.Groups.update_group/3`), but a name from the host's
  # list points at nothing but the site's own icons.
  defp put_icon(changeset) do
    case get_change(changeset, :icon) do
      nil ->
        changeset

      name ->
        if name in Gamend.Icons.choices(),
          do: put_change(changeset, :icon_url, Gamend.Icons.path(name)),
          else: add_error(changeset, :icon, "is invalid")
    end
  end

  # No unique index holds the title (a host may allow the same one twice),
  # so with `unique_titles` on it is checked here.
  defp validate_unique_title(changeset) do
    if Gamend.Groups.unique_titles?(),
      do: unsafe_validate_unique(changeset, :title, Gamend.Repo),
      else: changeset
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
        :slug,
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
