defmodule Gamend.MembershipConcurrencyTest do
  @moduledoc """
  Players joining, leaving, kicking and disbanding lobbies, parties and groups
  all at once, then the rules every interleaving has to keep: no call raises,
  every refusal is one a client is told about, nothing is over capacity, every
  lobby and party is led by one of its members, every group keeps an admin,
  and every player can still take a seat afterwards.

  Each player draws its moves from the run's seed, so `mix test --seed N`
  replays a failing mix of moves (the interleaving itself still varies).
  """
  use Gamend.DataCase, async: false

  import Ecto.Query, only: [from: 2]

  alias Gamend.Accounts.User
  alias Gamend.AccountsFixtures
  alias Gamend.Groups
  alias Gamend.Groups.Group
  alias Gamend.Groups.GroupMember
  alias Gamend.Lobbies
  alias Gamend.Lobbies.Lobby
  alias Gamend.Parties
  alias Gamend.Parties.Party
  alias Gamend.Parties.PartyInvite
  alias Gamend.Repo

  @players 8
  @moves 25

  setup do
    %{players: for(_ <- 1..@players, do: AccountsFixtures.unconfirmed_user_fixture())}
  end

  test "lobbies keep their rules under concurrent joins, leaves, kicks and disbands",
       %{players: players} do
    players
    |> storm(&lobby_move/1)
    |> assert_answered([
      :already_in_lobby,
      :full,
      :invalid_lobby,
      :not_found,
      :not_host,
      :not_in_lobby,
      :user_not_in_lobby
    ])

    assert_lobby_rules()
    assert_everyone_can_take_a_seat(players)
  end

  test "parties keep their rules under concurrent invites, joins, leaves, kicks and lobby moves",
       %{players: players} do
    connect(players)

    players
    |> storm(&party_move/1)
    |> assert_answered([
      :already_in_lobby,
      :already_in_party,
      :already_invited,
      :cannot_kick_self,
      :full,
      :member_in_lobby,
      :no_invite,
      :not_connected,
      :not_enough_space,
      :not_found,
      :not_in_lobby,
      :not_in_party,
      :not_leader,
      :not_member,
      :party_full,
      :party_not_found,
      # The party gained or lost a member between the gates and the seats.
      :state_changed,
      :target_in_party,
      :too_many_invites
    ])

    assert_party_rules()
    assert_lobby_rules()
    assert_everyone_can_take_a_seat(players)
  end

  test "groups keep their rules under concurrent joins, leaves, kicks, promotions and deletes",
       %{players: players} do
    players
    |> storm(&group_move/1)
    |> assert_answered([
      :already_admin,
      :already_member,
      :cannot_kick_self,
      :last_admin,
      :not_admin,
      :not_found,
      :not_member,
      :not_admin_target
    ])

    assert_group_rules()
  end

  # Every player's moves at once; what each move answered.
  defp storm(players, move) do
    seed = ExUnit.configuration()[:seed]

    players
    |> Enum.with_index()
    |> Task.async_stream(
      fn {player, index} ->
        :rand.seed(:exsss, {seed, index, 1})
        for _ <- 1..@moves, do: attempt(fn -> move.(player) end)
      end,
      max_concurrency: length(players),
      timeout: 120_000
    )
    |> Enum.flat_map(fn {:ok, answers} -> answers end)
  end

  defp attempt(move) do
    move.()
  rescue
    error -> {:raised, Exception.format(:error, error, __STACKTRACE__)}
  catch
    :exit, reason -> {:raised, inspect(reason)}
  end

  defp assert_answered(answers, refusals) do
    raised = for {:raised, error} <- answers, do: error
    assert raised == [], Enum.join(raised, "\n")

    odd = answers |> Enum.reject(&told?(&1, refusals)) |> Enum.uniq()
    assert odd == [], "answers no client is told about: #{inspect(odd, pretty: true)}"
  end

  defp told?(:skip, _refusals), do: true
  defp told?(:ok, _refusals), do: true
  defp told?({:ok, _}, _refusals), do: true
  defp told?({:error, reason}, refusals), do: reason in refusals
  defp told?(_answer, _refusals), do: false

  defp me(player), do: Repo.get!(User, player.id)

  defp pick([]), do: nil
  defp pick(list), do: Enum.random(list)

  defp lobby_ids, do: Repo.all(from l in Lobby, select: l.id)

  defp lobby_member_ids(lobby_id),
    do: Repo.all(from u in User, where: u.lobby_id == ^lobby_id, select: u.id)

  defp lobby_move(player) do
    case me(player) do
      %User{lobby_id: nil} = me ->
        case :rand.uniform(3) do
          1 -> join_any_lobby(me)
          2 -> Lobbies.quick_join(me, "soak", 3, %{})
          3 -> Lobbies.create_lobby(%{title: "soak", host_id: me.id, max_users: 3})
        end

      %User{lobby_id: lobby_id} = me ->
        case :rand.uniform(3) do
          1 -> Lobbies.leave_lobby(me)
          2 -> kick_from_lobby(me, lobby_id)
          3 -> disband_lobby(me, lobby_id)
        end
    end
  end

  defp join_any_lobby(me) do
    case pick(lobby_ids()) do
      nil -> :skip
      lobby_id -> Lobbies.join_lobby(me, lobby_id)
    end
  end

  defp kick_from_lobby(me, lobby_id) do
    with %Lobby{} = lobby <- Repo.get(Lobby, lobby_id),
         target_id when is_binary(target_id) <- pick(lobby_member_ids(lobby_id) -- [me.id]) do
      Lobbies.kick_user(me, lobby, Repo.get!(User, target_id))
    else
      _ -> :skip
    end
  end

  # The API's disband: the host ends the lobby, anyone else leaves it.
  defp disband_lobby(me, lobby_id) do
    case Repo.get(Lobby, lobby_id) do
      %Lobby{host_id: host_id} = lobby when host_id == me.id -> Lobbies.delete_lobby(lobby)
      _ -> Lobbies.leave_lobby(me)
    end
  end

  # Party invites need the leader and the player connected, and a party moves
  # into a lobby only with every member online.
  defp connect([first | rest] = players) do
    ids = Enum.map(players, & &1.id)
    Repo.update_all(from(u in User, where: u.id in ^ids), set: [is_online: true])

    {:ok, group} =
      Groups.create_group(first.id, %{title: "soak-#{System.unique_integer([:positive])}"})

    for player <- rest, do: {:ok, _} = Groups.join_group(player.id, group.id)
  end

  defp party_move(player) do
    case me(player) do
      %User{party_id: nil} = me ->
        case :rand.uniform(3) do
          1 -> Parties.create_party(me, %{max_size: 3})
          2 -> accept_any_invite(me)
          3 -> if me.lobby_id, do: Lobbies.leave_lobby(me), else: :skip
        end

      %User{party_id: party_id} = me ->
        case :rand.uniform(6) do
          1 -> Parties.leave_party(me)
          2 -> invite_anyone(me)
          3 -> kick_from_party(me, party_id)
          4 -> Parties.quick_join_with_party(me, %{title: "soak-party", max_users: 6})
          5 -> Parties.create_lobby_with_party(me, %{title: "soak-party", max_users: 6})
          6 -> if me.lobby_id, do: Lobbies.leave_lobby(me), else: accept_any_invite(me)
        end
    end
  end

  defp accept_any_invite(me) do
    invited =
      Repo.all(
        from i in PartyInvite,
          where: i.recipient_id == ^me.id and i.status == "pending",
          select: i.party_id
      )

    case pick(invited) do
      nil -> :skip
      party_id -> Parties.accept_party_invite(me, party_id)
    end
  end

  defp invite_anyone(me) do
    case pick(Repo.all(from u in User, where: u.id != ^me.id, select: u.id)) do
      nil -> :skip
      target_id -> Parties.invite_to_party(me, target_id)
    end
  end

  defp kick_from_party(me, party_id) do
    members = Repo.all(from u in User, where: u.party_id == ^party_id, select: u.id)

    case pick(members -- [me.id]) do
      nil -> :skip
      target_id -> Parties.kick_member(me, target_id)
    end
  end

  defp group_move(player) do
    groups = Repo.all(from g in Group, select: g.id)
    group_id = pick(groups)

    case {:rand.uniform(6), group_id} do
      {1, _} ->
        Groups.create_group(player.id, %{title: "soak-#{System.unique_integer([:positive])}"})

      {_, nil} ->
        :skip

      {2, group_id} ->
        Groups.join_group(player.id, group_id)

      {3, group_id} ->
        Groups.leave_group(player.id, group_id)

      {4, group_id} ->
        group_admin_move(player, group_id, &Groups.kick_member/3)

      {5, group_id} ->
        group_admin_move(player, group_id, &promote_or_demote/3)

      {6, group_id} ->
        Groups.delete_group(player.id, group_id)
    end
  end

  defp group_admin_move(player, group_id, move) do
    members = Repo.all(from m in GroupMember, where: m.group_id == ^group_id, select: m.user_id)

    case pick(members -- [player.id]) do
      nil -> :skip
      target_id -> move.(player.id, group_id, target_id)
    end
  end

  defp promote_or_demote(admin_id, group_id, target_id) do
    if :rand.uniform(2) == 1,
      do: Groups.promote_member(admin_id, group_id, target_id),
      else: Groups.demote_member(admin_id, group_id, target_id)
  end

  defp assert_lobby_rules do
    for lobby <- Repo.all(Lobby) do
      members = lobby_member_ids(lobby.id)

      assert length(members) <= lobby.max_users,
             "lobby #{lobby.id} seats #{length(members)} of #{lobby.max_users}"

      unless lobby.hostless or members == [] do
        assert lobby.host_id in members,
               "lobby #{lobby.id} is hosted by #{inspect(lobby.host_id)}, not one of #{inspect(members)}"
      end
    end

    seated = Repo.all(from u in User, where: not is_nil(u.lobby_id), select: u.lobby_id)
    assert Enum.all?(seated, &Repo.get(Lobby, &1)), "a player is seated in a lobby that is gone"
  end

  defp assert_party_rules do
    for party <- Repo.all(Party) do
      members = Repo.all(from u in User, where: u.party_id == ^party.id, select: u.id)

      assert members != [], "party #{party.id} has nobody in it"

      assert length(members) <= party.max_size,
             "party #{party.id} holds #{length(members)} of #{party.max_size}"

      assert party.leader_id in members,
             "party #{party.id} is led by #{party.leader_id}, not one of #{inspect(members)}"
    end
  end

  defp assert_group_rules do
    for group <- Repo.all(Group) do
      roles = Repo.all(from m in GroupMember, where: m.group_id == ^group.id, select: m.role)

      assert length(roles) <= group.max_members
      assert "admin" in roles, "group #{group.id} has members #{inspect(roles)} and no admin"
    end
  end

  # Nothing left a player stuck: each can leave whatever they are in and
  # quick-join a lobby.
  defp assert_everyone_can_take_a_seat(players) do
    for player <- players do
      left = Lobbies.leave_lobby(me(player))
      assert match?({:ok, _}, left) or left == {:error, :not_in_lobby}, inspect(left)

      assert {:ok, %Lobby{}} = Lobbies.quick_join(me(player), "after", @players, %{})
    end
  end
end
