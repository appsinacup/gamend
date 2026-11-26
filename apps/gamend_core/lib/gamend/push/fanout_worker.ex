defmodule Gamend.Push.FanoutWorker do
  @moduledoc """
  Expands a multi-user send into per-token `DeliveryWorker` jobs, in chunks,
  off the caller's request path. `Gamend.Push.send_to_users/3` enqueues
  this above its inline threshold so a large broadcast never holds a long
  transaction (SQLite is single-writer) and survives restarts. Identical args
  within a minute dedupe via Oban uniqueness (double-broadcast guard).
  """

  use Oban.Worker,
    queue: :push,
    max_attempts: 5,
    unique: [period: 60]

  alias Gamend.Push
  alias Gamend.Push.Message

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_ids" => user_ids, "message" => message_map} = args}) do
    Push.enqueue_deliveries(user_ids, Message.from_map(message_map), args["sent"] || %{})
  end
end
