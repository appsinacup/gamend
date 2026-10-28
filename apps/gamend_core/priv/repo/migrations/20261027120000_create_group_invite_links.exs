defmodule Gamend.Repo.Migrations.CreateGroupInviteLinks do
  @moduledoc """
  `group_invite_links` (`Gamend.Groups.InviteLinks`): a group's link that
  anyone signed in may open to join it as a member.

  One per group: making a new one replaces it, which is how an admin kills a
  link that went too far. The token is kept as it is, not hashed, so the
  admins can copy the link again later; it opens one group's membership and
  nothing else.
  """

  use Ecto.Migration

  def change do
    create table(:group_invite_links) do
      add :group_id, references(:groups, on_delete: :delete_all), null: false
      add :created_by_id, references(:users, on_delete: :nilify_all)
      add :token, :string, null: false
      add :expires_at, :utc_datetime, null: false
      add :uses, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:group_invite_links, [:group_id])
    create unique_index(:group_invite_links, [:token])
  end
end
