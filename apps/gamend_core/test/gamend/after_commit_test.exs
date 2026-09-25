defmodule Gamend.AfterCommitTest do
  use Gamend.DataCase, async: false

  import ExUnit.CaptureLog

  alias Gamend.AfterCommit
  alias Gamend.Repo

  defp mark(tag) do
    test = self()
    fn -> send(test, {:ran, tag}) end
  end

  describe "defer/1" do
    test "runs at once outside a transaction" do
      assert :ok = AfterCommit.defer(mark(:now))
      assert_received {:ran, :now}
    end

    test "waits for the transaction to commit" do
      assert {:ok, :done} =
               AfterCommit.transaction(fn ->
                 AfterCommit.defer(mark(:later))
                 refute_received {:ran, :later}
                 :done
               end)

      assert_received {:ran, :later}
    end

    test "runs queued effects in order" do
      AfterCommit.transaction(fn ->
        AfterCommit.defer(mark(1))
        AfterCommit.defer(mark(2))
      end)

      assert {:messages, [{:ran, 1}, {:ran, 2}]} = Process.info(self(), :messages)
    end

    test "a rollback drops them" do
      assert {:error, :nope} =
               AfterCommit.transaction(fn ->
                 AfterCommit.defer(mark(:dropped))
                 Repo.rollback(:nope)
               end)

      refute_received {:ran, :dropped}
      refute AfterCommit.deferring?()
    end

    test "an exception drops them and leaves no scope behind" do
      assert_raise RuntimeError, fn ->
        AfterCommit.transaction(fn ->
          AfterCommit.defer(mark(:dropped))
          raise "boom"
        end)
      end

      refute_received {:ran, :dropped}
      refute AfterCommit.deferring?()
    end

    test "a nested transaction waits for the outermost commit" do
      AfterCommit.transaction(fn ->
        {:ok, _} = AfterCommit.transaction(fn -> AfterCommit.defer(mark(:inner)) end)
        refute_received {:ran, :inner}
      end)

      assert_received {:ran, :inner}
    end

    test "inside a bare Repo.transaction there is no commit to wait for" do
      Repo.transaction(fn ->
        AfterCommit.transaction(fn -> AfterCommit.defer(mark(:bare)) end)
        assert_received {:ran, :bare}
      end)
    end

    test "Lock.serialize is a scope, and its effects run after the lock is released" do
      key = {{Gamend.Lock.Local, {"after_commit_test", "k"}}, :someone_else}

      {:ok, :done} =
        Gamend.Lock.serialize("after_commit_test", "k", fn ->
          AfterCommit.defer(fn ->
            send(self(), {:lock_free, :global.set_lock(key, [node()], 0)})
          end)

          :done
        end)

      assert_received {:lock_free, true}
      :global.del_lock(key, [node()])
    end

    test "an effect that raises is logged, and the rest still run" do
      log =
        capture_log(fn ->
          AfterCommit.transaction(fn ->
            AfterCommit.defer(fn -> raise "effect failed" end)
            AfterCommit.defer(mark(:after))
          end)
        end)

      assert log =~ "effect failed"
      assert_received {:ran, :after}
    end

    test "a cache invalidation inside a transaction is repeated after the commit" do
      key = {:after_commit_test, System.unique_integer([:positive])}
      Gamend.Cache.put(key, :before)

      AfterCommit.transaction(fn ->
        Gamend.Cache.invalidate(key)
        assert Gamend.Cache.get!(key) == nil

        # A concurrent read of the not-yet-committed row caches it back.
        Gamend.Cache.put(key, :stale)
      end)

      assert Gamend.Cache.get!(key) == nil
    end

    test "Gamend.Async.run inside a transaction starts after the commit" do
      AfterCommit.transaction(fn ->
        Gamend.Async.run(mark(:task))
        refute_receive {:ran, :task}, 50
      end)

      assert_receive {:ran, :task}
    end
  end

  describe "core" do
    # A broadcast or a hook task inside a bare `Repo.transaction/2` runs while
    # it holds the database (on SQLite, every request's database), and before
    # the write is visible. Core opens transactions through
    # `Gamend.AfterCommit` and broadcasts through `Gamend.Broadcast`, which
    # wait for the commit; these are the only files allowed the raw calls.
    @lib Path.expand("../../lib", __DIR__)
    @raw_transaction ~r/Repo\.transact(ion)?\(/
    @raw_broadcast ~r/Phoenix\.PubSub\.broadcast\(/

    defp offenders(pattern, allowed) do
      for path <- Path.wildcard(Path.join(@lib, "**/*.ex")),
          Path.relative_to(path, @lib) not in allowed,
          {line, number} <- path |> File.read!() |> String.split("\n") |> Enum.with_index(1),
          not String.starts_with?(String.trim_leading(line), "#"),
          Regex.match?(pattern, line) do
        "#{Path.relative_to(path, @lib)}:#{number}"
      end
    end

    test "opens no transaction but through Gamend.AfterCommit" do
      assert offenders(@raw_transaction, [
               "gamend/after_commit.ex",
               "gamend/lock.ex",
               "gamend/repo.ex"
             ]) == []
    end

    test "broadcasts through Gamend.Broadcast" do
      assert offenders(@raw_broadcast, ["gamend/broadcast.ex", "gamend/cache.ex"]) == []
    end
  end
end
