defmodule Gamend.Jobs.HookWorkerTest do
  # A hook run as a job (`Gamend.Jobs.HookWorker`): a hook no module exports,
  # or a name that is no atom at all, is discarded rather than retried for
  # ever.
  use Gamend.DataCase, async: false

  alias Gamend.Jobs.HookWorker

  defp perform(args), do: HookWorker.perform(%Oban.Job{args: args})

  test "a hook no module exports is discarded as not found" do
    # `flush` is an atom the VM knows, and no hooks module exports flush/1.
    assert {:discard, {:not_found, {_module, :flush, 1}}} = perform(%{"hook" => "flush"})
  end

  test "a name that is no atom at all is discarded as unknown" do
    assert perform(%{"hook" => "hook_#{System.unique_integer([:positive])}_never_seen"}) ==
             {:discard, :unknown_hook}
  end
end
