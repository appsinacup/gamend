defmodule Gamend.PartiesTest.HooksAllowPartyCreate do
  def before_party_create(_user, attrs), do: {:ok, attrs}
end

defmodule Gamend.PartiesTest.HooksDenyPartyCreate do
  def before_party_create(_user, _attrs), do: {:error, :party_creation_blocked}
end

defmodule Gamend.PartiesTest.HooksModifyPartyCreate do
  def before_party_create(_user, attrs) do
    {:ok, Map.put(attrs, "max_size", 3)}
  end
end

defmodule Gamend.PartiesTest.HooksAllowPartyUpdate do
  def before_party_update(_party, attrs), do: {:ok, attrs}
end

defmodule Gamend.PartiesTest.HooksDenyPartyUpdate do
  def before_party_update(_party, _attrs), do: {:error, :party_update_blocked}
end

defmodule Gamend.PartiesTest.HooksModifyPartyUpdate do
  def before_party_update(_party, attrs) do
    {:ok, Map.put(attrs, "max_size", 5)}
  end
end

defmodule Gamend.PartiesTest do
  use Gamend.DataCase

  alias Gamend.Accounts
  alias Gamend.AccountsFixtures
  alias Gamend.Chat.Message
  alias Gamend.Friends
  alias Gamend.Lobbies
  alias Gamend.Lobbies.Lobby
  alias Gamend.Parties
  alias Gamend.Parties.Party
  alias Gamend.Parties.PartyInvite

  setup do
    leader = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
    member1 = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
    member2 = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()

    %{leader: leader, member1: member1, member2: member2}
  end

  # Directly sets the party_id on a user (test setup helper only).
  defp add_member_to_party(user, party) do
    user
    |> Ecto.Changeset.change(%{party_id: party.id})
    |> Gamend.Repo.update!()
  end

  # Sets all given users as online (required for party lobby operations).
  defp set_all_online(users) do
    Enum.each(users, &Accounts.set_user_online(&1.id))
  end

  # Creates a mutual friendship for invite eligibility.
  defp make_friends(user_a, user_b) do
    {:ok, req} = Friends.create_request(user_a, user_b.id)
    Friends.accept_friend_request(req.id, user_b)
  end

  describe "create_party/2" do
    test "creates a party and sets user as leader and member", %{leader: leader} do
      assert {:ok, party} = Parties.create_party(leader, %{max_size: 4})
      assert party.leader_id == leader.id
      assert party.max_size == 4

      # Leader should now have party_id set
      updated_leader = Accounts.get_user(leader.id)
      assert updated_leader.party_id == party.id
    end

    test "cannot create party while already in a party", %{leader: leader} do
      {:ok, _party} = Parties.create_party(leader, %{})

      assert {:error, :already_in_party} = Parties.create_party(leader, %{})
    end

    test "uses default max_size when not specified", %{leader: leader} do
      assert {:ok, party} = Parties.create_party(leader)
      assert party.max_size == 4
    end
  end

  describe "invite_to_party/2" do
    test "leader can invite a friend", %{leader: leader, member1: member1} do
      {:ok, _party} = Parties.create_party(leader, %{max_size: 4})
      make_friends(leader, member1)

      assert {:ok, _notification} = Parties.invite_to_party(leader, member1.id)
    end

    test "leader can invite a shared group member", %{leader: leader, member1: member1} do
      {:ok, _party} = Parties.create_party(leader, %{max_size: 4})

      {:ok, group} =
        Gamend.Groups.create_group(leader.id, %{"title" => "g", "type" => "public"})

      {:ok, _} = Gamend.Groups.join_group(member1.id, group.id)

      assert {:ok, _notification} = Parties.invite_to_party(leader, member1.id)
    end

    test "fails when caller is not the leader", %{
      leader: leader,
      member1: member1,
      member2: member2
    } do
      {:ok, party} = Parties.create_party(leader, %{max_size: 4})
      add_member_to_party(member1, party)
      make_friends(member1, member2)

      assert {:error, :not_leader} = Parties.invite_to_party(member1, member2.id)
    end

    test "fails when target is not a friend or group member", %{leader: leader, member1: member1} do
      {:ok, _party} = Parties.create_party(leader, %{max_size: 4})

      assert {:error, :not_connected} = Parties.invite_to_party(leader, member1.id)
    end

    test "succeeds when target is already in a party", %{leader: leader, member1: member1} do
      {:ok, _party} = Parties.create_party(leader, %{max_size: 4})
      {:ok, _other} = Parties.create_party(member1, %{})
      make_friends(leader, member1)

      assert {:ok, _invite} = Parties.invite_to_party(leader, member1.id)
    end

    test "succeeds idempotently when invite already pending", %{leader: leader, member1: member1} do
      {:ok, _party} = Parties.create_party(leader, %{max_size: 4})
      make_friends(leader, member1)

      assert {:ok, invite1} = Parties.invite_to_party(leader, member1.id)
      assert {:ok, invite2} = Parties.invite_to_party(leader, member1.id)
      assert invite1.id == invite2.id
    end

    test "can re-invite after previous invite was declined", %{leader: leader, member1: member1} do
      {:ok, party} = Parties.create_party(leader, %{max_size: 4})
      make_friends(leader, member1)

      assert {:ok, invite1} = Parties.invite_to_party(leader, member1.id)
      assert :ok = Parties.decline_party_invite(member1, party.id)
      assert {:ok, invite2} = Parties.invite_to_party(leader, member1.id)

      assert invite2.id != invite1.id
      assert invite2.status == "pending"
    end

    test "can re-invite after previous invite was accepted and user left", %{
      leader: leader,
      member1: member1
    } do
      {:ok, party} = Parties.create_party(leader, %{max_size: 4})
      make_friends(leader, member1)

      assert {:ok, invite1} = Parties.invite_to_party(leader, member1.id)
      assert {:ok, _party} = Parties.accept_party_invite(member1, party.id)
      assert {:ok, :left} = Parties.leave_party(Accounts.get_user(member1.id))
      assert {:ok, invite2} = Parties.invite_to_party(leader, member1.id)

      assert invite2.id != invite1.id
      assert invite2.status == "pending"
    end

    test "stores sender_name and recipient_name in notification metadata", %{
      leader: leader,
      member1: member1
    } do
      {:ok, _} =
        Gamend.Accounts.update_user_display_name(leader, %{"display_name" => "LeaderDisplay"})

      {:ok, _} =
        Gamend.Accounts.update_user_display_name(member1, %{
          "display_name" => "Member1Display"
        })

      {:ok, _party} = Parties.create_party(leader, %{max_size: 4})
      make_friends(leader, member1)
      {:ok, invite} = Parties.invite_to_party(leader, member1.id)

      # invite_to_party now returns a PartyInvite record
      assert invite.sender_id == leader.id
      assert invite.recipient_id == member1.id
      assert invite.status == "pending"

      # Verify the informational notification was also created with metadata
      # (make_friends/2 also produces friend notifications, so filter by type)
      [notification] =
        member1.id
        |> Gamend.Notifications.list_notifications()
        |> Enum.filter(&(&1.metadata["type"] == "party_invite"))

      assert notification.metadata["sender_name"] == "LeaderDisplay"
      assert notification.metadata["recipient_name"] == "Member1Display"
    end
  end

  describe "accept_party_invite/2" do
    test "user can accept a valid invite and joins the party", %{leader: leader, member1: member1} do
      {:ok, party} = Parties.create_party(leader, %{max_size: 4})
      make_friends(leader, member1)
      {:ok, _} = Parties.invite_to_party(leader, member1.id)

      assert {:ok, joined_party} = Parties.accept_party_invite(member1, party.id)
      assert joined_party.id == party.id

      updated = Accounts.get_user(member1.id)
      assert updated.party_id == party.id
    end

    test "invite notification is removed after accept", %{leader: leader, member1: member1} do
      {:ok, party} = Parties.create_party(leader, %{max_size: 4})
      make_friends(leader, member1)
      {:ok, _} = Parties.invite_to_party(leader, member1.id)

      {:ok, _} = Parties.accept_party_invite(member1, party.id)

      invites = Parties.list_party_invitations(member1)
      assert invites == []
    end

    test "fails when no invite exists", %{leader: leader, member1: member1} do
      {:ok, party} = Parties.create_party(leader, %{max_size: 4})

      assert {:error, :no_invite} = Parties.accept_party_invite(member1, party.id)
    end

    test "auto-leaves current party when accepting another invite", %{
      leader: leader,
      member1: member1,
      member2: _member2
    } do
      {:ok, party} = Parties.create_party(leader, %{max_size: 4})
      make_friends(leader, member1)
      # Send invite while member1 is not yet in a party
      {:ok, _} = Parties.invite_to_party(leader, member1.id)
      # Now put member1 into their own party (directly, to simulate concurrent join)
      {:ok, other_party} = Parties.create_party(member1, %{})

      # Accept should auto-leave the other party and join the new one
      assert {:ok, joined_party} = Parties.accept_party_invite(member1, party.id)
      assert joined_party.id == party.id

      # The old party should be disbanded (member1 was leader)
      assert is_nil(Parties.get_party(other_party.id))
    end

    test "fails when party is full", %{leader: leader, member1: member1, member2: member2} do
      {:ok, party} = Parties.create_party(leader, %{max_size: 2})
      add_member_to_party(member1, party)
      make_friends(leader, member2)
      {:ok, _} = Parties.invite_to_party(leader, member2.id)

      assert {:error, :party_full} = Parties.accept_party_invite(member2, party.id)
    end

    test "full party marks invite as declined and notifies sender", %{
      leader: leader,
      member1: member1,
      member2: member2
    } do
      {:ok, party} = Parties.create_party(leader, %{max_size: 2})
      add_member_to_party(member1, party)
      make_friends(leader, member2)
      {:ok, invite} = Parties.invite_to_party(leader, member2.id)

      assert {:error, :party_full} = Parties.accept_party_invite(member2, party.id)

      # Invite should be marked as "declined"
      updated_invite = Gamend.Repo.get(Gamend.Parties.PartyInvite, invite.id)
      assert updated_invite.status == "declined"

      # Sender (leader) should receive a notification about the decline
      notifs = Gamend.Notifications.list_notifications(leader.id)

      declined_notif =
        Enum.find(notifs, fn n -> n.metadata["type"] == "party_invite_declined" end)

      assert declined_notif != nil
      assert declined_notif.metadata["reason"] == "party_full"
      assert declined_notif.metadata["party_id"] == party.id
      assert declined_notif.metadata["user_id"] == member2.id
    end
  end

  describe "decline_party_invite/2" do
    test "removes the invite notification", %{leader: leader, member1: member1} do
      {:ok, party} = Parties.create_party(leader, %{max_size: 4})
      make_friends(leader, member1)
      {:ok, _} = Parties.invite_to_party(leader, member1.id)

      assert :ok = Parties.decline_party_invite(member1, party.id)

      invites = Parties.list_party_invitations(member1)
      assert invites == []
    end

    test "is idempotent with no invite", %{leader: leader, member1: member1} do
      {:ok, party} = Parties.create_party(leader, %{max_size: 4})

      assert :ok = Parties.decline_party_invite(member1, party.id)
    end
  end

  describe "cancel_party_invite/2" do
    test "leader can cancel a pending invite", %{leader: leader, member1: member1} do
      {:ok, _party} = Parties.create_party(leader, %{max_size: 4})
      make_friends(leader, member1)
      {:ok, _} = Parties.invite_to_party(leader, member1.id)

      assert :ok = Parties.cancel_party_invite(leader, member1.id)

      invites = Parties.list_party_invitations(member1)
      assert invites == []
    end

    test "fails when caller is not the leader", %{
      leader: leader,
      member1: member1,
      member2: member2
    } do
      {:ok, party} = Parties.create_party(leader, %{max_size: 4})
      add_member_to_party(member1, party)
      make_friends(leader, member2)
      {:ok, _} = Parties.invite_to_party(leader, member2.id)

      assert {:error, :not_leader} = Parties.cancel_party_invite(member1, member2.id)
    end

    test "does not broadcast when no invite existed", %{leader: leader, member1: member1} do
      {:ok, _party} = Parties.create_party(leader, %{max_size: 4})
      make_friends(leader, member1)

      # Subscribe to PubSub to verify no broadcast is emitted
      Phoenix.PubSub.subscribe(Gamend.PubSub, "user:#{member1.id}")

      # Cancel with no prior invite — should succeed silently
      assert :ok = Parties.cancel_party_invite(leader, member1.id)

      # Ensure no spurious cancelled event was broadcast
      refute_receive {:party_invite_cancelled, _}, 100
    end
  end

  describe "list_party_invitations/1" do
    test "returns pending invites for user", %{leader: leader, member1: member1} do
      {:ok, party} = Parties.create_party(leader, %{max_size: 4})
      make_friends(leader, member1)
      {:ok, _} = Parties.invite_to_party(leader, member1.id)

      invites = Parties.list_party_invitations(member1)
      assert length(invites) == 1
      assert hd(invites).party_id == party.id
      assert hd(invites).sender_id == leader.id
    end

    test "includes sender_name and recipient_name", %{leader: leader, member1: member1} do
      {:ok, _} =
        Gamend.Accounts.update_user_display_name(leader, %{"display_name" => "InvLeader"})

      {:ok, _} =
        Gamend.Accounts.update_user_display_name(member1, %{"display_name" => "InvMember"})

      {:ok, _party} = Parties.create_party(leader, %{max_size: 4})
      make_friends(leader, member1)
      {:ok, _} = Parties.invite_to_party(leader, member1.id)

      invites = Parties.list_party_invitations(member1)
      assert length(invites) == 1
      invite = hd(invites)
      assert invite.sender_name == "InvLeader"
      assert invite.recipient_name == "InvMember"
    end

    test "returns empty list with no invites", %{member1: member1} do
      assert Parties.list_party_invitations(member1) == []
    end
  end

  describe "leave_party/1" do
    # Handed over rather than disbanded: losing the party because one player left
    # punished everyone else for it, the same reasoning lobbies migrate a host on.
    test "leader leaving hands the party to the next member", %{leader: leader, member1: member1} do
      {:ok, party} = Parties.create_party(leader, %{})
      add_member_to_party(member1, party)

      assert {:ok, :left} = Parties.leave_party(leader)

      assert Parties.get_party(party.id).leader_id == member1.id
      assert is_nil(Accounts.get_user(leader.id).party_id)
      assert Accounts.get_user(member1.id).party_id == party.id
    end

    test "the last member leaving disbands the party", %{leader: leader} do
      {:ok, party} = Parties.create_party(leader, %{})

      assert {:ok, :disbanded} = Parties.leave_party(leader)

      assert is_nil(Parties.get_party(party.id))
      assert is_nil(Accounts.get_user(leader.id).party_id)
    end

    test "regular member leaving does not disband the party", %{
      leader: leader,
      member1: member1
    } do
      {:ok, party} = Parties.create_party(leader, %{})
      add_member_to_party(member1, party)

      assert {:ok, :left} = Parties.leave_party(member1)

      # Party should still exist
      assert Parties.get_party(party.id) != nil

      # Only the member should have been removed
      assert is_nil(Accounts.get_user(member1.id).party_id)
      assert Accounts.get_user(leader.id).party_id == party.id
    end

    test "returns error when not in a party", %{member1: member1} do
      assert {:error, :not_in_party} = Parties.leave_party(member1)
    end
  end

  describe "kick_member/2" do
    test "leader can kick a member", %{leader: leader, member1: member1} do
      {:ok, party} = Parties.create_party(leader, %{})
      add_member_to_party(member1, party)

      assert {:ok, _} = Parties.kick_member(leader, member1.id)

      assert is_nil(Accounts.get_user(member1.id).party_id)
      assert Parties.get_party(party.id) != nil
    end

    test "non-leader cannot kick", %{leader: leader, member1: member1} do
      {:ok, party} = Parties.create_party(leader, %{})
      add_member_to_party(member1, party)

      assert {:error, :not_leader} = Parties.kick_member(member1, leader.id)
    end

    test "cannot kick self", %{leader: leader} do
      {:ok, _party} = Parties.create_party(leader, %{})

      assert {:error, :cannot_kick_self} = Parties.kick_member(leader, leader.id)
    end
  end

  describe "update_party/2" do
    test "leader can update party settings", %{leader: leader} do
      {:ok, _party} = Parties.create_party(leader, %{max_size: 4})

      assert {:ok, updated} = Parties.update_party(leader, %{max_size: 8})
      assert updated.max_size == 8
    end

    test "cannot reduce max_size below current member count", %{
      leader: leader,
      member1: member1
    } do
      {:ok, party} = Parties.create_party(leader, %{max_size: 4})
      add_member_to_party(member1, party)

      # 2 members, can't set to 1
      assert {:error, :too_small} = Parties.update_party(leader, %{max_size: 1})
    end

    test "non-leader cannot update", %{leader: leader, member1: member1} do
      {:ok, party} = Parties.create_party(leader, %{})
      add_member_to_party(member1, party)

      assert {:error, :not_leader} = Parties.update_party(member1, %{max_size: 8})
    end
  end

  describe "create_lobby_with_party/2" do
    test "leader creates lobby and all members join, party stays intact", %{
      leader: leader,
      member1: member1
    } do
      {:ok, party} = Parties.create_party(leader, %{max_size: 4})
      add_member_to_party(member1, party)
      set_all_online([leader, member1])

      assert {:ok, lobby} =
               Parties.create_lobby_with_party(leader, %{title: "party-lobby", max_users: 8})

      assert lobby.title == "party-lobby"

      # Party should still exist
      assert Parties.get_party(party.id) != nil

      # Both users should be in the lobby
      assert Accounts.get_user(leader.id).lobby_id == lobby.id
      assert Accounts.get_user(member1.id).lobby_id == lobby.id

      # Both should still be in the party
      assert Accounts.get_user(leader.id).party_id == party.id
      assert Accounts.get_user(member1.id).party_id == party.id
    end

    test "fails if lobby max_users is too small for party", %{
      leader: leader,
      member1: member1,
      member2: member2
    } do
      {:ok, party} = Parties.create_party(leader, %{max_size: 4})
      add_member_to_party(member1, party)
      add_member_to_party(member2, party)
      set_all_online([leader, member1, member2])

      # 3 members but max_users = 2
      assert {:error, :lobby_too_small_for_party} =
               Parties.create_lobby_with_party(leader, %{title: "tiny", max_users: 2})
    end

    test "non-leader cannot create lobby with party", %{leader: leader, member1: member1} do
      {:ok, party} = Parties.create_party(leader, %{})
      add_member_to_party(member1, party)
      set_all_online([leader, member1])

      assert {:error, :not_leader} = Parties.create_lobby_with_party(member1, %{title: "nope"})
    end

    test "fails if any party member is already in a lobby", %{leader: leader, member1: member1} do
      {:ok, party} = Parties.create_party(leader, %{max_size: 4})
      add_member_to_party(member1, party)
      set_all_online([leader, member1])

      # Put member1 in a lobby
      host = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
      {:ok, lobby} = Lobbies.create_lobby(%{title: "existing", host_id: host.id})
      Lobbies.join_lobby(member1, lobby.id)

      assert {:error, :member_in_lobby} =
               Parties.create_lobby_with_party(leader, %{title: "party-lobby", max_users: 8})
    end

    # Seats a member elsewhere from inside `create_lobby/1`: after the party's
    # members were checked, before they are seated.
    defmodule SeatElsewhereOnCreateHook do
      use Gamend.TestSupport.NoopHooks

      @impl true
      def before_lobby_create(attrs) do
        {user_id, lobby_id} = Application.fetch_env!(:gamend, :seat_on_lobby_create)

        Gamend.Repo.get!(Gamend.Accounts.User, user_id)
        |> Ecto.Changeset.change(lobby_id: lobby_id)
        |> Gamend.Repo.update!()

        {:ok, attrs}
      end
    end

    test "a member seated elsewhere after the check keeps that seat and the party stays out",
         %{leader: leader, member1: member1} do
      {:ok, party} = Parties.create_party(leader, %{max_size: 4})
      add_member_to_party(member1, party)
      set_all_online([leader, member1])
      {:ok, elsewhere} = Lobbies.create_lobby(%{title: "elsewhere", hostless: true})

      original = Application.get_env(:gamend_core, :hooks_module)
      Application.put_env(:gamend, :seat_on_lobby_create, {member1.id, elsewhere.id})
      Application.put_env(:gamend_core, :hooks_module, SeatElsewhereOnCreateHook)

      on_exit(fn ->
        Application.delete_env(:gamend, :seat_on_lobby_create)
        Application.put_env(:gamend_core, :hooks_module, original)
      end)

      assert {:error, :member_in_lobby} =
               Parties.create_lobby_with_party(leader, %{title: "party-lobby", max_users: 8})

      assert Gamend.Repo.get!(Accounts.User, member1.id).lobby_id == elsewhere.id
      assert Gamend.Repo.get!(Accounts.User, leader.id).lobby_id == nil
      refute Gamend.Repo.get_by(Lobby, title: "party-lobby")
    end
  end

  describe "join_lobby_with_party/3" do
    test "leader joins existing lobby and all members join, party stays intact", %{
      leader: leader,
      member1: member1
    } do
      {:ok, party} = Parties.create_party(leader, %{max_size: 4})
      add_member_to_party(member1, party)
      set_all_online([leader, member1])

      # Create a lobby with a different host
      host = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
      {:ok, lobby} = Lobbies.create_lobby(%{title: "existing-lobby", host_id: host.id})

      assert {:ok, joined_lobby} = Parties.join_lobby_with_party(leader, lobby.id)
      assert joined_lobby.id == lobby.id

      # Party should still exist
      assert Parties.get_party(party.id) != nil

      # All users should be in the lobby
      assert Accounts.get_user(leader.id).lobby_id == lobby.id
      assert Accounts.get_user(member1.id).lobby_id == lobby.id

      # All users should still be in the party
      assert Accounts.get_user(leader.id).party_id == party.id
      assert Accounts.get_user(member1.id).party_id == party.id
    end

    defmodule JoinPartyDuringHook do
      use Gamend.TestSupport.NoopHooks

      # A player joins the party while the game is asked about its members:
      # after they were read, before the seats.
      @impl true
      def before_lobby_join(user, lobby, opts) do
        {joiner_id, party_id} = Application.fetch_env!(:gamend, :join_party_during_hook)

        if Gamend.Repo.get!(Gamend.Accounts.User, joiner_id).party_id != party_id do
          Gamend.Repo.get!(Gamend.Accounts.User, joiner_id)
          |> Ecto.Changeset.change(party_id: party_id)
          |> Gamend.Repo.update!()
        end

        {:ok, {user, lobby, opts}}
      end
    end

    test "a party that changed between the gates and the seats is not seated", %{
      leader: leader,
      member1: member1,
      member2: member2
    } do
      {:ok, party} = Parties.create_party(leader, %{max_size: 4})
      add_member_to_party(member1, party)
      set_all_online([leader, member1, member2])
      {:ok, lobby} = Lobbies.create_lobby(%{title: "changed-party", hostless: true})

      original = Application.get_env(:gamend_core, :hooks_module)
      Application.put_env(:gamend, :join_party_during_hook, {member2.id, party.id})
      Application.put_env(:gamend_core, :hooks_module, JoinPartyDuringHook)

      on_exit(fn ->
        Application.delete_env(:gamend, :join_party_during_hook)
        Application.put_env(:gamend_core, :hooks_module, original)
      end)

      assert {:error, :state_changed} = Parties.join_lobby_with_party(leader, lobby.id)

      for user <- [leader, member1, member2],
          do: assert(Gamend.Repo.get!(Accounts.User, user.id).lobby_id == nil)
    end

    test "fails if lobby doesn't have enough space", %{
      leader: leader,
      member1: member1,
      member2: member2
    } do
      {:ok, party} = Parties.create_party(leader, %{max_size: 4})
      add_member_to_party(member1, party)
      add_member_to_party(member2, party)
      set_all_online([leader, member1, member2])

      # Create a lobby with max 3 users and 1 already in it (the host)
      host = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
      {:ok, lobby} = Lobbies.create_lobby(%{title: "small-lobby", host_id: host.id, max_users: 3})

      # 3 party members + 1 existing host = 4, but max is 3
      assert {:error, :not_enough_space} = Parties.join_lobby_with_party(leader, lobby.id)
    end

    test "fails if lobby is locked", %{leader: leader, member1: member1} do
      {:ok, party} = Parties.create_party(leader, %{})
      add_member_to_party(member1, party)
      set_all_online([leader, member1])

      host = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()

      {:ok, lobby} =
        Lobbies.create_lobby(%{title: "locked-lobby", host_id: host.id, is_locked: true})

      assert {:error, :locked} = Parties.join_lobby_with_party(leader, lobby.id)
    end

    test "fails if lobby requires password and no password given", %{
      leader: leader,
      member1: member1
    } do
      {:ok, party} = Parties.create_party(leader, %{})
      add_member_to_party(member1, party)
      set_all_online([leader, member1])

      host = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
      phash = Bcrypt.hash_pwd_salt("secret")

      {:ok, lobby} =
        Lobbies.create_lobby(%{
          title: "pw-lobby",
          host_id: host.id,
          password_hash: phash,
          max_users: 8
        })

      assert {:error, :password_required} = Parties.join_lobby_with_party(leader, lobby.id)
    end

    test "succeeds with correct password", %{leader: leader, member1: member1} do
      {:ok, party} = Parties.create_party(leader, %{})
      add_member_to_party(member1, party)
      set_all_online([leader, member1])

      host = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
      phash = Bcrypt.hash_pwd_salt("secret")

      {:ok, lobby} =
        Lobbies.create_lobby(%{
          title: "pw-lobby",
          host_id: host.id,
          password_hash: phash,
          max_users: 8
        })

      assert {:ok, _} = Parties.join_lobby_with_party(leader, lobby.id, %{password: "secret"})
    end

    test "non-leader cannot join lobby with party", %{leader: leader, member1: member1} do
      {:ok, party} = Parties.create_party(leader, %{})
      add_member_to_party(member1, party)
      set_all_online([leader, member1])

      host = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
      {:ok, lobby} = Lobbies.create_lobby(%{title: "test-lobby", host_id: host.id})

      assert {:error, :not_leader} = Parties.join_lobby_with_party(member1, lobby.id)
    end

    test "cannot join non-existent lobby with party", %{leader: leader, member1: member1} do
      {:ok, party} = Parties.create_party(leader, %{})
      add_member_to_party(member1, party)
      set_all_online([leader, member1])

      assert {:error, :invalid_lobby} =
               Parties.join_lobby_with_party(leader, Ecto.UUID.generate())
    end

    test "fails with wrong password", %{leader: leader, member1: member1} do
      {:ok, party} = Parties.create_party(leader, %{})
      add_member_to_party(member1, party)
      set_all_online([leader, member1])

      host = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
      phash = Bcrypt.hash_pwd_salt("secret")

      {:ok, lobby} =
        Lobbies.create_lobby(%{
          title: "pw-lobby",
          host_id: host.id,
          password_hash: phash,
          max_users: 8
        })

      assert {:error, :invalid_password} =
               Parties.join_lobby_with_party(leader, lobby.id, %{password: "wrong"})

      # Party should still exist after failed join
      updated_leader = Accounts.get_user(leader.id)
      assert updated_leader.party_id != nil
      assert is_nil(updated_leader.lobby_id)
    end

    test "fails if any party member is already in a lobby", %{leader: leader, member1: member1} do
      {:ok, party} = Parties.create_party(leader, %{max_size: 4})
      add_member_to_party(member1, party)
      set_all_online([leader, member1])

      # Put member1 in a lobby
      host = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
      {:ok, existing_lobby} = Lobbies.create_lobby(%{title: "existing", host_id: host.id})
      Lobbies.join_lobby(member1, existing_lobby.id)

      # Create a target lobby to try to join
      host2 = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
      {:ok, target_lobby} = Lobbies.create_lobby(%{title: "target", host_id: host2.id})

      assert {:error, :member_in_lobby} = Parties.join_lobby_with_party(leader, target_lobby.id)
    end

    # A party gets in only where each member could alone: a solo join of a
    # hidden lobby is 404, and a party walked in by its id.
    test "a hidden lobby is not found, unless the server bypasses it", %{
      leader: leader,
      member1: member1
    } do
      {:ok, party} = Parties.create_party(leader, %{max_size: 4})
      add_member_to_party(member1, party)
      set_all_online([leader, member1])

      host = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()

      {:ok, lobby} =
        Lobbies.create_lobby(%{title: "hidden-lobby", host_id: host.id, is_hidden: true})

      assert {:error, :not_found} = Parties.join_lobby_with_party(leader, lobby.id)
      assert Accounts.get_user(member1.id).lobby_id == nil

      assert {:ok, _} = Parties.join_lobby_with_party(leader, lobby.id, %{bypass_hidden: true})
      assert Accounts.get_user(member1.id).lobby_id == lobby.id
    end

    test "a block between any member and anyone seated keeps the party out", %{
      leader: leader,
      member1: member1
    } do
      {:ok, party} = Parties.create_party(leader, %{max_size: 4})
      add_member_to_party(member1, party)
      set_all_online([leader, member1])

      host = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
      {:ok, lobby} = Lobbies.create_lobby(%{title: "with-a-block", host_id: host.id})
      {:ok, _} = Friends.block_user(host, member1.id)

      assert {:error, :blocked} = Parties.join_lobby_with_party(leader, lobby.id)
      assert Accounts.get_user(leader.id).lobby_id == nil
      assert Accounts.get_user(member1.id).lobby_id == nil
    end
  end

  # Party seats bypassed `Lobbies.join_lobby/3`, and with it the game's
  # `before_lobby_join`: a lobby a game kept a player out of took them as part
  # of a party.
  describe "the game's before_lobby_join, for a party seat" do
    defmodule MidMatchHooks do
      use Gamend.TestSupport.NoopHooks

      @impl true
      def before_lobby_join(user, lobby, opts) do
        # Hook arguments arrive as plain data: the opts' keys are strings.
        send(:persistent_term.get({__MODULE__, :pid}), {:asked, user.id, opts["party_id"]})
        if lobby.title == "mid-match", do: {:error, :mid_match}, else: {:ok, {user, lobby, opts}}
      end
    end

    setup %{leader: leader, member1: member1} do
      original = Application.get_env(:gamend_core, :hooks_module)
      :persistent_term.put({MidMatchHooks, :pid}, self())
      Application.put_env(:gamend_core, :hooks_module, MidMatchHooks)

      on_exit(fn ->
        Application.put_env(:gamend_core, :hooks_module, original)
        :persistent_term.erase({MidMatchHooks, :pid})
      end)

      {:ok, party} = Parties.create_party(leader, %{max_size: 4})
      add_member_to_party(member1, party)
      set_all_online([leader, member1])
      %{party: party}
    end

    test "is asked for every member, and a refusal keeps the party out", %{
      leader: leader,
      member1: member1,
      party: party
    } do
      host = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
      {:ok, lobby} = Lobbies.create_lobby(%{title: "mid-match", host_id: host.id})

      assert {:error, {:hook_rejected, :mid_match}} =
               Parties.join_lobby_with_party(leader, lobby.id)

      assert_received {:asked, _first, party_id}
      assert party_id == party.id
      assert Accounts.get_user(leader.id).lobby_id == nil
      assert Accounts.get_user(member1.id).lobby_id == nil

      other_host = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
      {:ok, open} = Lobbies.create_lobby(%{title: "open", host_id: other_host.id, max_users: 8})
      flush_asked()
      assert {:ok, _} = Parties.join_lobby_with_party(leader, open.id)
      assert Enum.sort(asked()) == Enum.sort([leader.id, member1.id])
    end

    test "is asked for each member who joins the party's new lobby, not its creator", %{
      leader: leader,
      member1: member1
    } do
      assert {:error, {:hook_rejected, :mid_match}} =
               Parties.create_lobby_with_party(leader, %{"title" => "mid-match"})

      assert asked() == [member1.id]
      assert Accounts.get_user(leader.id).lobby_id == nil
      refute Gamend.Repo.get_by(Lobby, title: "mid-match")
    end

    test "a quick join passes over a lobby the game refuses", %{leader: leader, member1: member1} do
      host = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
      {:ok, refused} = Lobbies.create_lobby(%{title: "mid-match", host_id: host.id, max_users: 6})

      assert {:ok, lobby} = Parties.quick_join_with_party(leader, %{max_users: 6})
      assert lobby.id != refused.id
      assert Accounts.get_user(member1.id).lobby_id == lobby.id
    end

    defp asked(acc \\ []) do
      receive do
        {:asked, user_id, _party_id} -> asked([user_id | acc])
      after
        0 -> Enum.reverse(acc)
      end
    end

    defp flush_asked, do: asked()
  end

  describe "a quick join past a lobby with a block" do
    test "the party takes another lobby", %{leader: leader, member1: member1} do
      {:ok, party} = Parties.create_party(leader, %{max_size: 4})
      add_member_to_party(member1, party)
      set_all_online([leader, member1])

      blocker = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()

      {:ok, blocked_lobby} =
        Lobbies.create_lobby(%{title: "qj-block", host_id: blocker.id, max_users: 6})

      {:ok, _} = Friends.block_user(blocker, member1.id)

      assert {:ok, lobby} = Parties.quick_join_with_party(leader, %{max_users: 6})
      assert lobby.id != blocked_lobby.id
      assert Accounts.get_user(member1.id).lobby_id == lobby.id
    end

    test "a player alone takes another lobby, not a 403", %{leader: player} do
      blocker = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()

      {:ok, blocked_lobby} =
        Lobbies.create_lobby(%{title: "qj-solo-block", host_id: blocker.id, max_users: 7})

      {:ok, _} = Friends.block_user(player, blocker.id)

      assert {:ok, lobby} = Lobbies.quick_join(player, nil, 7, %{})
      assert lobby.id != blocked_lobby.id
    end
  end

  describe "atomicity of lobby operations" do
    test "create_lobby_with_party: party stays intact and all members are in lobby", %{
      leader: leader,
      member1: member1,
      member2: member2
    } do
      {:ok, party} = Parties.create_party(leader, %{max_size: 4})
      add_member_to_party(member1, party)
      add_member_to_party(member2, party)
      set_all_online([leader, member1, member2])

      {:ok, lobby} =
        Parties.create_lobby_with_party(leader, %{title: "atomic-lobby", max_users: 8})

      # All 3 users should be in the lobby and still in the party
      for user <- [leader, member1, member2] do
        u = Accounts.get_user(user.id)
        assert u.lobby_id == lobby.id, "User #{user.id} should be in the lobby"
        assert u.party_id == party.id, "User #{user.id} should still be in the party"
      end

      # Party should still exist
      assert Parties.get_party(party.id) != nil

      # Lobby should have 3 members
      members_in_lobby =
        Gamend.Repo.all(
          Ecto.Query.from(u in Gamend.Accounts.User,
            where: u.lobby_id == ^lobby.id
          )
        )

      assert length(members_in_lobby) == 3
    end

    test "join_lobby_with_party: party stays intact and all members are in lobby", %{
      leader: leader,
      member1: member1,
      member2: member2
    } do
      {:ok, party} = Parties.create_party(leader, %{max_size: 4})
      add_member_to_party(member1, party)
      add_member_to_party(member2, party)
      set_all_online([leader, member1, member2])

      host = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
      {:ok, lobby} = Lobbies.create_lobby(%{title: "existing", host_id: host.id, max_users: 10})

      {:ok, joined_lobby} = Parties.join_lobby_with_party(leader, lobby.id)
      assert joined_lobby.id == lobby.id

      # All 3 party members should be in the lobby and still in the party
      for user <- [leader, member1, member2] do
        u = Accounts.get_user(user.id)
        assert u.lobby_id == lobby.id, "User #{user.id} should be in the lobby"
        assert u.party_id == party.id, "User #{user.id} should still be in the party"
      end

      # Party should still exist
      assert Parties.get_party(party.id) != nil

      # Lobby should have 4 members (host + 3 party members)
      members_in_lobby =
        Gamend.Repo.all(
          Ecto.Query.from(u in Gamend.Accounts.User,
            where: u.lobby_id == ^lobby.id
          )
        )

      assert length(members_in_lobby) == 4
    end

    test "join_lobby_with_party: party still exists after failed password", %{
      leader: leader,
      member1: member1
    } do
      {:ok, party} = Parties.create_party(leader, %{})
      add_member_to_party(member1, party)
      set_all_online([leader, member1])

      host = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
      phash = Bcrypt.hash_pwd_salt("secret")

      {:ok, lobby} =
        Lobbies.create_lobby(%{
          title: "pw-lobby",
          host_id: host.id,
          password_hash: phash,
          max_users: 8
        })

      assert {:error, :password_required} = Parties.join_lobby_with_party(leader, lobby.id)

      # Party and membership should still be intact
      assert Parties.get_party(party.id) != nil
      assert Accounts.get_user(leader.id).party_id == party.id
      assert Accounts.get_user(member1.id).party_id == party.id
      assert is_nil(Accounts.get_user(leader.id).lobby_id)
      assert is_nil(Accounts.get_user(member1.id).lobby_id)
    end

    test "create_lobby_with_party: party_ids restored when lobby creation fails", %{
      leader: leader,
      member1: member1
    } do
      {:ok, party} = Parties.create_party(leader, %{max_size: 4})
      add_member_to_party(member1, party)
      set_all_online([leader, member1])

      # Create a lobby with the same title to cause a conflict
      # (titles need not be unique per se, but let's test with an invalid
      # max_users to force a changeset error)
      assert {:error, _} =
               Parties.create_lobby_with_party(leader, %{title: "err-lobby", max_users: 0})

      # Party should still exist
      assert Parties.get_party(party.id) != nil

      # Users should have party_id restored (not nil and not in a lobby)
      leader_fresh = Accounts.get_user(leader.id)
      member1_fresh = Accounts.get_user(member1.id)

      assert leader_fresh.party_id == party.id
      assert member1_fresh.party_id == party.id
      assert is_nil(leader_fresh.lobby_id)
      assert is_nil(member1_fresh.lobby_id)
    end
  end

  describe "PubSub events" do
    test "party_member_joined event is broadcast when invite accepted", %{
      leader: leader,
      member1: member1
    } do
      {:ok, party} = Parties.create_party(leader, %{})
      make_friends(leader, member1)
      {:ok, _} = Parties.invite_to_party(leader, member1.id)
      Parties.subscribe_party(party.id)

      {:ok, _} = Parties.accept_party_invite(member1, party.id)

      party_id = party.id
      member_id = member1.id
      assert_receive {:party_member_joined, ^party_id, ^member_id}, 500
    end

    test "party_member_left event is broadcast when member leaves", %{
      leader: leader,
      member1: member1
    } do
      {:ok, party} = Parties.create_party(leader, %{})
      add_member_to_party(member1, party)
      Parties.subscribe_party(party.id)

      {:ok, :left} = Parties.leave_party(member1)

      party_id = party.id
      member_id = member1.id
      assert_receive {:party_member_left, ^party_id, ^member_id}, 500
    end

    test "party_disbanded event is broadcast when the last member leaves", %{
      leader: leader
    } do
      {:ok, party} = Parties.create_party(leader, %{})
      Parties.subscribe_party(party.id)

      {:ok, :disbanded} = Parties.leave_party(leader)

      party_id = party.id
      assert_receive {:party_disbanded, ^party_id}, 500
    end

    test "party_updated event is broadcast on update", %{leader: leader} do
      {:ok, party} = Parties.create_party(leader, %{max_size: 4})
      Parties.subscribe_party(party.id)

      {:ok, _} = Parties.update_party(leader, %{max_size: 8})

      assert_receive {:party_updated, updated_party}, 500
      assert updated_party.max_size == 8
    end

    test "party_member_left event is broadcast on kick", %{leader: leader, member1: member1} do
      {:ok, party} = Parties.create_party(leader, %{})
      add_member_to_party(member1, party)
      Parties.subscribe_party(party.id)

      {:ok, _} = Parties.kick_member(leader, member1.id)

      party_id = party.id
      member_id = member1.id
      assert_receive {:party_member_left, ^party_id, ^member_id}, 500
    end
  end

  describe "user deletion edge cases" do
    test "deleting a party leader hands the party to the remaining member", %{
      leader: leader,
      member1: member1
    } do
      {:ok, party} = Parties.create_party(leader, %{max_size: 4})
      add_member_to_party(member1, party)

      # Delete the leader
      {:ok, _} = Accounts.delete_user(leader)

      # The account going does not take everyone else's party with it.
      assert Parties.get_party(party.id).leader_id == member1.id

      updated_member = Accounts.get_user(member1.id)
      assert updated_member.party_id == party.id
    end

    test "deleting a regular member removes them from the party", %{
      leader: leader,
      member1: member1
    } do
      {:ok, party} = Parties.create_party(leader, %{max_size: 4})
      add_member_to_party(member1, party)

      # Delete the member
      {:ok, _} = Accounts.delete_user(member1)

      # Party should still exist with leader
      remaining_party = Parties.get_party(party.id)
      assert remaining_party != nil
      assert remaining_party.leader_id == leader.id
    end
  end

  # ---------------------------------------------------------------------------
  # Sent party invitations
  # ---------------------------------------------------------------------------

  describe "list_sent_party_invitations/1" do
    test "returns invitations sent by leader", %{leader: leader, member1: member1} do
      {:ok, party} = Parties.create_party(leader, %{max_size: 4})
      make_friends(leader, member1)
      {:ok, _} = Parties.invite_to_party(leader, member1.id)

      invites = Parties.list_sent_party_invitations(leader)
      assert length(invites) == 1
      invite = hd(invites)
      assert invite.party_id == party.id
      assert invite.recipient_id == member1.id
    end

    test "includes sender_name and recipient_name", %{leader: leader, member1: member1} do
      {:ok, _} =
        Gamend.Accounts.update_user_display_name(leader, %{"display_name" => "SentLeader"})

      {:ok, _} =
        Gamend.Accounts.update_user_display_name(member1, %{"display_name" => "SentMember"})

      {:ok, _party} = Parties.create_party(leader, %{max_size: 4})
      make_friends(leader, member1)
      {:ok, _} = Parties.invite_to_party(leader, member1.id)

      invites = Parties.list_sent_party_invitations(leader)
      assert length(invites) == 1
      invite = hd(invites)
      assert invite.sender_name == "SentLeader"
      assert invite.recipient_name == "SentMember"
    end

    test "returns empty when no invitations sent", %{member1: member1} do
      assert Parties.list_sent_party_invitations(member1) == []
    end
  end

  # ---------------------------------------------------------------------------
  # Party hooks
  # ---------------------------------------------------------------------------

  describe "before_party_create hook" do
    setup do
      original = Application.get_env(:gamend_core, :hooks_module)

      on_exit(fn ->
        if original do
          Application.put_env(:gamend_core, :hooks_module, original)
        else
          Application.delete_env(:gamend_core, :hooks_module)
        end
      end)

      :ok
    end

    test "allows create when hook returns {:ok, attrs}", %{leader: leader} do
      Application.put_env(
        :gamend_core,
        :hooks_module,
        Gamend.PartiesTest.HooksAllowPartyCreate
      )

      assert {:ok, party} = Parties.create_party(leader, %{max_size: 4})
      assert party.leader_id == leader.id
    end

    test "blocks create when hook returns {:error, reason}", %{leader: leader} do
      Application.put_env(
        :gamend_core,
        :hooks_module,
        Gamend.PartiesTest.HooksDenyPartyCreate
      )

      assert {:error, {:hook_rejected, :party_creation_blocked}} =
               Parties.create_party(leader, %{max_size: 4})
    end

    test "hook can modify attrs before create", %{leader: leader} do
      Application.put_env(
        :gamend_core,
        :hooks_module,
        Gamend.PartiesTest.HooksModifyPartyCreate
      )

      assert {:ok, party} = Parties.create_party(leader, %{max_size: 10})
      assert party.max_size == 3
    end
  end

  describe "before_party_update hook" do
    setup do
      original = Application.get_env(:gamend_core, :hooks_module)

      on_exit(fn ->
        if original do
          Application.put_env(:gamend_core, :hooks_module, original)
        else
          Application.delete_env(:gamend_core, :hooks_module)
        end
      end)

      :ok
    end

    test "allows update when hook returns {:ok, attrs}", %{leader: leader} do
      {:ok, _party} = Parties.create_party(leader, %{max_size: 4})

      Application.put_env(
        :gamend_core,
        :hooks_module,
        Gamend.PartiesTest.HooksAllowPartyUpdate
      )

      assert {:ok, updated} = Parties.update_party(leader, %{"max_size" => 6})
      assert updated.max_size == 6
    end

    test "blocks update when hook returns {:error, reason}", %{leader: leader} do
      {:ok, _party} = Parties.create_party(leader, %{max_size: 4})

      Application.put_env(
        :gamend_core,
        :hooks_module,
        Gamend.PartiesTest.HooksDenyPartyUpdate
      )

      assert {:error, {:hook_rejected, :party_update_blocked}} =
               Parties.update_party(leader, %{"max_size" => 6})
    end

    test "hook can modify attrs before update", %{leader: leader} do
      {:ok, _party} = Parties.create_party(leader, %{max_size: 4})

      Application.put_env(
        :gamend_core,
        :hooks_module,
        Gamend.PartiesTest.HooksModifyPartyUpdate
      )

      assert {:ok, updated} = Parties.update_party(leader, %{"max_size" => 10})
      assert updated.max_size == 5
    end
  end

  describe "after_party_join hook" do
    test "fires after invite accept without breaking the flow", %{
      leader: leader,
      member1: member1
    } do
      make_friends(leader, member1)
      {:ok, party} = Parties.create_party(leader, %{})
      {:ok, _invite} = Parties.invite_to_party(leader, member1.id)

      assert {:ok, _party} = Parties.accept_party_invite(member1, party.id)
      updated = Accounts.get_user(member1.id)
      assert updated.party_id == party.id
    end
  end

  describe "after_party_leave hook" do
    test "fires after leave without breaking the flow", %{leader: leader, member1: member1} do
      make_friends(leader, member1)
      {:ok, party} = Parties.create_party(leader, %{})
      {:ok, _invite} = Parties.invite_to_party(leader, member1.id)
      {:ok, _} = Parties.accept_party_invite(member1, party.id)

      assert {:ok, :left} = Parties.leave_party(member1)
      updated = Accounts.get_user(member1.id)
      assert is_nil(updated.party_id)
    end
  end

  describe "after_party_kick hook" do
    test "fires after kick without breaking the flow", %{leader: leader, member1: member1} do
      make_friends(leader, member1)
      {:ok, party} = Parties.create_party(leader, %{})
      {:ok, _invite} = Parties.invite_to_party(leader, member1.id)
      {:ok, _} = Parties.accept_party_invite(member1, party.id)

      assert {:ok, _} = Parties.kick_member(leader, member1.id)
      updated = Accounts.get_user(member1.id)
      assert is_nil(updated.party_id)
    end
  end

  describe "after_party_disband hook" do
    test "fires after disband without breaking the flow", %{leader: leader, member1: member1} do
      make_friends(leader, member1)
      {:ok, party} = Parties.create_party(leader, %{})
      {:ok, _invite} = Parties.invite_to_party(leader, member1.id)
      {:ok, _} = Parties.accept_party_invite(member1, party.id)

      # Both out: the second leaves nobody to hand the party to, so it disbands.
      assert {:ok, :left} = Parties.leave_party(member1)
      assert {:ok, :disbanded} = Parties.leave_party(leader)
      updated_leader = Accounts.get_user(leader.id)
      assert is_nil(updated_leader.party_id)
    end
  end

  describe "the leader leaving while a member acts on the party they read" do
    test "a member handed the party as they leave disbands it rather than leaving it led by nobody",
         %{leader: leader, member1: member1} do
      {:ok, party} = Parties.create_party(leader, %{max_size: 4})
      add_member_to_party(member1, party)

      result =
        vanish_after(
          &(&1[:source] == "parties"),
          fn -> {:ok, :left} = Parties.leave_party(leader) end,
          fn -> Parties.leave_party(member1) end
        )

      assert Process.get(:vanished)
      assert result == {:ok, :disbanded}
      refute Repo.get(Party, party.id)
      assert Repo.get(Accounts.User, member1.id).party_id == nil
    end

    test "a kick landing after the leader handed the party to its target answers not_leader",
         %{leader: leader, member1: member1} do
      {:ok, party} = Parties.create_party(leader, %{max_size: 4})
      add_member_to_party(member1, party)

      result =
        vanish_after(
          &(&1[:source] == "parties"),
          fn -> {:ok, :left} = Parties.leave_party(leader) end,
          fn -> Parties.kick_member(leader, member1.id) end
        )

      assert Process.get(:vanished)
      assert result == {:error, :not_leader}
      assert Repo.get!(Party, party.id).leader_id == member1.id
      assert Repo.get(Accounts.User, member1.id).party_id == party.id
    end
  end

  describe "a parent deleted between its read and the write" do
    test "accepting an invite to a party deleted as the join reads it leaves the joiner out", %{
      leader: leader,
      member1: member1
    } do
      {:ok, party} = Parties.create_party(leader, %{max_size: 4})
      make_friends(leader, member1)
      {:ok, _} = Parties.invite_to_party(leader, member1.id)

      # The read inside the join's lock: the delete joins that transaction and
      # rolls back with it, so only the answer is asserted.
      result =
        vanish_after(
          &(&1[:source] == "parties" and Repo.in_transaction?()),
          fn -> delete_party(party.id) end,
          fn -> Parties.accept_party_invite(member1, party.id) end
        )

      assert Process.get(:vanished)
      assert result == {:error, :not_found}
      assert Repo.get(Accounts.User, member1.id).party_id == nil
    end

    test "inviting into a party deleted after it was read answers not_found and writes no invite",
         %{leader: leader, member1: member1} do
      {:ok, party} = Parties.create_party(leader, %{max_size: 4})
      make_friends(leader, member1)

      result =
        vanish_after(
          &(&1[:source] == "party_invites"),
          fn -> delete_party(party.id) end,
          fn -> Parties.invite_to_party(leader, member1.id) end
        )

      assert Process.get(:vanished)
      assert result == {:error, :not_found}
      refute Repo.exists?(from i in PartyInvite, where: i.recipient_id == ^member1.id)
    end

    @tag :capture_log
    test "a party joining a lobby deleted after it was read answers not_found and seats nobody",
         %{leader: leader, member1: member1} do
      {:ok, party} = Parties.create_party(leader, %{max_size: 4})
      add_member_to_party(member1, party)
      set_all_online([leader, member1])
      host = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()
      {:ok, lobby} = Lobbies.create_lobby(%{title: "doomed-lobby", host_id: host.id})

      result =
        vanish_after(
          &(&1[:source] == "lobbies"),
          fn -> delete_lobby(lobby.id) end,
          fn -> Parties.join_lobby_with_party(leader, lobby.id) end
        )

      assert Process.get(:vanished)
      assert result == {:error, :not_found}
      refute Repo.exists?(from u in Accounts.User, where: u.lobby_id == ^lobby.id)
      assert Repo.get(Accounts.User, leader.id).lobby_id == nil
      assert Repo.get(Accounts.User, member1.id).lobby_id == nil
    end

    @tag :capture_log
    test "a party quick join moves past a candidate disbanded as it joins", %{
      leader: leader,
      member1: member1
    } do
      {:ok, party} = Parties.create_party(leader, %{max_size: 4})
      add_member_to_party(member1, party)
      set_all_online([leader, member1])
      host = AccountsFixtures.user_fixture() |> AccountsFixtures.set_password()

      {:ok, vanishing} =
        Lobbies.create_lobby(%{title: "vanishing-room", host_id: host.id, max_users: 4})

      # The candidate query is the first read of lobbies.
      result =
        vanish_after(
          &(&1[:source] == "lobbies"),
          fn -> delete_lobby(vanishing.id) end,
          fn -> Parties.quick_join_with_party(leader, %{max_users: 4}) end
        )

      assert Process.get(:vanished)
      assert {:ok, fresh} = result
      refute fresh.id == vanishing.id
      assert Repo.get(Accounts.User, leader.id).lobby_id == fresh.id
      assert Repo.get(Accounts.User, member1.id).lobby_id == fresh.id
    end

    test "disbanding clears every member and the party's chat, and a second disband answers",
         %{leader: leader, member1: member1, member2: member2} do
      {:ok, party} = Parties.create_party(leader, %{max_size: 4})
      add_member_to_party(member1, party)
      add_member_to_party(member2, party)
      post_party_message(leader, party)
      assert party_chat(party.id) == 1

      assert Parties.disband(party) == {:ok, :disbanded}

      refute Repo.exists?(from u in Accounts.User, where: u.party_id == ^party.id)
      assert party_chat(party.id) == 0
      assert Parties.disband(party) == {:ok, :disbanded}
    end

    test "an admin delete clears every member and the party's chat, and a second answers not_found",
         %{leader: leader, member1: member1, member2: member2} do
      {:ok, party} = Parties.create_party(leader, %{max_size: 4})
      add_member_to_party(member1, party)
      add_member_to_party(member2, party)
      post_party_message(member1, party)
      assert party_chat(party.id) == 1

      assert {:ok, %Party{id: id}} = Parties.admin_delete_party(party.id)
      assert id == party.id

      refute Repo.exists?(from u in Accounts.User, where: u.party_id == ^party.id)
      assert party_chat(party.id) == 0
      assert Parties.admin_delete_party(party.id) == {:error, :not_found}
    end
  end

  # Runs `fun`, deleting a row with `vanish` the first time this process runs a
  # query `picks?` matches.
  defp vanish_after(picks?, vanish, fun) do
    pid = self()
    handler = {__MODULE__, :vanish_after, System.unique_integer()}

    :telemetry.attach(
      handler,
      [:gamend, :repo, :query],
      fn _event, _measurements, meta, _config ->
        if self() == pid and !Process.get(:vanished) and picks?.(meta) do
          Process.put(:vanished, true)
          vanish.()
        end
      end,
      nil
    )

    try do
      fun.()
    after
      :telemetry.detach(handler)
    end
  end

  defp delete_party(party_id), do: Repo.delete_all(from p in Party, where: p.id == ^party_id)
  defp delete_lobby(lobby_id), do: Repo.delete_all(from l in Lobby, where: l.id == ^lobby_id)

  defp party_chat(party_id) do
    Repo.aggregate(
      from(m in Message, where: m.chat_type == "party" and m.chat_ref_id == ^party_id),
      :count
    )
  end

  defp post_party_message(sender, party) do
    %Message{sender_id: sender.id}
    |> Message.changeset(%{chat_type: "party", chat_ref_id: party.id, content: "gg"})
    |> Repo.insert!()
  end
end
