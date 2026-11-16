defmodule Gamend.MatchmakingHooksTest do
  @moduledoc """
  The matchmaking hook contract: server authority over params, a custom
  matcher per bucket, and core's enforcement of invariants the game cannot
  be trusted with.
  """
  use Gamend.DataCase

  alias Gamend.AccountsFixtures
  alias Gamend.Friends
  alias Gamend.Matchmaking
  alias Gamend.Matchmaking.Ticket
  alias Gamend.Matchmaking.Worker

  # Rewrites params (drops whatever the client claimed) and vetoes one mode.
  defmodule AuthorityHook do
    def before_matchmaking_join(_user, %{"match_params" => %{"mode" => "banned"}}),
      do: {:error, :mode_disabled}

    def before_matchmaking_join(user, attrs) do
      rating = get_in(user.metadata, ["rating"]) || 1000

      {:ok,
       Map.put(attrs, "match_params", %{
         "mode" => "ranked",
         "band" => Integer.to_string(div(rating, 500))
       })}
    end

    def after_matchmaking_join(user, ticket) do
      send_test({:joined, user.id, ticket.id})
    end

    def after_matchmaking_cancel(user_id, count) do
      send_test({:cancelled, user_id, count})
    end

    def after_matchmaking_matched(tickets, lobby_id) do
      send_test({:matched, Enum.map(tickets, & &1.user_id), lobby_id})
    end

    defp send_test(msg) do
      case Application.get_env(:gamend, :hooks_test_pid) do
        nil -> :ok
        pid -> send(pid, msg)
      end

      :ok
    end
  end

  # Pairs by closest integer rating read off the user record, ignoring FIFO.
  defmodule RatingMatcherHook do
    def matchmaking_form_matches(%{"mode" => "ranked"}, tickets) do
      tickets
      |> Enum.map(&{get_in(&1.user.metadata, ["rating"]) || 0, &1})
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.chunk_every(2, 2, :discard)
      |> Enum.map(fn [{_, a}, {_, b}] -> [a, b] end)
    end

    def matchmaking_form_matches(_params, _tickets), do: :default
  end

  # Returns a group core must reject: two tickets that blocked each other.
  defmodule BlockIgnoringHook do
    def matchmaking_form_matches(_params, tickets), do: [Enum.take(tickets, 2)]
  end

  # Returns tickets that were never in the bucket.
  defmodule FabricatingHook do
    def matchmaking_form_matches(_params, tickets) do
      ghost = %{hd(tickets) | id: Ecto.UUID.generate()}
      [[hd(tickets), ghost]]
    end
  end

  defp install(mod) do
    orig = Application.get_env(:gamend_core, :hooks_module)
    Application.put_env(:gamend_core, :hooks_module, mod)
    Application.put_env(:gamend, :hooks_test_pid, self())

    on_exit(fn ->
      if orig,
        do: Application.put_env(:gamend_core, :hooks_module, orig),
        else: Application.delete_env(:gamend_core, :hooks_module)

      Application.delete_env(:gamend, :hooks_test_pid)
    end)
  end

  defp player(rating) do
    user = AccountsFixtures.unconfirmed_user_fixture()
    {:ok, user} = Gamend.Accounts.update_user(user, %{metadata: %{"rating" => rating}})
    {:ok, user} = user |> Ecto.Changeset.change(is_online: true) |> Repo.update()
    user
  end

  describe "before_matchmaking_join" do
    setup do: install(AuthorityHook)

    test "rewrites client params — a client cannot pick its own band" do
      {:ok, ticket} =
        Matchmaking.join(player(1450), %{"mode" => "casual", "band" => "99", "cheat" => "yes"})

      assert ticket.match_params == %{"mode" => "ranked", "band" => "2"}
    end

    test "vetoes a join" do
      assert {:error, :mode_disabled} = Matchmaking.join(player(1000), %{"mode" => "banned"})
      assert Matchmaking.stats().queued == 0
    end
  end

  describe "notification hooks" do
    setup do: install(AuthorityHook)

    test "after_matchmaking_join and after_matchmaking_cancel fire" do
      user = player(1000)
      {:ok, ticket} = Matchmaking.join(user, %{})

      assert_receive {:joined, user_id, ticket_id}
      assert user_id == user.id
      assert ticket_id == ticket.id

      assert Matchmaking.cancel(user.id) == 1
      assert_receive {:cancelled, cancelled_id, 1}
      assert cancelled_id == user.id
    end

    test "after_matchmaking_cancel does not fire when nothing was queued" do
      assert Matchmaking.cancel(player(1000).id) == 0
      refute_received {:cancelled, _, _}
    end
  end

  describe "matchmaking_form_matches" do
    setup do: install(RatingMatcherHook)

    test "a custom matcher overrides FIFO order" do
      # queued oldest-first: 1200, 2400, 1250 — FIFO would pair 1200+2400,
      # the rating matcher must pair 1200+1250 instead.
      low = player(1200)
      {:ok, _} = Matchmaking.join(low, %{"mode" => "ranked"})
      high = player(2400)
      {:ok, _} = Matchmaking.join(high, %{"mode" => "ranked"})
      near = player(1250)
      {:ok, _} = Matchmaking.join(near, %{"mode" => "ranked"})

      assert Worker.sweep() == 1

      matched = Matchmaking.list_tickets(status: "matched")
      assert Enum.sort(Enum.map(matched, & &1.user_id)) == Enum.sort([low.id, near.id])

      assert [remaining] = Matchmaking.list_tickets(status: "queued")
      assert remaining.user_id == high.id
    end

    test "an empty return from the matcher forms nothing" do
      {:ok, _} = Matchmaking.join(player(1200), %{"mode" => "ranked"})
      assert Worker.sweep() == 0
      assert Matchmaking.stats().queued == 1
    end
  end

  describe "core enforces invariants a custom matcher may violate" do
    test "a group pairing blocked players is dropped" do
      install(BlockIgnoringHook)

      alice = player(1000)
      bob = player(1000)
      {:ok, _} = Friends.block_user(alice, bob.id)

      {:ok, _} = Matchmaking.join(alice, %{"mode" => "ranked"})
      {:ok, _} = Matchmaking.join(bob, %{"mode" => "ranked"})

      assert Worker.sweep() == 0
      assert Matchmaking.stats().queued == 2
    end

    test "a group containing tickets outside the bucket is dropped" do
      install(FabricatingHook)

      {:ok, _} = Matchmaking.join(player(1000), %{"mode" => "ranked"})
      {:ok, _} = Matchmaking.join(player(1000), %{"mode" => "ranked"})

      assert Worker.sweep() == 0
      assert Matchmaking.stats().queued == 2
    end
  end

  describe "no hooks installed" do
    test "falls back to the built-in matcher" do
      alice = player(1000)
      bob = player(1000)
      {:ok, _} = Matchmaking.join(alice, %{"mode" => "duel"}, 2, 2)
      {:ok, _} = Matchmaking.join(bob, %{"mode" => "duel"}, 2, 2)

      assert Worker.sweep() == 1
      assert Enum.all?(Matchmaking.list_tickets([]), &(&1.status == "matched"))
      assert [%Ticket{}, %Ticket{}] = Matchmaking.list_tickets(status: "matched")
    end
  end
end
