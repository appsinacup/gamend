defmodule GameServer.Quests.Objective do
  @moduledoc """
  One objective inside a quest definition: reach `target` occurrences of
  `event` (as reported through `GameServer.Quests.report_event/4`).

  `params` optionally narrows which events count — every key present must
  match the reported event's meta (e.g. `%{"map" => "desert"}`).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @derive {Jason.Encoder, only: [:event, :target, :params]}

  @primary_key false
  embedded_schema do
    field :event, :string
    field :target, :integer, default: 1
    field :params, :map, default: %{}
  end

  @doc false
  def changeset(objective, attrs) do
    objective
    |> cast(attrs, [:event, :target, :params])
    |> validate_required([:event])
    |> validate_length(:event, min: 1, max: 128)
    |> validate_number(:target, greater_than: 0)
  end
end
