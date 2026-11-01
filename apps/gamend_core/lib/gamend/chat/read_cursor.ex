defmodule Gamend.Chat.ReadCursor do
  @moduledoc """
  Ecto schema for the `chat_read_cursors` table.

  Tracks the last message a user has read in a given chat conversation.
  The unique constraint on `[user_id, chat_type, chat_ref_id]` ensures
  one cursor per user per conversation.
  """

  use Gamend.Schema
  import Ecto.Changeset

  alias Gamend.Accounts.User
  alias Gamend.Chat.Message

  @type t :: %__MODULE__{}

  @chat_types ["lobby", "group", "friend", "party"]

  @derive {Jason.Encoder,
           only: [
             :id,
             :user_id,
             :chat_type,
             :chat_ref_id,
             :last_read_message_id,
             :updated_at
           ]}

  schema "chat_read_cursors" do
    field :chat_type, :string
    field :chat_ref_id, Ecto.UUID

    belongs_to :user, User
    belongs_to :last_read_message, Message

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(chat_type chat_ref_id)a
  @optional_fields ~w(last_read_message_id)a

  @doc "Changeset for creating/updating a read cursor."
  def changeset(cursor, attrs) do
    cursor
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:chat_type, @chat_types)
    |> unique_constraint([:user_id, :chat_type, :chat_ref_id],
      name: :chat_read_cursors_user_type_ref
    )
  end
end
