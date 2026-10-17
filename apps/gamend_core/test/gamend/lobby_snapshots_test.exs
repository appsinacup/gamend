defmodule Gamend.LobbySnapshotsTest do
  # async: false — the writer is a named process shared across tests.
  use Gamend.DataCase, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Gamend.AccountsFixtures
  alias Gamend.Lobbies
  alias Gamend.LobbySnapshots
  alias Gamend.LobbySnapshots.{Blob, Snapshot, Writer}

  setup do
    previous = Application.get_env(:gamend_core, LobbySnapshots, [])

    Application.put_env(
      :gamend_core,
      LobbySnapshots,
      Keyword.merge(previous, enabled: true, user_kv_keys: [])
    )

    {:ok, writer} = Writer.start_link([])
    Sandbox.allow(Gamend.Repo, self(), writer)

    on_exit(fn ->
      Application.put_env(:gamend_core, LobbySnapshots, previous)
    end)

    host = AccountsFixtures.user_fixture()
    {:ok, lobby} = Lobbies.create_lobby(%{title: "snapshot-room", host_id: host.id})

    %{host: host, lobby: lobby}
  end

  defp capture(lobby_id, trigger, opts \\ []) do
    :ok = LobbySnapshots.capture_lobby(lobby_id, trigger, Keyword.put(opts, :sync, true))
    :ok = Writer.flush()
  end

  # Flushes the writer and lists until `count` snapshots exist for the lobby,
  # or gives up after two seconds and returns whatever is there for the
  # assertion to report.
  defp flushed_snapshots(lobby_id, count, deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + 2_000
    :ok = Writer.flush()
    snapshots = LobbySnapshots.list_snapshots(lobby_id)

    if length(snapshots) >= count or System.monotonic_time(:millisecond) > deadline do
      snapshots
    else
      Process.sleep(20)
      flushed_snapshots(lobby_id, count, deadline)
    end
  end

  describe "capture" do
    test "records snapshots in order with their trigger", %{lobby: lobby} do
      capture(lobby.id, "test:first")
      capture(lobby.id, "test:second")

      assert [first, second] = LobbySnapshots.list_snapshots(lobby.id)
      assert first.trigger == "test:first"
      assert second.trigger == "test:second"
      # UUIDv7 ids are time-ordered, which is what makes a stored counter
      # unnecessary for ordering.
      assert first.id < second.id

      assert Map.has_key?(first.section_hashes, "lobby")
      assert Map.has_key?(first.section_hashes, "members")
    end

    test "unchanged sections reuse the same blob rather than storing it twice", %{lobby: lobby} do
      capture(lobby.id, "test:first")
      capture(lobby.id, "test:second")

      [first, second] = LobbySnapshots.list_snapshots(lobby.id)

      # Nothing changed between the two captures, so every section resolves to
      # the hash already stored — this is what makes dedup subsume
      # section-skipping.
      assert first.section_hashes == second.section_hashes

      hashes = first.section_hashes |> Map.values() |> Enum.uniq()
      assert Repo.aggregate(Blob, :count) == length(hashes)
    end

    test "a changed section produces a new blob, unchanged ones do not", %{lobby: lobby} do
      capture(lobby.id, "test:before")
      before_blobs = Repo.aggregate(Blob, :count)

      {:ok, _} = Lobbies.update_lobby(Repo.get!(Lobbies.Lobby, lobby.id), %{title: "renamed"})
      capture(lobby.id, "test:after")

      [first, second] = LobbySnapshots.list_snapshots(lobby.id)

      assert first.section_hashes["lobby"] != second.section_hashes["lobby"]
      assert first.section_hashes["members"] == second.section_hashes["members"]
      assert Repo.aggregate(Blob, :count) == before_blobs + 1
    end

    test "is a no-op when disabled", %{lobby: lobby} do
      Application.put_env(:gamend_core, LobbySnapshots, enabled: false)

      capture(lobby.id, "test:disabled")

      assert Repo.aggregate(Snapshot, :count) == 0
    end

    test "flagged captures are recorded for the retention sweep to exempt", %{lobby: lobby} do
      capture(lobby.id, "hook:boom", flagged: true)

      assert [snapshot] = LobbySnapshots.list_snapshots(lobby.id)
      assert snapshot.flagged
      assert [%{flagged: true}] = LobbySnapshots.list_lobbies(flagged_only: true)
    end
  end

  describe "reads" do
    test "state_at takes the latest section at or before the snapshot", %{lobby: lobby} do
      capture(lobby.id, "test:first")
      {:ok, _} = Lobbies.update_lobby(Repo.get!(Lobbies.Lobby, lobby.id), %{title: "renamed"})
      capture(lobby.id, "test:second")

      [first, second] = LobbySnapshots.list_snapshots(lobby.id)

      at_first = LobbySnapshots.state_at(first)
      at_second = LobbySnapshots.state_at(second)

      assert at_first["lobby"]["title"] == "snapshot-room"
      assert at_second["lobby"]["title"] == "renamed"
      # members did not change, so the later snapshot resolves it from the blob
      # stored at the earlier one
      assert at_second["members"] == at_first["members"]
    end

    test "timeline groups events into the interval they fall within", %{lobby: lobby} do
      :ok = LobbySnapshots.record_event(lobby.id, "before.anything", %{})
      :ok = Writer.flush()

      capture(lobby.id, "test:first")
      :ok = LobbySnapshots.record_event(lobby.id, "race.speed", %{from: 100, to: 50})
      :ok = Writer.flush()

      capture(lobby.id, "test:second")
      :ok = LobbySnapshots.record_event(lobby.id, "race.collision", %{target: "rock"})
      :ok = Writer.flush()

      timeline = LobbySnapshots.timeline(lobby.id)

      # Events before the first snapshot have no interval to belong to.
      assert [%{kind: "before.anything"}] = timeline.prologue

      assert [first, second] = timeline.intervals
      assert first.index == 1
      assert first.snapshot.trigger == "test:first"
      assert [%{kind: "race.speed", payload: %{"from" => 100, "to" => 50}}] = first.events

      assert second.index == 2
      assert [%{kind: "race.collision"}] = second.events
    end

    test "members section stores ids and in-lobby state, never profile fields", %{
      lobby: lobby,
      host: host
    } do
      capture(lobby.id, "test:privacy")

      [snapshot] = LobbySnapshots.list_snapshots(lobby.id)
      members = snapshot |> LobbySnapshots.state_at() |> Map.fetch!("members")

      assert [member] = members
      assert member["id"] == host.id
      assert Enum.sort(Map.keys(member)) == ["id", "is_online", "metadata"]
      refute Map.has_key?(member, "email")
      refute Map.has_key?(member, "username")
    end
  end

  describe "event payloads" do
    test "terms jsonb cannot represent are coerced rather than failing the batch", %{
      lobby: lobby
    } do
      # A tuple or pid reaching the insert would fail encoding and take the
      # writer's whole batch with it, losing unrelated events too.
      :ok =
        LobbySnapshots.record_event(lobby.id, "race.weird", %{
          tuple: {:collision, 3},
          pid: self(),
          nested: %{list: [{:a, 1}], atom: :rock},
          binary: <<0xFF, 0xFE>>
        })

      :ok = Writer.flush()

      assert [event] = LobbySnapshots.list_events(lobby.id)
      assert event.payload["tuple"] == ["collision", 3]
      assert event.payload["nested"]["list"] == [["a", 1]]
      assert event.payload["nested"]["atom"] == "rock"
      assert is_binary(event.payload["pid"])
      assert is_binary(event.payload["binary"])
    end

    test "a bad payload does not take unrelated events down with it", %{lobby: lobby} do
      :ok = LobbySnapshots.record_event(lobby.id, "race.fine", %{ok: 1})
      :ok = LobbySnapshots.record_event(lobby.id, "race.weird", %{pid: self()})
      :ok = Writer.flush()

      kinds = lobby.id |> LobbySnapshots.list_events() |> Enum.map(& &1.kind) |> Enum.sort()
      assert kinds == ["race.fine", "race.weird"]
    end
  end

  describe "coverage gaps" do
    test "are recorded in the run's timeline where they happened", %{lobby: lobby} do
      capture(lobby.id, "test:first")

      :ok =
        LobbySnapshots.record_coverage_gap(lobby.id, "unserialized_write", %{
          "section" => "boat_adventure"
        })

      :ok = Writer.flush()

      timeline = LobbySnapshots.timeline(lobby.id)
      assert [interval] = timeline.intervals
      assert [gap] = interval.events
      assert gap.kind == "coverage:unserialized_write"
      assert gap.payload["section"] == "boat_adventure"
    end

    test "are listed across lobbies, newest first", %{lobby: lobby} do
      other = AccountsFixtures.user_fixture()
      {:ok, other_lobby} = Lobbies.create_lobby(%{title: "other", host_id: other.id})

      :ok = LobbySnapshots.record_coverage_gap(lobby.id, "unserialized_write")
      :ok = LobbySnapshots.record_coverage_gap(other_lobby.id, "unserialized_write")
      :ok = LobbySnapshots.record_event(lobby.id, "race.speed", %{from: 100, to: 50})
      :ok = Writer.flush()

      gaps = LobbySnapshots.list_coverage_gaps()

      # The ordinary game event is not a gap and must not dilute the list.
      assert length(gaps) == 2
      assert Enum.all?(gaps, &LobbySnapshots.coverage_gap?/1)
      assert hd(gaps).lobby_id == other_lobby.id
    end

    test "coverage_gap? distinguishes gaps from game decisions" do
      assert LobbySnapshots.coverage_gap?("coverage:unserialized_write")
      refute LobbySnapshots.coverage_gap?("race.speed")
    end
  end

  describe "writer stats" do
    test "cluster_stats reports this node when standalone" do
      stats = Writer.cluster_stats()

      assert stats.nodes == 1
      assert stats.unreachable == 0
      assert is_integer(stats.buffered)
      assert is_integer(stats.dropped)
    end
  end

  describe "diff" do
    test "reports changed fields with flattened paths, omitting unchanged sections", %{
      lobby: lobby
    } do
      capture(lobby.id, "test:before")

      {:ok, _} =
        Lobbies.update_lobby(Repo.get!(Lobbies.Lobby, lobby.id), %{
          title: "renamed",
          metadata: %{"boat" => %{"speed" => 50}}
        })

      capture(lobby.id, "test:after")

      [first, second] = LobbySnapshots.list_snapshots(lobby.id)
      diff = LobbySnapshots.diff(first, second)

      assert %{"lobby" => lobby_changes} = diff
      assert %{path: ["title"], from: "snapshot-room", to: "renamed"} in lobby_changes

      # Nested fields read as one flattened path rather than making the reader
      # walk two levels to spot the change.
      assert %{"lobby_metadata" => meta_changes} = diff
      assert %{path: ["boat", "speed"], from: nil, to: 50} in meta_changes

      # members did not change, so it is absent entirely
      refute Map.has_key?(diff, "members")
    end

    test "a value reverting between snapshots is visible as a change back", %{lobby: lobby} do
      # The bug this system exists for: a field that goes 0 -> 250 -> 0.
      set_metadata = fn value ->
        {:ok, _} =
          Lobbies.update_lobby(Repo.get!(Lobbies.Lobby, lobby.id), %{
            metadata: %{"distance" => value}
          })
      end

      set_metadata.(0)
      capture(lobby.id, "test:one")
      set_metadata.(250)
      capture(lobby.id, "test:two")
      set_metadata.(0)
      capture(lobby.id, "test:three")

      [one, two, three] = LobbySnapshots.list_snapshots(lobby.id)

      assert %{"lobby_metadata" => [%{path: ["distance"], from: 0, to: 250}]} =
               LobbySnapshots.diff(one, two)

      assert %{"lobby_metadata" => [%{path: ["distance"], from: 250, to: 0}]} =
               LobbySnapshots.diff(two, three)
    end

    test "a section emptied mid-run does not revert to its previous value", %{lobby: lobby} do
      # state_at resolves each section from its latest occurrence at or before a
      # snapshot. If a section that became empty were simply omitted, "emptied"
      # would be indistinguishable from "unchanged" and the stale value would
      # linger for the rest of the run.
      {:ok, _} =
        Lobbies.update_lobby(Repo.get!(Lobbies.Lobby, lobby.id), %{metadata: %{"a" => 1}})

      capture(lobby.id, "test:populated")

      {:ok, _} = Lobbies.update_lobby(Repo.get!(Lobbies.Lobby, lobby.id), %{metadata: %{}})
      capture(lobby.id, "test:emptied")

      [populated, emptied] = LobbySnapshots.list_snapshots(lobby.id)

      assert LobbySnapshots.state_at(populated)["lobby_metadata"] == %{"a" => 1}
      assert LobbySnapshots.state_at(emptied)["lobby_metadata"] == %{}

      assert %{"lobby_metadata" => [%{path: ["a"], from: 1, to: nil}]} =
               LobbySnapshots.diff(populated, emptied)
    end

    test "is empty between identical snapshots", %{lobby: lobby} do
      capture(lobby.id, "test:one")
      capture(lobby.id, "test:two")

      [one, two] = LobbySnapshots.list_snapshots(lobby.id)

      assert LobbySnapshots.diff(one, two) == %{}
    end
  end

  describe "lobby teardown" do
    test "captures the run's final state before the lobby is deleted", %{lobby: lobby} do
      {:ok, _} = Lobbies.delete_lobby(Repo.get!(Lobbies.Lobby, lobby.id))
      :ok = Writer.flush()

      # The lobby row is gone, but the run's record is not — this is the whole
      # reason lobby_id is not a foreign key.
      refute Repo.get(Lobbies.Lobby, lobby.id)

      assert [snapshot] = LobbySnapshots.list_snapshots(lobby.id)
      assert snapshot.trigger == "lobby:deleted"

      state = LobbySnapshots.state_at(snapshot)
      assert state["lobby"]["title"] == "snapshot-room"
      # Captured before members were detached, so the final roster survives.
      assert [_member] = state["members"]
    end

    test "captures when the last member leaving empties the lobby", %{lobby: lobby, host: host} do
      {:ok, _} = Lobbies.leave_lobby(Repo.get!(Gamend.Accounts.User, host.id))
      :ok = Writer.flush()

      refute Repo.get(Lobbies.Lobby, lobby.id)

      triggers = lobby.id |> LobbySnapshots.list_snapshots() |> Enum.map(& &1.trigger)
      assert "lobby:emptied" in triggers
    end
  end

  describe "hook capture" do
    test "captures against the caller's lobby and flags errors", %{lobby: lobby, host: host} do
      user = Repo.get!(Gamend.Accounts.User, host.id)

      :ok = LobbySnapshots.capture_hook(:finish_boat_game, user, {:ok, :done})
      :ok = LobbySnapshots.capture_hook(:broken_hook, user, {:error, :boom})
      # capture_hook gathers off the caller's process — a real task here, since
      # core tests leave `Gamend.Async` asynchronous (see config/test.exs) — so
      # wait for both captures to land rather than a fixed pause the loaded
      # suite overran.
      snapshots = flushed_snapshots(lobby.id, 2)

      assert Enum.any?(snapshots, &(&1.trigger == "hook:finish_boat_game" and not &1.flagged))
      assert Enum.any?(snapshots, &(&1.trigger == "hook:broken_hook" and &1.flagged))
      assert Enum.all?(snapshots, &(&1.user_id == host.id))
    end

    test "skips callers who are not in a lobby" do
      loner = AccountsFixtures.user_fixture()

      :ok = LobbySnapshots.capture_hook(:some_hook, loner, {:ok, :done})
      Process.sleep(50)
      :ok = Writer.flush()

      assert Repo.aggregate(Snapshot, :count) == 0
    end

    test "skips when there is no caller" do
      :ok = LobbySnapshots.capture_hook(:some_hook, nil, {:ok, :done})
      Process.sleep(50)
      :ok = Writer.flush()

      assert Repo.aggregate(Snapshot, :count) == 0
    end
  end
end
