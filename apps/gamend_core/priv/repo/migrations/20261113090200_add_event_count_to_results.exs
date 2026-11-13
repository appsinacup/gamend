defmodule Gamend.Repo.Migrations.AddEventCountToResults do
  @moduledoc """
  `results.event_count`: the events a play has recorded, which
  `max_result_events` is checked against with one conditional update
  (`Gamend.Results.record/4`). Counting them under the result's lock made each
  event read every one before it.

  Filled for open plays only: an ended play takes no more events, and nothing
  else reads the column.
  """

  use Ecto.Migration

  def up do
    alter table(:results) do
      add :event_count, :integer, null: false, default: 0
    end

    execute("""
    UPDATE results
    SET event_count = (
      SELECT COUNT(*) FROM result_events WHERE result_events.result_id = results.id
    )
    WHERE status = 'open'
    """)
  end

  def down do
    alter table(:results) do
      remove :event_count
    end
  end
end
