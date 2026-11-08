defmodule Gamend.MatchmakingSeatHookTest do
  @moduledoc """
  `matchmaking_seat_match/1`: the game answers where a formed match sits and
  whether its players are asked first, and core does the seating.
  """
  use Gamend.DataCase

  alias Gamend.AccountsFixtures
  alias Gamend.Lobbies
  alias Gamend.Matchmaking
  alias Gamend.Matchmaking.Ticket
  alias Gamend.Matchmaking.Worker
  alias Gamend.MatchSeating
  alias Gamend.Parties
  alias Gamend.ReadyChecks
  alias Gamend.ReadyChecks.Check

  @params %{"mode" => "duel"}
  @answer_key :seat_hook_test_answer

  # Forms every ticket (or party) into a match of its own: how a game offers a
  # newcomer a free seat, with nobody already seated holding a ticket.
  defmodule Hook do
    @answer_key :seat_hook_test_answer

    def matchmaking_form_matches(_params, tickets) do
      tickets |> Enum.group_by(&(&1.party_id || &1.id)) |> Map.values()
    end

    def matchmaking_seat_match(tickets) do
      Application.fetch_env!(:gamend, @answer_key).(tickets)
    end
  end

  setup do
    orig = Application.get_env(:gamend_core, :hooks_module)
    Application.put_env(:gamend_core, :hooks_module, Hook)

    on_exit(fn ->
      if orig,
        do: Application.put_env(:gamend_core, :hooks_module, orig),
        else: Application.delete_env(:gamend_core, :hooks_module)

      Application.delete_env(:gamend, @answer_key)
    end)
  end

  defp answer(fun), do: Application.put_env(:gamend, @answer_key, fun)

  defp user do
    AccountsFixtures.user_fixture()
    |> Ecto.Changeset.change(is_online: true)
    |> Repo.update!()
  end

  defp ticket!(user), do: elem(Matchmaking.join(user, @params, 1, 4), 1)

  defp status(ticket), do: Repo.get!(Ticket, ticket.id).status
  defp seat_of(user), do: Repo.get!(Gamend.Accounts.User, user.id).lobby_id

  # A running match: hidden, locked, hostless, `seated` players in it.
  defp room(max_users, seated) do
    {:ok, lobby} =
      Lobbies.create_lobby(%{
        max_users: max_users,
        is_hidden: true,
        is_locked: true,
        hostless: true
      })

    for player <- seated do
      {:ok, _} = Lobbies.join_lobby(player, lobby.id, %{bypass_hidden: true, bypass_lock: true})
    end

    lobby
  end

  defp party_of_two do
    leader = user()
    {:ok, party} = Parties.create_party(leader)
    member = user() |> Ecto.Changeset.change(party_id: party.id) |> Repo.update!()
    {Repo.reload!(leader), member}
  end

  describe "a new lobby with the game's settings" do
    test "are the lobby's, and it opens once seated" do
      answer(fn _ ->
        MatchSeating.new_lobby(title: "Arena", max_users: 6, is_hidden: false, is_locked: false)
      end)

      player = user()
      ticket!(player)

      assert Worker.sweep() == 1

      lobby = Lobbies.get_lobby!(seat_of(player))
      assert lobby.title == "Arena"
      assert lobby.max_users == 6
      refute lobby.is_hidden
      refute lobby.is_locked
    end

    test "a host holding a ticket is seated once, and hosts it" do
      host = user()
      answer(fn _ -> MatchSeating.new_lobby(host_id: host.id) end)
      ticket = ticket!(host)

      assert Worker.sweep() == 1

      lobby = Lobbies.get_lobby!(seat_of(host))
      assert lobby.host_id == host.id
      refute lobby.hostless
      assert status(ticket) == "matched"
    end
  end

  describe "an existing lobby" do
    test "a newcomer takes a free seat of a locked, hostless match" do
      seated = user()
      lobby = room(3, [seated])
      answer(fn _ -> MatchSeating.in_lobby(lobby.id) end)

      newcomer = user()
      Phoenix.PubSub.subscribe(Gamend.PubSub, "matchmaking:user:#{newcomer.id}")
      ticket!(newcomer)

      assert Worker.sweep() == 1

      assert seat_of(newcomer) == lobby.id
      assert seat_of(seated) == lobby.id
      assert_receive {:matchmaking_event, "match_found", %{lobby_id: lobby_id}}
      assert lobby_id == lobby.id
    end

    test "a full lobby keeps the player in the queue" do
      lobby = room(1, [user()])
      answer(fn _ -> MatchSeating.in_lobby(lobby.id) end)

      newcomer = user()
      ticket = ticket!(newcomer)

      assert Worker.sweep() == 0

      assert seat_of(newcomer) == nil
      assert status(ticket) == "queued"
    end

    test "a full lobby does not cost a player the lobby they are in" do
      lobby = room(1, [user()])
      answer(fn _ -> MatchSeating.in_lobby(lobby.id) end)

      newcomer = user()
      {:ok, own} = Lobbies.create_lobby(%{host_id: newcomer.id, max_users: 2})
      ticket = newcomer |> Repo.reload!() |> ticket!()

      assert Worker.sweep() == 0

      assert seat_of(newcomer) == own.id
      assert status(ticket) == "queued"
    end

    test "a lobby that is gone keeps the player in the queue" do
      answer(fn _ -> MatchSeating.in_lobby(Ecto.UUID.generate()) end)
      ticket = ticket!(user())

      assert Worker.sweep() == 0
      assert status(ticket) == "queued"
    end

    test "a party goes in whole" do
      lobby = room(4, [user()])
      answer(fn _ -> MatchSeating.in_lobby(lobby.id) end)
      {leader, member} = party_of_two()
      ticket!(leader)

      assert Worker.sweep() == 1

      assert seat_of(leader) == lobby.id
      assert seat_of(member) == lobby.id
    end

    @tag capture_log: true
    test "or not at all" do
      lobby = room(2, [user()])
      answer(fn _ -> MatchSeating.in_lobby(lobby.id) end)
      {leader, member} = party_of_two()
      ticket = ticket!(leader)

      assert Worker.sweep() == 0

      assert seat_of(leader) == nil
      assert seat_of(member) == nil
      assert status(ticket) == "queued"
    end
  end

  describe "asking first" do
    test "only the newcomer is asked, and nobody is seated until they say yes" do
      seated = user()
      lobby = room(3, [seated])
      answer(fn _ -> MatchSeating.in_lobby(lobby.id, accept_timeout_ms: 5_000) end)

      newcomer = user()
      ticket!(newcomer)

      assert Worker.sweep() == 0
      assert seat_of(newcomer) == nil

      assert %Check{kind: "accept", participants: [%{user_id: asked}]} =
               ReadyChecks.for_user(newcomer.id, :match)

      assert asked == newcomer.id
      assert ReadyChecks.for_user(seated.id, :match) == nil

      {:ok, _} = ReadyChecks.respond(newcomer, true)

      assert seat_of(newcomer) == lobby.id
    end

    test "new-lobby settings outlast the wait" do
      answer(fn _ -> MatchSeating.new_lobby(title: "Asked", accept_timeout_ms: 5_000) end)

      player = user()
      ticket!(player)

      assert Worker.sweep() == 0

      {:ok, _} = ReadyChecks.respond(player, true)

      assert Lobbies.get_lobby!(seat_of(player)).title == "Asked"
    end

    test "where the match will sit is never sent to clients" do
      lobby = room(3, [user()])
      answer(fn _ -> MatchSeating.in_lobby(lobby.id, accept_timeout_ms: 5_000) end)

      newcomer = user()
      ticket!(newcomer)
      Worker.sweep()

      check = ReadyChecks.for_user(newcomer.id, :match)

      assert check.seating != nil
      refute Jason.encode!(check) =~ lobby.id
    end

    test "default keeps core's seat and only adds the question" do
      answer(fn _ -> MatchSeating.default(accept_timeout_ms: 5_000) end)

      player = user()
      ticket!(player)

      assert Worker.sweep() == 0

      {:ok, _} = ReadyChecks.respond(player, true)

      assert Lobbies.get_lobby!(seat_of(player)).hostless
    end
  end

  describe "an answer that cannot be used puts the tickets back" do
    test ":default is core's seat" do
      answer(fn _ -> :default end)
      player = user()
      ticket!(player)

      assert Worker.sweep() == 1
      assert Lobbies.get_lobby!(seat_of(player)).is_hidden
    end

    test "a refusal" do
      answer(fn _ -> {:error, :not_now} end)
      ticket = ticket!(user())

      assert Worker.sweep() == 0
      assert status(ticket) == "queued"
    end

    @tag capture_log: true
    test "a hook that raises" do
      answer(fn _ -> raise "boom" end)
      ticket = ticket!(user())

      assert Worker.sweep() == 0
      assert status(ticket) == "queued"
    end

    @tag capture_log: true
    test "an answer that is not a seating" do
      answer(fn _ -> %{lobby_id: "typed by hand"} end)
      ticket = ticket!(user())

      assert Worker.sweep() == 0
      assert status(ticket) == "queued"
    end
  end
end
