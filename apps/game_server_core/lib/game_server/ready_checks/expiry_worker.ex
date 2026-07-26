defmodule GameServer.ReadyChecks.ExpiryWorker do
  @moduledoc false
  # Fails a ready check when its deadline_at arrives.
  #
  # One durable job per check rather than a bespoke GenServer tick: it survives
  # a node restart (a `Process.send_after` would not) and fires within Oban's
  # poll interval of the deadline_at. `ReadyChecks.expire/1` is idempotent, so a
  # check that already resolved makes this a no-op, and the matchmaking sweep's
  # backstop can safely run the same expiry for a job that was lost.

  use Oban.Worker, queue: :default, max_attempts: 3

  alias GameServer.ReadyChecks

  @doc "Schedules expiry of `check_id` in `seconds`."
  @spec schedule(Ecto.UUID.t(), non_neg_integer()) :: :ok
  def schedule(check_id, seconds) when is_binary(check_id) and is_integer(seconds) do
    _ = GameServer.Jobs.enqueue(__MODULE__, %{"check_id" => check_id}, schedule_in: seconds)
    :ok
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"check_id" => check_id}}) do
    case ReadyChecks.get_check(check_id) do
      nil -> :ok
      check -> with :noop <- ReadyChecks.expire(check), do: :ok
    end
  end
end
