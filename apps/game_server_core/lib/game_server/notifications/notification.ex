defmodule GameServer.Notifications.Notification do
  @moduledoc """
  Ecto schema representing a notification sent from one user to another.

  Notifications are persisted in the database and remain until the recipient
  explicitly deletes them. Fields:

  - `sender_id` – the user who sent the notification (must be a friend)
  - `recipient_id` – the user who receives the notification
  - `title` – required short summary
  - `content` – optional longer body text
  - `metadata` – optional arbitrary key/value map
  - `icon_url` – optional icon; `nil` means clients show their default
    notification icon
  """
  use GameServer.Schema
  import Ecto.Changeset

  alias GameServer.Accounts.User
  alias GameServer.Notifications.Types

  schema "notifications" do
    belongs_to :sender, User
    belongs_to :recipient, User

    field :title, :string
    field :content, :string, default: ""
    field :metadata, :map, default: %{}
    field :icon_url, :string
    field :read, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  @typedoc "A notification record."
  @type t :: %__MODULE__{
          id: integer() | nil,
          sender_id: integer() | nil,
          recipient_id: integer() | nil,
          title: String.t() | nil,
          content: String.t() | nil,
          metadata: map(),
          icon_url: String.t() | nil,
          read: boolean(),
          inserted_at: DateTime.t() | nil
        }

  @doc false
  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [:title, :content, :metadata, :icon_url])
    |> validate_required([:title])
    |> validate_length(:icon_url, max: GameServer.Limits.get(:max_profile_url))
    |> validate_length(:title, min: 1, max: GameServer.Limits.get(:max_notification_title))
    |> validate_length(:content, max: GameServer.Limits.get(:max_notification_content))
    |> unique_constraint([:sender_id, :recipient_id, :title],
      name: :notifications_sender_id_recipient_id_title_index
    )
    |> GameServer.Limits.validate_metadata_size(:metadata)
    |> validate_notification_type()
  end

  # A notification's type is a client contract: the server never reads it, so
  # an unregistered code would be delivered and silently ignored by every
  # client. Reject it at write time instead. See GameServer.Notifications.Types.
  defp validate_notification_type(changeset) do
    case get_field(changeset, :metadata) do
      %{"type" => type} ->
        if Types.known?(type) do
          changeset
        else
          add_error(changeset, :metadata, "unknown notification type #{inspect(type)}")
        end

      _ ->
        changeset
    end
  end
end

# Hand-written rather than @derive so nil strings encode as "" (see
# GameServer.SchemaJSON — game clients choke on null).
defimpl Jason.Encoder, for: GameServer.Notifications.Notification do
  def encode(notification, opts) do
    GameServer.SchemaJSON.encode(
      notification,
      [
        :id,
        :sender_id,
        :recipient_id,
        :title,
        :content,
        :metadata,
        :icon_url,
        :read,
        :inserted_at
      ],
      opts
    )
  end
end
