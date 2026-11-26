defmodule Gamend.Sent.SentMessage do
  @moduledoc """
  One email or push that went out (`sent_messages`), written by `Gamend.Sent`.

    * `channel`: `email` or `push` (`Gamend.Notifications.NotificationChannel`);
    * `kind`: what it was (`Gamend.Sent.SentKind`);
    * `group_key`: the notification group it went out in, if any;
    * `batch_id`: the announcement it was part of, so one send to everyone
      reads as one line;
    * `address`: the email address, or the device (`ios · apns`);
    * `subject`: the email's subject or the push's title;
    * `body`: what it said, with sign-in links, codes and unsubscribe links
      hidden. An email's is its `Gamend.Mail.Message`, so the admin sees it in
      the email's look; a push's is its title, body, picture and data;
    * `status` (`Gamend.Sent.SentStatus`) and `reason` when it failed.
  """

  use Gamend.Schema
  import Ecto.Changeset

  alias Gamend.Sent.SentKind
  alias Gamend.Sent.SentStatus

  require Gamend.Notifications.NotificationChannel, as: NotificationChannel

  @type t :: %__MODULE__{}

  schema "sent_messages" do
    field :channel, :string
    field :kind, :string
    field :group_key, :string
    field :batch_id, Ecto.UUID
    belongs_to :user, Gamend.Accounts.User
    field :address, :string
    field :subject, :string
    field :body, :map, default: %{}
    field :status, :string
    field :reason, :string

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @required ~w(channel kind status)a
  @optional ~w(group_key batch_id user_id address subject body reason)a

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(sent, attrs) do
    sent
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_inclusion(:channel, [NotificationChannel.email(), NotificationChannel.push()])
    |> validate_inclusion(:kind, SentKind.all())
    |> validate_inclusion(:status, SentStatus.all())
  end
end
