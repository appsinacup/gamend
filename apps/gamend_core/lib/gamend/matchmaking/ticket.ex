defmodule Gamend.Matchmaking.Ticket do
  @moduledoc """
  Ecto schema for a matchmaking ticket.

  A ticket represents one matchmaking request from a user. Tickets with
  the same `match_params` are grouped and matched together.

  A ticket queued on behalf of a party carries that party's `party_id`. Tickets
  sharing a `party_id` form an indivisible unit: the matcher seats them in the
  same lobby or leaves them all queued.

  A ticket queued by a lobby's host carries that lobby's `lobby_id`
  (backfill): a match seats the other players there instead of in a new
  lobby. `size` and `capacity` are what the sweep read for it, the lobby's
  members and seats (1 and nil for any other ticket).

  `accept_timeout_ms` set, a formed match asks everyone to accept first
  (a ready check of kind `accept`, `Gamend.ReadyChecks`).
  """

  use Gamend.Schema

  @type t :: %__MODULE__{}

  import Ecto.Changeset

  alias Gamend.Accounts.User
  alias Gamend.Matchmaking.Constants

  @statuses [
    Constants.status_queued(),
    Constants.status_matched(),
    Constants.status_cancelled()
  ]

  schema "matchmaking_tickets" do
    field :status, :string, default: Constants.status_queued()
    field :match_params, :map, default: %{}
    field :min_players, :integer
    field :max_players, :integer
    field :timeout_ms, :integer
    field :queued_at, :utc_datetime_usec
    field :matched_at, :utc_datetime_usec
    field :match_id, :binary_id
    field :accept_timeout_ms, :integer
    field :size, :integer, virtual: true, default: 1
    field :capacity, :integer, virtual: true

    belongs_to :user, User
    belongs_to :party, Gamend.Parties.Party
    belongs_to :lobby, Gamend.Lobbies.Lobby

    timestamps(type: :utc_datetime_usec)
  end

  @required [
    :user_id,
    :status,
    :match_params,
    :min_players,
    :max_players,
    :timeout_ms,
    :queued_at
  ]

  @doc false
  def changeset(ticket, attrs) do
    ticket
    |> cast(attrs, [
      :user_id,
      :party_id,
      :status,
      :match_params,
      :min_players,
      :max_players,
      :timeout_ms,
      :queued_at,
      :matched_at,
      :match_id,
      :lobby_id,
      :accept_timeout_ms
    ])
    |> validate_required(@required)
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:min_players, greater_than: 0)
    |> validate_number(:max_players,
      greater_than: 0,
      less_than_or_equal_to: Gamend.Limits.get(:max_matchmaking_players)
    )
    |> validate_number(:timeout_ms, greater_than: 0)
    |> validate_number(:accept_timeout_ms, greater_than: 0)
    |> validate_max_gte_min()
    |> Gamend.Limits.validate_metadata_size(:match_params, :max_matchmaking_params_size)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:party_id)
    |> foreign_key_constraint(:lobby_id)
    # Backs `Matchmaking.ensure_none_queued/1`, whose check-then-insert has the
    # `before_matchmaking_join` hook in the middle of it.
    |> unique_constraint(:user_id,
      name: :matchmaking_tickets_one_queued_per_user,
      message: "already queued"
    )
  end

  defp validate_max_gte_min(changeset) do
    min = get_field(changeset, :min_players)
    max = get_field(changeset, :max_players)

    if is_integer(min) and is_integer(max) and max >= min do
      changeset
    else
      add_error(changeset, :max_players, "must be greater than or equal to min_players")
    end
  end
end
