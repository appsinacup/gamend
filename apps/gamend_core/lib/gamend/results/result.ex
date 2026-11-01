defmodule Gamend.Results.Result do
  @moduledoc """
  Ecto schema for `results`: one play by one player (`Gamend.Results`).

  `metadata` is what the play was (its settings), set when it starts; what
  happened is its events (`Gamend.Results.Event`). `lobby_id` is the lobby
  it ran in, kept as a plain id: the lobby is deleted long before the
  result is.
  """

  use Gamend.Schema
  import Ecto.Changeset

  alias Gamend.Accounts.User

  @type t :: %__MODULE__{}

  # KV's access words (`Gamend.Hooks.kv_access/0`), as strings.
  @visibilities ~w(public owner_only lobby_members_only owner_or_lobby_member admin_only server_only)
  @statuses ~w(open ended)
  @max_kind 64

  schema "results" do
    field :lobby_id, Ecto.UUID
    field :kind, :string
    field :visibility, :string, default: "owner_only"
    field :status, :string, default: "open"
    field :metadata, :map, default: %{}
    field :started_at, :utc_datetime_usec
    field :ended_at, :utc_datetime_usec

    belongs_to :user, User
  end

  @doc "Who may read a result: KV's access words."
  @spec visibilities() :: [String.t()]
  def visibilities, do: @visibilities

  @doc "Where a play is: `open` while it runs, `ended` once it is over."
  @spec statuses() :: [String.t()]
  def statuses, do: @statuses

  @doc false
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(result, attrs) do
    result
    |> cast(attrs, [:user_id, :lobby_id, :kind, :visibility, :metadata, :started_at])
    |> validate_required([:user_id, :kind, :visibility, :started_at])
    |> validate_length(:kind, min: 1, max: @max_kind)
    |> validate_inclusion(:visibility, @visibilities)
    |> Gamend.Limits.validate_metadata_size(:metadata)
    |> foreign_key_constraint(:user_id)
  end
end

# By hand: `lobby_id` is a UUID, which `Gamend.SchemaJSON` leaves `null`, and
# the null policy wants `""` for an id that is not there.
defimpl Jason.Encoder, for: Gamend.Results.Result do
  def encode(result, opts) do
    Jason.Encode.map(
      %{
        id: result.id,
        user_id: result.user_id,
        lobby_id: result.lobby_id || "",
        kind: result.kind,
        visibility: result.visibility,
        status: result.status,
        metadata: result.metadata || %{},
        started_at: result.started_at,
        ended_at: result.ended_at
      },
      opts
    )
  end
end
