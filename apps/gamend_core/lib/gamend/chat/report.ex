defmodule Gamend.Chat.Report do
  @moduledoc """
  Ecto schema for the `chat_reports` table — a player- or filter-filed report
  about a chat message.

  `reporter_id` is `nil` when the word filter filed the report itself (a `flag`
  severity hit). `reported_user_id` and `content_snapshot` are denormalized so
  the queue still makes sense after the message is deleted.
  """

  use Gamend.Schema
  import Ecto.Changeset

  alias Gamend.Accounts.User
  alias Gamend.Chat.Message

  require Gamend.Chat.ChatReportStatus, as: ChatReportStatus

  @type t :: %__MODULE__{}

  @statuses ~w(open reviewing actioned dismissed)

  schema "chat_reports" do
    field :content_snapshot, :string
    field :reason, :string
    field :status, :string, default: ChatReportStatus.open()
    field :resolution_note, :string
    field :resolved_at, :utc_datetime

    belongs_to :reporter, User
    belongs_to :reported_user, User
    belongs_to :resolved_by_user, User, foreign_key: :resolved_by
    belongs_to :message, Message

    timestamps(type: :utc_datetime)
  end

  @doc "The statuses a report may have."
  @spec statuses() :: [String.t()]
  def statuses, do: @statuses

  @doc false
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(report, attrs) do
    report
    |> cast(attrs, [
      :reporter_id,
      :message_id,
      :reported_user_id,
      :content_snapshot,
      :reason,
      :status
    ])
    |> validate_required([:reported_user_id, :status])
    |> validate_inclusion(:status, @statuses)
    |> validate_length(:reason, max: Gamend.Limits.get(:max_report_reason))
    |> foreign_key_constraint(:reported_user_id)
    # Both names on purpose: Postgres reports the partial index by its real
    # name, while ecto_sqlite3 reports the default `<table>_<field>_index`.
    |> unique_constraint([:reporter_id, :message_id],
      name: :chat_reports_reporter_message_index
    )
    |> unique_constraint([:reporter_id, :message_id])
  end

  @doc "Changeset for a moderator resolving a report."
  @spec resolve_changeset(t(), map()) :: Ecto.Changeset.t()
  def resolve_changeset(report, attrs) do
    report
    |> cast(attrs, [:status, :resolution_note, :resolved_by, :resolved_at])
    |> validate_required([:status])
    |> validate_inclusion(:status, @statuses)
    |> validate_length(:resolution_note, max: Gamend.Limits.get(:max_report_reason))
  end
end

# Hand-written rather than @derive so nil strings encode as "" (see
# Gamend.SchemaJSON — game clients choke on null).
defimpl Jason.Encoder, for: Gamend.Chat.Report do
  def encode(report, opts) do
    Gamend.SchemaJSON.encode(
      report,
      [
        :id,
        :reporter_id,
        :message_id,
        :reported_user_id,
        :content_snapshot,
        :reason,
        :status,
        :resolved_by,
        :resolution_note,
        :resolved_at,
        :inserted_at,
        :updated_at
      ],
      opts
    )
  end
end
