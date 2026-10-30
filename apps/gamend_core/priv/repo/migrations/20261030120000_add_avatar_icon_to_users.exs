defmodule Gamend.Repo.Migrations.AddAvatarIconToUsers do
  @moduledoc """
  `users.avatar_icon`: an icon the user picked for their avatar in place of a
  picture, by name (`Gamend.Icons`). Nil for every account until it picks one.
  """

  use Ecto.Migration

  def change do
    alter table(:users) do
      add :avatar_icon, :string
    end
  end
end
