defmodule Gamend.Reports.Report do
  @moduledoc """
  Ecto schema for the `reports` table: one report a player filed about the
  game — a page, a word, anything a `Gamend.Reports.Kind` describes.

  `subject` is the kind's snapshot of what was reported, taken when it was
  filed, so the queue still reads right after the thing itself is renamed or
  removed. `subject_ref` is the kind's short key for it, which the queue groups
  duplicates on. `data` holds the kind's extra fields (a suggested correction).
  """

  use Gamend.Schema
  import Ecto.Changeset

  alias Gamend.Accounts.User

  @type t :: %__MODULE__{}

  @statuses ~w(open fixed wontfix duplicate)
  @sources ~w(web api)

  @max_description 2_000
  @max_email 160
  @max_ref 255

  schema "reports" do
    field :kind, :string
    field :topic, :string
    field :subject_ref, :string
    field :subject, :map, default: %{}
    field :data, :map, default: %{}
    field :description, :string
    field :email, :string
    field :locale, :string
    field :source, :string, default: "web"
    field :client, :map, default: %{}
    field :attachments, :map, default: %{}
    field :status, :string, default: "open"
    field :resolution_note, :string
    field :resolved_at, :utc_datetime

    belongs_to :user, User
    belongs_to :resolved_by_user, User, foreign_key: :resolved_by

    timestamps(type: :utc_datetime)
  end

  @doc "The statuses a report may have. `open` is the only unresolved one."
  @spec statuses() :: [String.t()]
  def statuses, do: @statuses

  @doc "Longest description accepted, in characters."
  @spec max_description() :: pos_integer()
  def max_description, do: @max_description

  @doc false
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(report, attrs) do
    report
    |> cast(attrs, [
      :kind,
      :topic,
      :subject_ref,
      :subject,
      :data,
      :description,
      :email,
      :locale,
      :source,
      :client,
      :user_id
    ])
    |> update_change(:description, &trim/1)
    |> update_change(:email, &trim/1)
    |> validate_required([:kind, :source])
    |> validate_inclusion(:source, @sources)
    |> validate_length(:description, max: @max_description)
    |> validate_length(:subject_ref, max: @max_ref)
    |> validate_length(:email, max: @max_email)
    |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+\.[^@,;\s]+$/)
    |> validate_length(:locale, max: 16)
    |> foreign_key_constraint(:user_id)
  end

  @doc false
  @spec attachments_changeset(t(), [map()]) :: Ecto.Changeset.t()
  def attachments_changeset(report, files) do
    change(report, attachments: %{"files" => files})
  end

  @doc false
  @spec resolve_changeset(t(), map()) :: Ecto.Changeset.t()
  def resolve_changeset(report, attrs) do
    report
    |> cast(attrs, [:status, :resolution_note, :resolved_by, :resolved_at])
    |> validate_required([:status])
    |> validate_inclusion(:status, @statuses)
    |> validate_length(:resolution_note, max: @max_description)
  end

  @doc ~s(The stored attachments, each `%{"key", "type", "size"}`.)
  @spec files(t()) :: [map()]
  def files(%__MODULE__{attachments: %{"files" => files}}) when is_list(files), do: files
  def files(%__MODULE__{}), do: []

  defp trim(nil), do: nil

  defp trim(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
