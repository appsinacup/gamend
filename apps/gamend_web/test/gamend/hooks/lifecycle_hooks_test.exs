defmodule Gamend.Hooks.LifecycleHooksTest do
  use GamendWeb.ConnCase, async: false

  alias Gamend.AccountsFixtures
  alias Gamend.Friends
  alias Gamend.Leaderboards
  alias Gamend.Parties

  setup do
    orig = Application.get_env(:gamend_core, :hooks_module)
    on_exit(fn -> Application.put_env(:gamend_core, :hooks_module, orig) end)
    :ok
  end

  defmodule VetoPartyJoinHooks do
    use Gamend.TestSupport.NoopHooks

    @impl true
    def before_party_join(_user, _party), do: {:error, :party_join_vetoed}
  end

  defmodule ScoreListenerHooks do
    use Gamend.TestSupport.NoopHooks

    @impl true
    def after_score_submitted(record) do
      send(:score_hook_listener, {:score_submitted, record.id})
      :ok
    end
  end

  test "before_party_join can veto joining a party" do
    leader = AccountsFixtures.user_fixture()
    target = AccountsFixtures.user_fixture()

    {:ok, req} = Friends.create_request(leader, target.id)
    {:ok, _} = Friends.accept_friend_request(req.id, target)

    {:ok, party} = Parties.create_party(leader, %{max_size: 4})
    {:ok, _invite} = Parties.invite_to_party(leader, target.id)

    Application.put_env(:gamend_core, :hooks_module, VetoPartyJoinHooks)

    assert {:error, {:hook_rejected, :party_join_vetoed}} =
             Parties.accept_party_invite(target, party.id)

    refute Gamend.Accounts.get_user!(target.id).party_id
  end

  test "after_score_submitted fires for submitted scores" do
    Process.register(self(), :score_hook_listener)

    on_exit(fn ->
      Process.whereis(:score_hook_listener) && Process.unregister(:score_hook_listener)
    end)

    user = AccountsFixtures.user_fixture()
    {:ok, leaderboard} = Leaderboards.create_leaderboard(%{slug: "hook_lb", title: "Hook LB"})

    Application.put_env(:gamend_core, :hooks_module, ScoreListenerHooks)

    assert {:ok, record} = Leaderboards.submit_score(leaderboard.id, user.id, 42)
    assert_receive {:score_submitted, record_id}, 1_000
    assert record_id == record.id
  end
end
