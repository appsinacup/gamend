defmodule Gamend.GitHub.Installation do
  @moduledoc """
  One user's access to one installation of the GitHub App.

  The row is written from `GET /user/installations`, answered with the user's
  own GitHub token: GitHub's word on what that person may see, rather than a
  number they typed into a URL. `installation_id` is GitHub's; the primary key
  is ours and never leaves the server.
  """

  use Gamend.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "github_installations" do
    field :installation_id, :integer
    field :user_id, Ecto.UUID
    field :account_login, :string
    field :account_id, :integer
    field :account_type, :string
    field :repository_selection, :string
    field :suspended_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(installation, attrs) do
    installation
    |> cast(attrs, [
      :installation_id,
      :account_login,
      :account_id,
      :account_type,
      :repository_selection,
      :suspended_at
    ])
    |> validate_required([:installation_id])
    |> validate_length(:account_login, max: 255)
    |> validate_length(:account_type, max: 32)
    |> validate_length(:repository_selection, max: 32)
    |> unique_constraint([:user_id, :installation_id],
      name: :github_installations_user_id_installation_id_index
    )
  end
end
