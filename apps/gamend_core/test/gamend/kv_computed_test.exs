defmodule Gamend.KVComputedTest do
  use Gamend.DataCase, async: false

  alias Gamend.Accounts.Preferences
  alias Gamend.AccountsFixtures
  alias Gamend.AfterCommit
  alias Gamend.Hooks
  alias Gamend.KV
  alias Gamend.KV.Computed

  defmodule Host do
    @moduledoc false
    # A level from the points stored; no row before any points.
    def level(%{user_id: user_id}) do
      case KV.get("points", user_id: user_id) do
        {:ok, %{value: %{"points" => points}}} -> %{"level" => div(points, 100)}
        :error -> nil
      end
    end

    # A language's words counted, from that language's stored list.
    def words(%{user_id: user_id, part: part}) do
      case KV.get("words:" <> part, user_id: user_id) do
        {:ok, %{value: %{"words" => words}}} -> %{"count" => length(words), "part" => part}
        :error -> nil
      end
    end
  end

  setup do
    Application.put_env(:gamend_core, :computed_rows, %{
      "level" => %{value: {Host, :level}, from: ["points"]},
      "word_count:*" => %{value: {Host, :words}, from: ["words:*", "word_settings"]}
    })

    on_exit(fn -> Application.delete_env(:gamend_core, :computed_rows) end)
    %{user: AccountsFixtures.user_fixture()}
  end

  test "a computed row is read like a stored one, and stored nowhere", %{user: user} do
    assert :error == KV.get("level", user_id: user.id)

    {:ok, _entry} = KV.put("points", %{"points" => 250}, %{}, user_id: user.id)

    assert {:ok, %{value: %{"level" => 2}, metadata: %{}}} == KV.get("level", user_id: user.id)
    assert KV.count_entries(user_id: user.id, key: "level") == 0
  end

  test "a write or a delete of what it is worked out from says it moved, in that scope", %{
    user: user
  } do
    other = AccountsFixtures.user_fixture()
    :ok = KV.subscribe("level", user_id: user.id)

    {:ok, _entry} = KV.put("points", %{"points" => 100}, %{}, user_id: other.id)
    {:ok, _entry} = KV.put("unrelated", %{"v" => 1}, %{}, user_id: user.id)
    refute_receive {:kv_stale, _row}, 50

    {:ok, _entry} = KV.put("points", %{"points" => 100}, %{}, user_id: user.id)
    user_id = user.id
    assert_receive {:kv_stale, %{key: "level", user_id: ^user_id, lobby_id: nil}}

    :ok = KV.delete("points", user_id: user.id)
    assert_receive {:kv_stale, %{key: "level", user_id: ^user_id}}
  end

  test "refresh says a computed row moved, and nothing for a stored key", %{user: user} do
    :ok = KV.subscribe("level", user_id: user.id)
    :ok = KV.subscribe("points", user_id: user.id)

    assert :ok = KV.refresh("level", user_id: user.id)
    assert_receive {:kv_stale, %{key: "level"}}

    assert :ok = KV.refresh("points", user_id: user.id)
    refute_receive {:kv_stale, _row}, 50
  end

  test "inside a transaction it is said once it commits", %{user: user} do
    :ok = KV.subscribe("level", user_id: user.id)

    {:ok, :done} =
      AfterCommit.transaction(fn ->
        {:ok, _entry} = KV.put("points", %{"points" => 100}, %{}, user_id: user.id)
        refute_receive {:kv_stale, _row}, 50
        :done
      end)

    assert_receive {:kv_stale, %{key: "level"}}
  end

  test "a family's row is its part's, worked out from the same part's", %{user: user} do
    assert :error == KV.get("word_count:fr", user_id: user.id)
    {:ok, _entry} = KV.put("words:fr", %{"words" => ["a", "b"]}, %{}, user_id: user.id)
    {:ok, _entry} = KV.put("words:de", %{"words" => ["c"]}, %{}, user_id: user.id)

    assert {:ok, %{value: %{"count" => 2, "part" => "fr"}}} =
             KV.get("word_count:fr", user_id: user.id)

    assert {:ok, %{value: %{"count" => 1}}} = KV.get("word_count:de", user_id: user.id)
    assert :not_computed == Computed.fetch("word_count", user.id, nil)
    assert :not_computed == Computed.fetch("word_count:", user.id, nil)
    assert KV.count_entries(user_id: user.id, key: "word_count:fr") == 0
  end

  test "a write moves its own part's row, and no other", %{user: user} do
    :ok = KV.subscribe("word_count:fr", user_id: user.id)
    :ok = KV.subscribe("word_count:de", user_id: user.id)

    {:ok, _entry} = KV.put("words:fr", %{"words" => []}, %{}, user_id: user.id)
    assert_receive {:kv_stale, %{key: "word_count:fr"}}
    refute_receive {:kv_stale, %{key: "word_count:de"}}, 50

    assert Computed.dependents("words:fr") == ["word_count:fr"]
    assert Computed.dependents("words") == []
    assert Computed.dependents("points") == ["level"]
  end

  test "a key named whole, and a refresh of the family, move every part, said once",
       %{user: user} do
    :ok = KV.subscribe_family("word_count:*", user_id: user.id)
    :ok = KV.subscribe_family("word_count:*", user_id: user.id)
    user_id = user.id

    assert Computed.family("word_count:fr") == "word_count:*"
    assert Computed.family("word_count") == nil
    assert Computed.family?("word_count:*")
    refute Computed.family?("level")
    assert Computed.dependents("word_settings") == ["word_count:*"]

    {:ok, _entry} = KV.put("word_settings", %{"v" => 1}, %{}, user_id: user.id)
    assert_receive {:kv_stale, %{key: "word_count:*", user_id: ^user_id}}
    refute_receive {:kv_stale, %{key: "word_count:*"}}, 50

    :ok = KV.refresh("word_count:*", user_id: user.id)
    assert_receive {:kv_stale, %{key: "word_count:*", user_id: ^user_id}}

    :ok = KV.unsubscribe_family("word_count:*", user_id: user.id)
    :ok = KV.refresh("word_count:*", user_id: user.id)
    refute_receive {:kv_stale, _row}, 50
  end

  describe "the account's preferences" do
    test "are a row of what a client may set, theirs alone, and move with each change", %{
      user: user
    } do
      {:ok, user} =
        Preferences.update(user, &Map.merge(&1, %{"notifications" => %{"off_all" => true}}))

      assert {:ok, %{value: %{}}} = KV.get("preferences", user_id: user.id)
      assert :error == KV.get("preferences")

      :ok = KV.subscribe("preferences", user_id: user.id)
      {:ok, _user} = Preferences.put_client(user, "theme", "dark")
      user_id = user.id
      assert_receive {:kv_stale, %{key: "preferences", user_id: ^user_id}}

      assert {:ok, %{value: %{"theme" => "dark"} = row}} = KV.get("preferences", user_id: user.id)
      refute Map.has_key?(row, "notifications")

      {:ok, _user} = Preferences.put_client(user, "theme", "system")
      assert {:ok, %{value: %{}}} = KV.get("preferences", user_id: user.id)
    end

    test "are read by their owner alone, whatever a plugin answers" do
      assert Computed.access("preferences") == :owner_only
      assert Computed.access("level") == :public
      assert Computed.access("stored") == :public

      assert {:ok, :owner_only} ==
               Hooks.internal_call(:before_kv_get, ["preferences", %{user_id: nil}])

      assert {:ok, :public} ==
               Hooks.internal_call(:before_kv_get, ["level", %{user_id: nil}])
    end

    test "a host's row of the same name replaces core's" do
      Application.put_env(:gamend_core, :computed_rows, %{
        "preferences" => %{value: {Host, :level}, from: ["points"]}
      })

      assert Computed.access("preferences") == :public
      assert Computed.dependents("points") == ["preferences"]
    end
  end
end
