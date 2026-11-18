defmodule Gamend.KVComputedTest do
  use Gamend.DataCase, async: false

  alias Gamend.AccountsFixtures
  alias Gamend.AfterCommit
  alias Gamend.KV

  defmodule Host do
    @moduledoc false
    # A level from the points stored; no row before any points.
    def level(%{user_id: user_id}) do
      case KV.get("points", user_id: user_id) do
        {:ok, %{value: %{"points" => points}}} -> %{"level" => div(points, 100)}
        :error -> nil
      end
    end
  end

  setup do
    Application.put_env(:gamend_core, :computed_rows, %{
      "level" => %{value: {Host, :level}, from: ["points"]}
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
end
