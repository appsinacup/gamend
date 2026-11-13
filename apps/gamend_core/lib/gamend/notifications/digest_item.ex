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
    # How many sweeps queued this notice's digest (`Gamend.Notifications.Digest`).
    field :sweeps, :integer, default: 0

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @type t :: %__MODULE__{}
end
