defmodule GameServer.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's data layer.

  You may define functions here to be used as helpers in
  your tests.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use GameServer.DataCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL

  @drain_timeout 5_000

  using do
    quote do
      alias Ecto.Adapters.SQL
      alias GameServer.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import GameServer.DataCase
    end
  end

  setup tags do
    GameServer.DataCase.setup_sandbox(tags)
    :ok
  end

  @doc """
  Sets up the sandbox based on the test tags.
  """
  def setup_sandbox(tags) do
    pid = SQL.Sandbox.start_owner!(GameServer.Repo, shared: not tags[:async])

    on_exit(fn ->
      drain_async_tasks(System.monotonic_time(:millisecond) + @drain_timeout)
      SQL.Sandbox.stop_owner(pid)
    end)
  end

  # `GameServer.Async` side effects run as supervised tasks that outlive the
  # caller, so a test can finish while one is still mid-query — cache warming
  # via Nebulex and quest progress are the usual culprits. Stopping the owner
  # first tears the connection down under them, which disconnects the pooled
  # connection and fails the query. Draining is iterative because a running
  # task can enqueue further async work.
  defp drain_async_tasks(deadline_at) do
    if System.monotonic_time(:millisecond) < deadline_at do
      case running_tasks() do
        pending when map_size(pending) == 0 -> :ok
        pending -> if await_down(pending, deadline_at), do: drain_async_tasks(deadline_at)
      end
    end
  end

  defp running_tasks do
    case Process.whereis(GameServer.TaskSupervisor) do
      nil -> %{}
      sup -> Map.new(Task.Supervisor.children(sup), &{Process.monitor(&1), &1})
    end
  end

  # Returns true when everything went down before the deadline_at.
  defp await_down(pending, _deadline) when map_size(pending) == 0, do: true

  defp await_down(pending, deadline_at) do
    receive do
      {:DOWN, ref, :process, _pid, _reason} when is_map_key(pending, ref) ->
        await_down(Map.delete(pending, ref), deadline_at)
    after
      max(deadline_at - System.monotonic_time(:millisecond), 0) ->
        Enum.each(pending, fn {ref, _pid} -> Process.demonitor(ref, [:flush]) end)
        false
    end
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(changeset).password
      assert %{password: ["password is too short"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
