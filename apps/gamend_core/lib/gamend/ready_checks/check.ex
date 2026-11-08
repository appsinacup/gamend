defmodule Gamend.ReadyChecks.Check do
  @moduledoc """
  Ecto schema for one ready check — a *moment* at which a set of players must
  each answer before something proceeds.

  Two kinds, differing only in what a "no" means and whether an answer can be
  taken back (see `Gamend.ReadyChecks`):

    * `"accept"` — one-shot and irrevocable; the first decline fails the whole
      check; the deadline_at is mandatory.
    * `"ready"` — a toggle; a decline just leaves the check pending.

  The subject is whichever of `lobby_id`/`party_id` is set — a lobby's
  pre-match ready-up or a party's standing ready board. Both nil is a
  matchmaking check: at that point the group exists only as its tickets, and
  no lobby has been created.
  """

  use Gamend.Schema

  import Ecto.Changeset

  alias Gamend.Accounts.User
  alias Gamend.Lobbies.Lobby
  alias Gamend.Parties.Party
  alias Gamend.ReadyChecks.Participant

  require Gamend.ReadyChecks.CheckKind, as: CheckKind
  require Gamend.ReadyChecks.CheckStatus, as: CheckStatus

  @type t :: %__MODULE__{}

  @kinds ~w(accept ready)
  @statuses ~w(pending passed failed cancelled)
  @reasons ~w(declined timeout cancelled reset)

  schema "ready_checks" do
    field :kind, :string
    field :status, :string, default: CheckStatus.pending()
    field :deadline_at, :utc_datetime
    field :reason, :string
    field :resolved_at, :utc_datetime
    field :metadata, :map, default: %{}
    # Where an accepted match will sit (`Gamend.MatchSeating.dump/1`). Left out
    # of the JSON below: `metadata` is echoed to clients, and this can name a
    # hidden lobby.
    field :seating, :map

    belongs_to :lobby, Lobby
    belongs_to :party, Party
    belongs_to :opened_by_user, User, foreign_key: :opened_by

    has_many :participants, Participant, foreign_key: :ready_check_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(check, attrs) do
    check
    |> cast(attrs, [
      :kind,
      :status,
      :lobby_id,
      :party_id,
      :deadline_at,
      :opened_by,
      :reason,
      :resolved_at,
      :metadata,
      :seating
    ])
    |> validate_required([:kind, :status])
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:reason, @reasons)
    |> validate_accept_deadline()
    |> validate_one_subject()
    |> Gamend.Limits.validate_metadata_size(:metadata)
    |> foreign_key_constraint(:lobby_id)
    |> foreign_key_constraint(:party_id)
    # Both names on purpose: Postgres reports the partial index by its real
    # name, while ecto_sqlite3 reports the default `<table>_<field>_index`.
    # Without the second clause a concurrent open raises instead of returning a
    # changeset on SQLite.
    |> unique_constraint(:lobby_id, name: :ready_checks_pending_lobby_index)
    |> unique_constraint(:lobby_id)
    |> unique_constraint(:party_id, name: :ready_checks_pending_party_index)
    |> unique_constraint(:party_id)
  end

  # A check belongs to exactly one subject; both set would make the participant
  # set ambiguous the moment the two rosters diverge.
  defp validate_one_subject(changeset) do
    if get_field(changeset, :lobby_id) && get_field(changeset, :party_id) do
      add_error(changeset, :party_id, "cannot be set together with lobby_id")
    else
      changeset
    end
  end

  # An accept check with no deadline_at would strand a whole match on one absent
  # player, so the deadline_at is part of what "accept" means.
  defp validate_accept_deadline(changeset) do
    if get_field(changeset, :kind) == CheckKind.accept() and
         is_nil(get_field(changeset, :deadline_at)) do
      add_error(changeset, :deadline_at, "is required for accept checks")
    else
      changeset
    end
  end

  @doc "The kinds a check may have."
  @spec kinds() :: [String.t()]
  def kinds, do: @kinds

  @doc "The statuses a check may have."
  @spec statuses() :: [String.t()]
  def statuses, do: @statuses
end

# Hand-written rather than @derive so nil strings encode as "" (see
# Gamend.SchemaJSON — game clients choke on null).
defimpl Jason.Encoder, for: Gamend.ReadyChecks.Check do
  def encode(check, opts) do
    Gamend.SchemaJSON.encode(
      check,
      [
        :id,
        :kind,
        :status,
        :lobby_id,
        :party_id,
        :deadline_at,
        :opened_by,
        :reason,
        :resolved_at,
        :metadata,
        :inserted_at,
        :updated_at
      ],
      opts
    )
  end
end
