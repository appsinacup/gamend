defmodule Gamend.Chat.Message do
  @moduledoc """
  Ecto schema for the `chat_messages` table.

  Represents a single chat message in a lobby, group, or friend conversation.

  ## Fields

    * `content` — message text
    * `metadata` — arbitrary JSON metadata (e.g. message type, attachments)
    * `sender_id` — user who sent the message
    * `chat_type` — "lobby", "group", or "friend"
    * `chat_ref_id` — reference ID (lobby_id, group_id, or the other user's id for DMs)
  """

  use Gamend.Schema
  import Ecto.Changeset

  alias Gamend.Accounts.User

  @type t :: %__MODULE__{}

  @chat_types ["lobby", "group", "friend", "party"]

  @derive {Jason.Encoder,
           only: [
             :id,
             :content,
             :metadata,
             :sender_id,
             :chat_type,
             :chat_ref_id,
             :inserted_at,
             :updated_at
           ]}

  schema "chat_messages" do
    field :content, :string
    field :metadata, :map, default: %{}
    field :chat_type, :string
    field :chat_ref_id, Ecto.UUID

    belongs_to :sender, User

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(content chat_type chat_ref_id)a
  @optional_fields ~w(metadata)a

  @doc "Changeset for creating/updating a chat message."
  def changeset(message, attrs) do
    message
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:content, min: 1, max: Gamend.Limits.get(:max_chat_content))
    |> validate_inclusion(:chat_type, @chat_types)
    |> Gamend.Limits.validate_metadata_size(:metadata)
  end

  @doc "Changeset for editing an existing message (content and metadata only)."
  def update_changeset(message, attrs) do
    message
    |> cast(attrs, [:content, :metadata])
    |> validate_required([:content])
    |> validate_length(:content, min: 1, max: Gamend.Limits.get(:max_chat_content))
    |> Gamend.Limits.validate_metadata_size(:metadata)
  end
end
