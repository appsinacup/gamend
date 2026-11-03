defmodule Gamend.Notifications.DigestItem do
  @moduledoc "One notice waiting for a digest email (`Gamend.Notifications.Digest`)."

  use Gamend.Schema

  alias Gamend.Accounts.User

  schema "notification_digest_items" do
    belongs_to :user, User

    field :group_key, :string
    field :subject, :string
    field :text, :string, default: ""
    field :url, :string

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @type t :: %__MODULE__{}
end
