defmodule Gamend.KVTest do
  use Gamend.DataCase, async: true

  import Ecto.Query

  alias Gamend.AccountsFixtures
  alias Gamend.KV

  test "put/get/update and delete" do
    user = AccountsFixtures.user_fixture()

    assert :error == KV.get("my_game:key1")

    assert {:ok, _row} =
             KV.put("my_game:key1", %{"a" => 1}, %{"plugin" => "my_game"})

    assert {:ok, %{value: %{"a" => 1}, metadata: %{"plugin" => "my_game"}}} =
             KV.get("my_game:key1")

    assert {:ok, _row} =
             KV.put("my_game:key1", %{"a" => 2}, %{"plugin" => "my_game"}, user_id: user.id)

    assert {:ok, %{value: %{"a" => 2}, metadata: %{"plugin" => "my_game"}}} =
             KV.get("my_game:key1", user_id: user.id)

    # Deleting the global entry doesn't affect the per-user one.
    assert :ok = KV.delete("my_game:key1")
    assert :error == KV.get("my_game:key1")
    assert {:ok, _} = KV.get("my_game:key1", user_id: user.id)

    assert :ok = KV.delete("my_game:key1", user_id: user.id)
    assert :error == KV.get("my_game:key1", user_id: user.id)
  end

  test "prune_prefix deletes old rows under a prefix, and nothing else" do
    user = AccountsFixtures.user_fixture()

    {:ok, _} = KV.put("hist:2026-01-01", %{"v" => 1}, %{}, user_id: user.id)
    {:ok, _} = KV.put("hist:2026-09-30", %{"v" => 2}, %{}, user_id: user.id)
    {:ok, _} = KV.put("hist_summary", %{"v" => 3}, %{}, user_id: user.id)
    {:ok, _} = KV.put("other:2026-01-01", %{"v" => 4}, %{}, user_id: user.id)

    # Read before the prune: the cached copy must not outlive the row.
    assert {:ok, _} = KV.get("hist:2026-01-01", user_id: user.id)
    assert length(KV.list_entries(user_id: user.id, key: "hist:")) == 2

    long_ago =
      DateTime.add(DateTime.utc_now(), -400 * 86_400, :second) |> DateTime.truncate(:second)

    Gamend.Repo.update_all(
      from(e in Gamend.KV.Entry,
        where: e.key in ["hist:2026-01-01", "hist_summary", "other:2026-01-01"]
      ),
      set: [updated_at: long_ago]
    )

    assert KV.prune_prefix("hist:", 365) == 1

    assert :error == KV.get("hist:2026-01-01", user_id: user.id)
    assert {:ok, _} = KV.get("hist:2026-09-30", user_id: user.id)
    # Another key family, and one only LIKE-shaped like it, are left alone.
    assert {:ok, _} = KV.get("hist_summary", user_id: user.id)
    assert {:ok, _} = KV.get("other:2026-01-01", user_id: user.id)
    assert [%{key: "hist:2026-09-30"}] = KV.list_entries(user_id: user.id, key: "hist:")

    assert KV.prune_prefix("", 1) == 0
    assert KV.prune_prefix("hist:", 0) == 0
  end

  test "register_kv_prefix runs as a retention class, its window read at each sweep" do
    user = AccountsFixtures.user_fixture()
    {:ok, _} = KV.put("hist2:old", %{"v" => 1}, %{}, user_id: user.id)

    long_ago =
      DateTime.add(DateTime.utc_now(), -40 * 86_400, :second) |> DateTime.truncate(:second)

    Gamend.Repo.update_all(from(e in Gamend.KV.Entry, where: e.key == "hist2:old"),
      set: [updated_at: long_ago]
    )

    window = :counters.new(1, [])

    :ok =
      Gamend.Retention.register_kv_prefix(:test_hist2, "hist2:", fn ->
        :counters.get(window, 1)
      end)

    on_exit(fn -> Gamend.Retention.unregister_class(:test_hist2) end)
    class = Gamend.Retention.registered_classes()[:test_hist2]

    # 0 keeps everything; the window is read when the sweep runs.
    assert class.() == 0
    :counters.put(window, 1, 30)
    assert class.() == 1
    assert :error == KV.get("hist2:old", user_id: user.id)
  end

  test "list/count entries supports global_only" do
    user = AccountsFixtures.user_fixture()

    {:ok, _} = KV.put("admin-kv:global-only:global", %{"v" => 1}, %{})
    {:ok, _} = KV.put("admin-kv:global-only:user", %{"v" => 2}, %{}, user_id: user.id)

    global_entries = KV.list_entries(global_only: true, page: 1, page_size: 100)
    global_keys = Enum.map(global_entries, & &1.key)

    assert "admin-kv:global-only:global" in global_keys
    refute "admin-kv:global-only:user" in global_keys
    assert Enum.all?(global_entries, &is_nil(&1.user_id))

    assert KV.count_entries(global_only: true) >= 1
  end
end
