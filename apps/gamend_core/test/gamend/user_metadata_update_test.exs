defmodule Gamend.UserMetadataUpdateTest do
  @moduledoc """
  `Accounts.update_user_metadata/2`: payments and every plugin write their own
  keys into one `metadata` map, and a write replaces the whole map. A writer
  that read the row before another write landed must start over, not put the
  other writer's keys back as they were.
  """
  use Gamend.DataCase, async: false

  alias Gamend.Accounts
  alias Gamend.AccountsFixtures
  alias Gamend.Hooks.Default
  alias Gamend.Payments.Entitlement

  setup do
    handler = "user-metadata-update-#{System.unique_integer([:positive])}"
    :ok = :telemetry.attach(handler, [:gamend, :repo, :query], &__MODULE__.pause/4, nil)
    on_exit(fn -> :telemetry.detach(handler) end)
    %{user: AccountsFixtures.user_fixture()}
  end

  test "a write between another writer's read and its write survives", %{user: user} do
    late = paused(fn -> Accounts.update_user_metadata(user.id, &Map.put(&1, "lives", 3)) end)
    # A writer outside the line: only the compare stands between it and a
    # lost key.
    {:ok, _} = Accounts.merge_metadata(user, %{"shields" => 2})

    assert {:ok, _} = resume(late)
    assert %{"lives" => 3, "shields" => 2} = Accounts.get_user(user.id).metadata
  end

  test "an entitlement recorded while a plugin writes its own key is kept", %{user: user} do
    plugin = paused(fn -> Accounts.update_user_metadata(user.id, &Map.put(&1, "level", 7)) end)

    entitlement = %Entitlement{
      id: Ecto.UUID.generate(),
      user_id: user.id,
      key: "vip",
      status: "active"
    }

    payment = Task.async(fn -> Default.after_entitlement_changed(entitlement) end)

    assert {:ok, _} = resume(plugin)
    assert :ok = Task.await(payment, 5_000)

    metadata = Accounts.get_user(user.id).metadata
    assert metadata["level"] == 7
    assert get_in(metadata, ["payments", "entitlements", "vip"]) == true
  end

  test ":unchanged writes nothing and answers the stored user", %{user: user} do
    {:ok, _} = Accounts.update_user_metadata(user.id, &Map.put(&1, "a", 1))

    assert {:ok, %{metadata: %{"a" => 1}}} =
             Accounts.update_user_metadata(user.id, fn _ -> :unchanged end)
  end

  test "a refusal and a missing user are answered, not raised", %{user: user} do
    assert {:error, :nope} = Accounts.update_user_metadata(user.id, fn _ -> {:error, :nope} end)
    assert {:error, :not_found} = Accounts.update_user_metadata(Ecto.UUID.generate(), & &1)
  end

  describe "the admin's update_user/2 with metadata" do
    test "a key written since the form was opened stays", %{user: user} do
      opened = Accounts.get_user(user.id)

      # A purchase mirrored into metadata while the admin edits the form.
      {:ok, _} =
        Accounts.update_user_metadata(user.id, &Map.put(&1, "payments", %{"vip" => true}))

      assert {:ok, saved} =
               Accounts.update_user(opened, %{
                 "is_admin" => false,
                 "metadata" => Map.put(opened.metadata || %{}, "note", "checked")
               })

      # The save wrote the form's whole map: `payments` was gone.
      assert saved.metadata == %{"payments" => %{"vip" => true}, "note" => "checked"}
    end

    test "what the admin removes or changes is removed or changed", %{user: user} do
      {:ok, _} =
        Accounts.update_user_metadata(user.id, &Map.merge(&1, %{"a" => 1, "b" => 2, "c" => 3}))

      opened = Accounts.get_user(user.id)
      {:ok, _} = Accounts.update_user_metadata(user.id, &Map.put(&1, "d", 4))

      assert {:ok, saved} =
               Accounts.update_user(opened, %{metadata: %{"a" => 10, "c" => 3, x: true}})

      assert saved.metadata == %{"a" => 10, "c" => 3, "d" => 4, "x" => true}
    end
  end

  # Runs `fun` in its own process and returns once it has read the user row.
  defp paused(fun) do
    test = self()

    task =
      Task.async(fn ->
        Process.put(:pause_after_users_query, test)
        fun.()
      end)

    assert_receive {:paused, pid}, 5_000
    {task, pid}
  end

  defp resume({task, pid}) do
    send(pid, :resume)
    Task.await(task, 5_000)
  end

  @doc false
  def pause(_event, _measurements, %{source: "users"}, _config) do
    case Process.delete(:pause_after_users_query) do
      nil ->
        :ok

      test ->
        send(test, {:paused, self()})

        receive do
          :resume -> :ok
        end
    end
  end

  def pause(_event, _measurements, _metadata, _config), do: :ok
end
