defmodule Gamend.TournamentRegisterRaceTest do
  @moduledoc """
  Registrations landing together, with `before_tournament_register` charging
  the entry fee as the guides tell games to.

  The hook used to run before the seat was taken, after only a read of the
  field: a double tap passed that read twice and charged twice (one seat then
  failed `:already_registered`), and two players reaching the last seat were
  both charged while one was answered `:tournament_full`. The seat is now
  taken first, so a request that cannot have one never reaches the hook.

  The hook holds the first caller until the second has reached the hook too,
  or has been answered, so the old order interleaves on every run and on both
  adapters.
  """

  use Gamend.DataCase, async: false

  alias Gamend.AccountsFixtures
  alias Gamend.Tournaments
  alias Gamend.Tournaments.Entry
  alias Gamend.Tournaments.Match
  alias Gamend.Tournaments.Tournament

  defmodule ChargingHook do
    use Gamend.TestSupport.NoopHooks

    # Counts charges. In a race, the first caller in waits for the other to be
    # charged too, or to be answered without it.
    @impl true
    def before_tournament_register(user, tournament) do
      coordinator = Application.fetch_env!(:gamend, :tournament_register_race)

      {charged, hold?} =
        Agent.get_and_update(coordinator, fn state ->
          {{state.charged + 1, state.hold}, %{state | charged: state.charged + 1}}
        end)

      if hold? and charged == 1 do
        wait_until(fn ->
          state = Agent.get(coordinator, & &1)
          state.charged >= 2 or state.answered >= 1
        end)
      end

      case Application.get_env(:gamend, :tournament_register_race_hook) do
        nil -> {:ok, {user, tournament}}
        fun -> fun.(user, tournament)
      end
    end

    @impl true
    def after_tournament_register(_user, _tournament) do
      coordinator = Application.fetch_env!(:gamend, :tournament_register_race)
      Agent.update(coordinator, &%{&1 | registered: &1.registered + 1})
    end

    defp wait_until(fun, attempts \\ 200) do
      cond do
        fun.() ->
          :ok

        attempts == 0 ->
          raise "the other registration never got there"

        true ->
          Process.sleep(10)
          wait_until(fun, attempts - 1)
      end
    end
  end

  setup do
    {:ok, coordinator} =
      Agent.start_link(fn -> %{charged: 0, answered: 0, registered: 0, hold: false} end)

    previous = Application.get_env(:gamend_core, :hooks_module)
    Application.put_env(:gamend_core, :hooks_module, ChargingHook)
    Application.put_env(:gamend, :tournament_register_race, coordinator)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:gamend_core, :hooks_module, previous),
        else: Application.delete_env(:gamend_core, :hooks_module)

      Application.delete_env(:gamend, :tournament_register_race)
      Application.delete_env(:gamend, :tournament_register_race_hook)
    end)

    %{coordinator: coordinator}
  end

  defp tournament(attrs \\ %{}) do
    {:ok, tournament} =
      %{
        slug: "register-race-#{System.unique_integer([:positive])}",
        title: "Register Race",
        starts_at: DateTime.add(DateTime.utc_now(:second), 3600),
        round_window_sec: 600,
        bracket_size: 8
      }
      |> Map.merge(attrs)
      |> Tournaments.create_tournament()

    tournament
  end

  defp race(coordinator, joins) do
    Agent.update(coordinator, &%{&1 | hold: true})

    joins
    |> Enum.map(fn join ->
      Task.async(fn ->
        result = join.()
        Agent.update(coordinator, &%{&1 | answered: &1.answered + 1})
        result
      end)
    end)
    |> Task.await_many(10_000)
  end

  defp charged(coordinator), do: Agent.get(coordinator, & &1.charged)

  test "a double tap is charged once", %{coordinator: coordinator} do
    tournament = tournament()
    user = AccountsFixtures.user_fixture()
    join = fn -> Tournaments.join_tournament(user, tournament) end

    results = race(coordinator, [join, join])

    assert Enum.count(results, &match?({:ok, %Entry{}}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :already_registered})) == 1
    assert charged(coordinator) == 1, "the repeated request reached the hook"
    assert Tournaments.count_entries(tournament.id) == 1
  end

  test "the last seat is charged once, and the player without it never", %{
    coordinator: coordinator
  } do
    tournament = tournament(%{max_entries: 2})
    [early, first, second] = for _ <- 1..3, do: AccountsFixtures.user_fixture()
    {:ok, _} = Tournaments.join_tournament(early, tournament)
    Agent.update(coordinator, &%{&1 | charged: 0})

    results =
      race(coordinator, [
        fn -> Tournaments.join_tournament(first, tournament) end,
        fn -> Tournaments.join_tournament(second, tournament) end
      ])

    assert Enum.count(results, &match?({:ok, %Entry{}}, &1)) == 1
    assert Enum.count(results, &(&1 == {:error, :tournament_full})) == 1
    assert charged(coordinator) == 1, "a player refused the seat was charged"
    assert Tournaments.count_entries(tournament.id) == 2
  end

  describe "a refusal" do
    test "gives the seat back and registers nobody", %{coordinator: coordinator} do
      tournament = tournament(%{max_entries: 2})
      [early, user] = for _ <- 1..2, do: AccountsFixtures.user_fixture()
      {:ok, _} = Tournaments.join_tournament(early, tournament)

      Application.put_env(:gamend, :tournament_register_race_hook, fn _user, _tournament ->
        {:error, :not_enough_coins}
      end)

      assert Tournaments.join_tournament(user, tournament) == {:error, :not_enough_coins}
      assert Tournaments.count_entries(tournament.id) == 1

      # The seat is free again for someone the game lets in.
      Application.delete_env(:gamend, :tournament_register_race_hook)
      assert {:ok, _} = Tournaments.join_tournament(AccountsFixtures.user_fixture(), tournament)
      assert Tournaments.count_entries(tournament.id) == 2
      refute Tournaments.get_entry(tournament.id, user.id)

      assert Agent.get(coordinator, & &1.registered) == 2,
             "after_tournament_register fired for the refused player"
    end

    test "after the draw took the seat forfeits the entry's match" do
      tournament = tournament(%{bracket_size: 4})
      [top, rival, refused] = for _ <- 1..3, do: AccountsFixtures.user_fixture()
      {:ok, _} = Tournaments.join_tournament(top, tournament)
      {:ok, _} = Tournaments.join_tournament(rival, tournament)

      # The draw lands while the refused player's hook runs.
      Application.put_env(:gamend, :tournament_register_race_hook, fn _user, t ->
        {:ok, due} = Tournaments.update_tournament(t, %{starts_at: DateTime.utc_now(:second)})
        %Tournament{state: "running"} = Tournaments.advance_lifecycle(due)
        {:error, :not_enough_coins}
      end)

      assert Tournaments.join_tournament(refused, tournament) == {:error, :not_enough_coins}

      entry = Tournaments.get_entry(tournament.id, refused.id)
      assert entry.state == "eliminated"

      # Seeds 1 (a bye), 2 and 3: the refused third seed's match goes to the
      # second, who meets the first in the final.
      matches = Repo.all(from m in Match, where: m.tournament_id == ^tournament.id)

      forfeited =
        Enum.find(matches, &(&1.round == 1 and entry.id in [&1.a_entry_id, &1.b_entry_id]))

      rival_entry = Tournaments.get_entry(tournament.id, rival.id)

      assert forfeited.winner_entry_id == rival_entry.id
      assert forfeited.metadata["withdrawn"] == true

      [final] = Enum.filter(matches, &(&1.round == 2))
      top_entry = Tournaments.get_entry(tournament.id, top.id)

      assert Enum.sort([final.a_entry_id, final.b_entry_id]) ==
               Enum.sort([top_entry.id, rival_entry.id])

      assert is_nil(final.resolved_at)
    end
  end
end
