defmodule Gamend.PartyBlocklistTest do
  @moduledoc """
  A party invite is checked against every current member, not just the leader,
  so a block cannot be routed around by having a mutual friend do the inviting.
  """
  use Gamend.DataCase

  alias Gamend.AccountsFixtures
  alias Gamend.Friends
  alias Gamend.Parties

  defp user do
    user = AccountsFixtures.unconfirmed_user_fixture()
    {:ok, user} = user |> Ecto.Changeset.change(is_online: true) |> Repo.update()
    user
  end

  defp befriend(a, b) do
    {:ok, request} = Friends.create_request(a, b.id)
    {:ok, _} = Friends.accept_friend_request(request.id, b)
    :ok
  end

  defp party_with(leader, members) do
    {:ok, party} = Parties.create_party(leader)

    for member <- members do
      member |> Ecto.Changeset.change(party_id: party.id) |> Repo.update!()
    end

    {party, Repo.reload(leader)}
  end

  test "a friend cannot invite you into a party holding someone you blocked" do
    leader = user()
    enemy = user()
    victim = user()

    {:ok, _} = Friends.block_user(victim, enemy.id)
    befriend(leader, victim)
    {_party, leader} = party_with(leader, [enemy])

    assert {:error, :blocked} = Parties.invite_to_party(leader, victim.id)
  end

  test "the block holds in the other direction too" do
    leader = user()
    hater = user()
    target = user()

    # The existing member blocked the invitee, rather than the other way round.
    {:ok, _} = Friends.block_user(hater, target.id)
    befriend(leader, target)
    {_party, leader} = party_with(leader, [hater])

    assert {:error, :blocked} = Parties.invite_to_party(leader, target.id)
  end

  test "the leader's own block still applies" do
    leader = user()
    target = user()

    {:ok, _} = Friends.block_user(leader, target.id)
    {_party, leader} = party_with(leader, [])

    assert {:error, :blocked} = Parties.invite_to_party(leader, target.id)
  end

  test "an unrelated member does not prevent an invite" do
    leader = user()
    bystander = user()
    target = user()

    befriend(leader, target)
    {_party, leader} = party_with(leader, [bystander])

    assert {:ok, _invite} = Parties.invite_to_party(leader, target.id)
  end

  test "a block landing between invite and accept is caught on accept" do
    leader = user()
    enemy = user()
    victim = user()

    befriend(leader, victim)
    {party, leader} = party_with(leader, [])

    # Invite is legitimate at the time it is sent.
    assert {:ok, _} = Parties.invite_to_party(leader, victim.id)

    # ...then the party gains a member the invitee had blocked.
    {:ok, _} = Friends.block_user(victim, enemy.id)
    enemy |> Ecto.Changeset.change(party_id: party.id) |> Repo.update!()

    assert {:error, :blocked} = Parties.accept_party_invite(victim, party.id)

    members = party.id |> Parties.get_party_members() |> Enum.map(& &1.id)
    refute victim.id in members
  end
end
