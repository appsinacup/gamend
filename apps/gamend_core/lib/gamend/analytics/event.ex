defmodule Gamend.Analytics.Event do
  @moduledoc """
  One thing a player did, with who and when: `name` (`"web.game.finished"`),
  `dims` (its fields — language, game, score — as a map with string keys),
  `user_id` (nil for a visitor, nulled when the account is deleted) and
  `inserted_at`, the moment it happened. Written by `Gamend.Analytics.track/3`
  through `Gamend.Analytics.Buffer`, in batches, never one row at a time.

  The daily counters (`Gamend.Analytics.DailyCount`) hold the same events
  summed per day and per dimension, forever; these rows are what answers the
  questions a sum cannot (distinct people, order, combinations) and are
  pruned after `GAMEND_RETENTION_ANALYTICS_EVENTS_DAYS`.
  """

  use Gamend.Schema

  @type t :: %__MODULE__{}

  schema "analytics_events" do
    field :name, :string
    field :dims, :map, default: %{}
    belongs_to :user, Gamend.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
