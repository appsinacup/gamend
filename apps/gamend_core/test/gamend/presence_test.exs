defmodule Gamend.PresenceTest do
  @moduledoc """
  The reads that skip the tracker shard's process (`Gamend.Presence`, *Reads*).
  """

  # async: false — the tracker is one named process shared by the whole node.
  use ExUnit.Case, async: false

  alias Gamend.Presence

  defp topic, do: "presence_test:#{System.unique_integer([:positive])}"

  # A process holding one presence until it is told to stop.
  defp hold(topic, key) do
    parent = self()

    pid =
      spawn_link(fn ->
        {:ok, _} = Presence.track(self(), topic, key, %{})
        send(parent, {:tracked, self()})

        receive do
          :stop -> :ok
        end
      end)

    # `track/4` is a call to the shard, which may still be removing the
    # holders of an earlier test: 100 ms is too short under a loaded suite.
    assert_receive {:tracked, ^pid}, 5_000
    pid
  end

  # The tracker removes a dead process's entries when it sees the exit.
  defp eventually(fun, tries \\ 50) do
    cond do
      fun.() -> :ok
      tries == 0 -> flunk("condition never held")
      true -> Process.sleep(20) && eventually(fun, tries - 1)
    end
  end

  describe "keys/1" do
    test "is the topic's distinct keys, sorted, and only that topic's" do
      t = topic()
      other = topic()

      for key <- ["b", "a", "b"], do: hold(t, key)
      hold(other, "c")

      assert Presence.keys(t) == ["a", "b"]
      assert Presence.keys(other) == ["c"]
      assert Presence.keys(topic()) == []
    end

    test "keeps a key while any of its processes holds it" do
      t = topic()
      first = hold(t, "a")
      second = hold(t, "a")

      send(first, :stop)
      Process.sleep(50)
      assert Presence.keys(t) == ["a"]

      send(second, :stop)
      eventually(fn -> Presence.keys(t) == [] end)
    end

    test "reads one topic without copying every presence on the shard" do
      for _ <- 1..2_000, do: hold(topic(), "player")

      t = topic()
      hold(t, "a")

      # A fresh process, so what it holds after the call is what the call cost:
      # through the shard's reply (`list/1`) this was ~1 MB at 2,000 presences.
      task =
        Task.async(fn ->
          {:memory, before} = Process.info(self(), :memory)
          ["a"] = Presence.keys(t)
          {:memory, after_call} = Process.info(self(), :memory)
          after_call - before
        end)

      assert Task.await(task) < 100_000
    end
  end
end
