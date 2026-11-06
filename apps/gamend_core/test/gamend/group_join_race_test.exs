defmodule Gamend.GroupJoinRaceTest do
  @moduledoc """
  What a group join reads before its `before_group_join` hook, changed while
  the hook runs: the invite it accepts cancelled or declined, the join
  request it approves rejected, the group's `max_members` lowered. And the
  other way round: a join landing while an update's `before_group_update`
  hook runs.

  The accept read the invite once at the top and never claimed it, so a
  cancel or decline in that window still let the player into a private group
  and told the sender they joined. The approve wrote "accepted" over a
  reject. The join checked the room against the group read before the hook,
  and the update counted the members before its hook.

  The hook holds one side until the test has made the other change, so the
  interleaving happens on every run and on both adapters.
  """

  use Gamend.DataCase, async: false

  alias Gamend.AccountsFixtures
  alias Gamend.Groups
  alias Gamend.Groups.GroupInvite
  alias Gamend.Groups.GroupJoinRequest
  alias Gamend.Notifications.Notification

  defmodule HoldingHook do
    use Gamend.TestSupport.NoopHooks

    # Holds the hook named in the coordinator until the test lets it go.
    @impl true
    def before_group_join(user, group, opts) do
      hold(:before_group_join)
      {:ok, {user, group, opts}}
    end

    @impl true
    def before_group_update(group, attrs) do
      hold(:before_group_update)
      {:ok, {group, attrs}}
    end

    defp hold(hook) do
      coordinator = Application.fetch_env!(:gamend, :group_join_race)

      if Agent.get(coordinator, & &1.hold) == hook do
        Agent.update(coordinator, &%{&1 | arrived: true})
        wait_until(fn -> Agent.get(coordinator, & &1.go) end)
      end
    end

    defp wait_until(fun, attempts \\ 300) do
      cond do
        fun.() -> :ok
        attempts == 0 -> raise "the test never let the hook go"
        true -> sleep_then(fn -> wait_until(fun, attempts - 1) end)
      end
    end

    defp sleep_then(fun) do
      Process.sleep(10)
      fun.()
    end
  end

  setup do
    {:ok, coordinator} = Agent.start_link(fn -> %{hold: nil, arrived: false, go: false} end)
    previous = Application.get_env(:gamend_core, :hooks_module)
    Application.put_env(:gamend_core, :hooks_module, HoldingHook)
    Application.put_env(:gamend, :group_join_race, coordinator)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:gamend_core, :hooks_module, previous),
        else: Application.delete_env(:gamend_core, :hooks_module)

      Application.delete_env(:gamend, :group_join_race)
    end)

    admin = AccountsFixtures.user_fixture()
    player = AccountsFixtures.user_fixture()
    :ok = AccountsFixtures.befriend(admin, player)

    %{coordinator: coordinator, admin: admin, player: player}
  end

  # Runs `first` until it reaches `hook`, runs `meanwhile`, then lets `first`
  # finish. Answers `first`'s result.
  defp while_held(coordinator, hook, first, meanwhile) do
    Agent.update(coordinator, &%{&1 | hold: hook})
    task = Task.async(first)
    wait_until(fn -> Agent.get(coordinator, & &1.arrived) end)
    meanwhile.()
    Agent.update(coordinator, &%{&1 | go: true})
    Task.await(task, 10_000)
  end

  defp wait_until(fun, attempts \\ 300) do
    cond do
      fun.() -> :ok
      attempts == 0 -> flunk("never reached the hook")
      true -> sleep_then(fn -> wait_until(fun, attempts - 1) end)
    end
  end

  defp sleep_then(fun) do
    Process.sleep(10)
    fun.()
  end

  defp private_group(admin, attrs \\ %{}) do
    {:ok, group} =
      Groups.create_group(admin.id, Map.merge(%{"title" => "Crew", "type" => "private"}, attrs))

    group
  end

  defp heard(sender_id, type) do
    from(n in Notification, where: n.recipient_id == ^sender_id, select: n.metadata)
    |> Repo.all()
    |> Enum.count(&(&1["type"] == type))
  end

  describe "accepting an invite" do
    test "a cancel while the join hook runs keeps the player out", %{
      coordinator: coordinator,
      admin: admin,
      player: player
    } do
      group = private_group(admin)
      {:ok, invite} = Groups.invite_to_group(admin.id, group.id, player.id)

      result =
        while_held(
          coordinator,
          :before_group_join,
          fn -> Groups.accept_invite(player.id, invite.id) end,
          fn -> assert :ok = Groups.cancel_invite(admin.id, invite.id) end
        )

      assert result == {:error, :no_invite}
      refute Groups.member?(group.id, player.id)
      assert heard(admin.id, "group_invite_accepted") == 0
    end

    test "a decline while the join hook runs keeps the player out; the sender hears the decline only",
         %{coordinator: coordinator, admin: admin, player: player} do
      group = private_group(admin)
      {:ok, invite} = Groups.invite_to_group(admin.id, group.id, player.id)

      result =
        while_held(
          coordinator,
          :before_group_join,
          fn -> Groups.accept_invite(player.id, invite.id) end,
          fn -> assert :ok = Groups.decline_invite(player.id, invite.id) end
        )

      assert result == {:error, :no_invite}
      refute Groups.member?(group.id, player.id)
      assert Repo.get!(GroupInvite, invite.id).status == "declined"
      assert heard(admin.id, "group_invite_accepted") == 0
      assert heard(admin.id, "group_invite_declined") == 1
    end

    test "a decline after the accept has seated the player answers not_found", %{
      admin: admin,
      player: player
    } do
      group = private_group(admin)
      {:ok, invite} = Groups.invite_to_group(admin.id, group.id, player.id)

      assert {:ok, _member} = Groups.accept_invite(player.id, invite.id)
      assert {:error, :not_found} = Groups.decline_invite(player.id, invite.id)
      assert {:error, :not_found} = Groups.cancel_invite(admin.id, invite.id)
      assert heard(admin.id, "group_invite_declined") == 0
    end
  end

  describe "approving a join request" do
    test "a reject while the approve's join hook runs keeps the player out", %{
      coordinator: coordinator,
      admin: admin,
      player: player
    } do
      group = private_group(admin)
      {:ok, request} = Groups.request_join(player.id, group.id)

      result =
        while_held(
          coordinator,
          :before_group_join,
          fn -> Groups.approve_join_request(admin.id, request.id) end,
          fn -> assert {:ok, _} = Groups.reject_join_request(admin.id, request.id) end
        )

      assert result == {:error, :not_pending}
      refute Groups.member?(group.id, player.id)
      assert Repo.get!(GroupJoinRequest, request.id).status == "rejected"
      assert heard(player.id, "group_join_request_approved") == 0
      assert heard(player.id, "group_join_request_rejected") == 1
    end

    test "a reject after the approve answers not_pending and leaves the member be", %{
      admin: admin,
      player: player
    } do
      group = private_group(admin)
      {:ok, request} = Groups.request_join(player.id, group.id)

      assert {:ok, _member} = Groups.approve_join_request(admin.id, request.id)
      assert {:error, :not_pending} = Groups.reject_join_request(admin.id, request.id)
      assert Groups.member?(group.id, player.id)
      assert Repo.get!(GroupJoinRequest, request.id).status == "accepted"
      assert heard(player.id, "group_join_request_rejected") == 0
    end

    test "an approve holds the player's cap on groups", %{admin: admin, player: player} do
      previous = Application.get_env(:gamend_core, Gamend.Limits, [])
      Gamend.SettingsHelpers.put(:gamend_core, Gamend.Limits, :max_groups_per_user, 1)
      on_exit(fn -> Application.put_env(:gamend_core, Gamend.Limits, previous) end)

      {:ok, open} = Groups.create_group(admin.id, %{"title" => "Open", "type" => "public"})
      {:ok, _} = Groups.join_group(player.id, open.id)

      group = private_group(admin)
      {:ok, request} = Groups.request_join(player.id, group.id)

      assert {:error, :too_many_groups} = Groups.approve_join_request(admin.id, request.id)
      refute Groups.member?(group.id, player.id)
      assert Repo.get!(GroupJoinRequest, request.id).status == "pending"
    end
  end

  describe "max_members" do
    test "lowered while a join's hook runs: the join is refused", %{
      coordinator: coordinator,
      admin: admin,
      player: player
    } do
      {:ok, group} =
        Groups.create_group(admin.id, %{"title" => "Two", "type" => "public", "max_members" => 3})

      result =
        while_held(
          coordinator,
          :before_group_join,
          fn -> Groups.join_group(player.id, group.id) end,
          fn ->
            assert {:ok, _} = Groups.update_group(admin.id, group.id, %{"max_members" => 1})
          end
        )

      assert result == {:error, :full}
      assert Groups.count_group_members(group.id) == 1
    end

    test "a join landing while an update's hook runs: the update is refused", %{
      coordinator: coordinator,
      admin: admin,
      player: player
    } do
      {:ok, group} =
        Groups.create_group(admin.id, %{"title" => "Two", "type" => "public", "max_members" => 3})

      result =
        while_held(
          coordinator,
          :before_group_update,
          fn -> Groups.update_group(admin.id, group.id, %{"max_members" => 1}) end,
          fn -> assert {:ok, _} = Groups.join_group(player.id, group.id) end
        )

      assert result == {:error, :max_members_too_low}
      assert Groups.get_group(group.id).max_members == 3
      assert Groups.count_group_members(group.id) == 2
    end
  end
end
