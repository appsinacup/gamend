defmodule Gamend.PartyLeaderRaceTest do
  @moduledoc """
  What a leader's write reads before it, changed before it lands: a
  `max_size` lowered while an accept seats one more member (the update's
  `before_party_update` hook holds it until the accept is done), and a
  disband arriving after its leader handed the party over.

  The update counted the members before its hook and wrote whatever size it
  was given, so the party ended with more members than `max_size`. The
  disband checked leadership on the party read before it, so a leader who
  left (handing the party to the next member) still ended it for them.
  """

  use Gamend.DataCase, async: false

  alias Gamend.AccountsFixtures
  alias Gamend.Parties
  alias Gamend.Parties.Party

  defmodule HoldingHook do
    use Gamend.TestSupport.NoopHooks

    @impl true
    def before_party_update(party, attrs) do
      coordinator = Application.fetch_env!(:gamend, :party_leader_race)
      Agent.update(coordinator, &%{&1 | arrived: true})
      wait_until(fn -> Agent.get(coordinator, & &1.go) end)
      {:ok, {party, attrs}}
    end

    defp wait_until(fun, attempts \\ 300) do
      cond do
        fun.() ->
          :ok

        attempts == 0 ->
          raise "the test never let the hook go"

        true ->
          Process.sleep(10)
          wait_until(fun, attempts - 1)
      end
    end
  end

  setup do
    leader = AccountsFixtures.user_fixture()
    member = AccountsFixtures.user_fixture()
    :ok = AccountsFixtures.befriend(leader, member)

    {:ok, party} = Parties.create_party(leader, %{"max_size" => 3})
    {:ok, _} = Parties.invite_to_party(leader, member.id)
    {:ok, _} = Parties.accept_party_invite(member, party.id)

    %{leader: leader, member: member, party: party}
  end

  describe "update_party/2" do
    setup do
      {:ok, coordinator} = Agent.start_link(fn -> %{arrived: false, go: false} end)
      previous = Application.get_env(:gamend_core, :hooks_module)
      Application.put_env(:gamend_core, :hooks_module, HoldingHook)
      Application.put_env(:gamend, :party_leader_race, coordinator)

      on_exit(fn ->
        if previous,
          do: Application.put_env(:gamend_core, :hooks_module, previous),
          else: Application.delete_env(:gamend_core, :hooks_module)

        Application.delete_env(:gamend, :party_leader_race)
      end)

      %{coordinator: coordinator}
    end

    test "an accept landing while the update's hook runs: the update is refused", %{
      coordinator: coordinator,
      leader: leader,
      party: party
    } do
      third = AccountsFixtures.user_fixture()
      :ok = AccountsFixtures.befriend(leader, third)
      {:ok, _} = Parties.invite_to_party(leader, third.id)

      task = Task.async(fn -> Parties.update_party(leader, %{"max_size" => 2}) end)
      wait_until(fn -> Agent.get(coordinator, & &1.arrived) end)
      assert {:ok, _} = Parties.accept_party_invite(third, party.id)
      Agent.update(coordinator, &%{&1 | go: true})

      assert Task.await(task, 10_000) == {:error, :too_small}
      assert Repo.get!(Party, party.id).max_size == 3
      assert Parties.count_party_members(party.id) == 3
    end
  end

  describe "disband/2" do
    test "a disband after the leader handed the party over leaves it to the new leader", %{
      leader: leader,
      member: member,
      party: party
    } do
      # The disband's caller read the party while still its leader…
      assert Parties.can_manage_party?(leader, party)
      # …and left before the disband landed, handing it over.
      assert {:ok, :left} = Parties.leave_party(leader)

      assert {:error, :not_leader} = Parties.disband(party, leader)
      assert %Party{leader_id: leader_id} = Repo.get(Party, party.id)
      assert leader_id == member.id
    end

    test "the leader's disband ends the party", %{leader: leader, member: member, party: party} do
      assert {:ok, :disbanded} = Parties.disband(party, leader)
      assert Repo.get(Party, party.id) == nil
      assert Repo.get!(Gamend.Accounts.User, member.id).party_id == nil
    end
  end

  defp wait_until(fun, attempts \\ 300) do
    cond do
      fun.() ->
        :ok

      attempts == 0 ->
        flunk("the update never reached its hook")

      true ->
        Process.sleep(10)
        wait_until(fun, attempts - 1)
    end
  end
end
