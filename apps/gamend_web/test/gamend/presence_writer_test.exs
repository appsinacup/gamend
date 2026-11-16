defmodule Gamend.PresenceWriterTest do
  @moduledoc """
  The connect/disconnect path fixes: `is_online` coalescing, and the two
  cluster-wide/per-node counts that used to be O(all connections).
  """

  # async: false — flush_ms is application env, and PresenceWriter is a single
  # named process shared by the whole node.
  use GamendWeb.ChannelCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Gamend.Accounts
  alias Gamend.Accounts.PresenceWriter
  alias Gamend.Accounts.User
  alias Gamend.Repo
  alias GamendWeb.Auth.Guardian
  alias GamendWeb.ConnectionTracker
  alias GamendWeb.UserSocket

  import Gamend.AccountsFixtures

  defp buffered(flush_ms) do
    previous = Application.get_env(:gamend_core, PresenceWriter, [])
    Application.put_env(:gamend_core, PresenceWriter, flush_ms: flush_ms)

    # The writer is its own process, so it needs its own sandbox grant.
    if pid = Process.whereis(PresenceWriter), do: Sandbox.allow(Repo, self(), pid)

    on_exit(fn -> Application.put_env(:gamend_core, PresenceWriter, previous) end)
  end

  defp online?(%User{id: id}), do: Repo.get(User, id).is_online

  describe "is_online write-through (flush_ms: 0, the test default)" do
    test "sets and clears the flag immediately" do
      user = user_fixture()

      assert {:ok, _} = Accounts.set_user_online(user.id)
      assert online?(user)

      assert {:ok, _} = Accounts.set_user_offline(user.id)
      refute online?(user)
    end

    test "a second call for an already-online user is a no-op" do
      user = user_fixture()

      assert {:ok, _} = Accounts.set_user_online(user.id)
      assert {:ok, %User{is_online: true}} = Accounts.set_user_online(user.id)
      assert online?(user)
    end

    test "an unknown user id errors rather than writing" do
      assert {:error, :not_found} = Accounts.set_user_online(Ecto.UUID.generate())
    end
  end

  describe "is_online coalescing (flush_ms > 0)" do
    setup do
      buffered(60_000)
      :ok
    end

    test "many distinct users become one flush" do
      users = for _ <- 1..5, do: user_fixture()

      for u <- users, do: assert({:ok, _} = Accounts.set_user_online(u.id))

      # Nothing durable yet — that is the point.
      for u <- users, do: refute(online?(u))

      assert :ok = PresenceWriter.flush()
      for u <- users, do: assert(online?(u))
    end

    test "the caller still gets the struct it would have got" do
      user = user_fixture()
      assert {:ok, %User{is_online: true}} = Accounts.set_user_online(user.id)
    end

    test "a disconnect inside the window wins over the connect it follows" do
      user = user_fixture()

      assert {:ok, _} = Accounts.set_user_online(user.id)
      # Reads the pending state, not the stale row, so this actually queues.
      assert {:ok, %User{is_online: false}} = Accounts.set_user_offline(user.id)

      assert :ok = PresenceWriter.flush()
      refute online?(user)
    end

    test "a user already in the target state is never queued" do
      user = user_fixture()
      assert {:ok, _} = Accounts.set_user_online(user.id)
      assert :ok = PresenceWriter.flush()
      assert online?(user)

      # No transition left to make; flushing again must not undo anything.
      assert {:ok, %User{is_online: true}} = Accounts.set_user_online(user.id)
      assert :ok = PresenceWriter.flush()
      assert online?(user)
    end
  end

  describe "Presence.last_socket?/1" do
    test "is true for a lone tracked socket and false while a second is held" do
      user = user_fixture()
      topic = Gamend.Presence.users_topic(user.id)

      {:ok, _} = Gamend.Presence.track(self(), topic, user.id, %{})
      assert Gamend.Presence.last_socket?(user.id)

      task =
        Task.async(fn ->
          {:ok, _} = Gamend.Presence.track(self(), topic, user.id, %{})
          # Report from inside the second socket's process, while both are held.
          answer = Gamend.Presence.last_socket?(user.id)
          Gamend.Presence.untrack(self(), topic, user.id)
          answer
        end)

      refute Task.await(task)
    end

    test "is true for a user with no tracked socket at all" do
      assert Gamend.Presence.last_socket?(Ecto.UUID.generate())
    end

    test "reads one user without copying every presence on the shard" do
      parent = self()

      for _ <- 1..500 do
        spawn_link(fn ->
          id = Ecto.UUID.generate()
          {:ok, _} = Gamend.Presence.track(self(), Gamend.Presence.users_topic(id), id, %{})
          send(parent, :tracked)
          Process.sleep(:infinity)
        end)
      end

      for _ <- 1..500, do: assert_receive(:tracked, 5_000)

      # A fresh process, so what it holds after the call is what the call cost:
      # through the shard's reply this was ~1 MB at 2,000 presences, so about
      # 250 KB at these 500, still over twice the bound.
      user_id = Ecto.UUID.generate()

      task =
        Task.async(fn ->
          {:memory, before} = Process.info(self(), :memory)
          true = Gamend.Presence.last_socket?(user_id)
          {:memory, after_call} = Process.info(self(), :memory)
          after_call - before
        end)

      assert Task.await(task) < 100_000
    end

    test "buckets users across topics rather than one global topic" do
      topics =
        for _ <- 1..200, do: Gamend.Presence.users_topic(Ecto.UUID.generate())

      # The point of the change: not everyone lands on one tracker shard.
      assert topics |> Enum.uniq() |> length() > 1
      assert Enum.all?(topics, &String.starts_with?(&1, "users:"))
    end
  end

  describe "per-user socket registry" do
    test "counts only this user's sockets" do
      user = user_fixture()
      other = user_fixture()
      {:ok, token, _} = Guardian.encode_and_sign(user)
      {:ok, other_token, _} = Guardian.encode_and_sign(other)

      assert ConnectionTracker.count_ws_sockets(user.id) == 0

      assert {:ok, _} = connect(UserSocket, %{"token" => token})
      assert {:ok, _} = connect(UserSocket, %{"token" => token})
      assert {:ok, _} = connect(UserSocket, %{"token" => other_token})

      assert ConnectionTracker.count_ws_sockets(user.id) == 2
      assert ConnectionTracker.count_ws_sockets(other.id) == 1
    end
  end
end
