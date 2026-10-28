defmodule Gamend.Groups.GroupInviteLink do
  @moduledoc """
  Ecto schema for the `group_invite_links` table: a group's invite link
  (`Gamend.Groups.InviteLinks`).

  - `token` – the link's secret part, random and URL-safe
  - `expires_at` – when the link stops working
  - `uses` – how many people joined through it
  - `created_by` – the admin who made it; the link works while they are one
  """
  use Gamend.Schema
  import Ecto.Changeset

  alias Gamend.Accounts.User
  alias Gamend.Groups.Group

  @type t :: %__MODULE__{}

  schema "group_invite_links" do
    belongs_to :group, Group
    belongs_to :created_by, User

    field :token, :string, redact: true
    field :expires_at, :utc_datetime
    field :uses, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(link, attrs) do
    link
    |> cast(attrs, [:group_id, :created_by_id, :token, :expires_at])
    |> validate_required([:group_id, :token, :expires_at])
    |> unique_constraint(:group_id)
    |> unique_constraint(:token)
  end
end
