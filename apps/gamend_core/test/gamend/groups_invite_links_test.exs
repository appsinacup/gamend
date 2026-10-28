defmodule Gamend.GroupsInviteLinksTest do
  # A group's invite link (`Gamend.Groups.InviteLinks`): an admin makes one,
  # anyone who opens it joins as a member; a new one replaces it, and it
  # stops working when turned off, expired, or its maker is no longer an
  # admin. `link_days` 0 turns links off.
  use Gamend.DataCase, async: false

  import Ecto.Query

  alias Gamend.AccountsFixtures
  alias Gamend.Groups
  alias Gamend.Groups.GroupInviteLink
  alias Gamend.Repo

  setup do
    previous = Application.get_env(:gamend_core, Groups, [])
    on_exit(fn -> Application.put_env(:gamend_core, Groups, previous) end)

    owner = AccountsFixtures.user_fixture()
    title = "crew-#{System.unique_integer([:positive])}"
    {:ok, group} = Groups.create_group(owner.id, %{"title" => title, "type" => "hidden"})

    %{owner: owner, other: AccountsFixtures.user_fixture(), group: group}
  end

  test "an admin makes a link, and whoever opens it joins as a member", %{
    owner: owner,
    other: other,
    group: group
  } do
    assert Groups.invite_links?()
    assert Groups.get_invite_link(group.id) == nil

    assert {:ok, link} = Groups.create_invite_link(owner.id, group.id)
    assert DateTime.diff(link.expires_at, DateTime.utc_now(), :day) in 6..7
    assert Groups.get_invite_link_by_token(link.token).group.id == group.id

    assert {:ok, %{role: "member"}} = Groups.join_by_invite_link(other.id, link.token)
    assert Groups.member?(group.id, other.id)
    assert Groups.get_invite_link(group.id).uses == 1
    assert {:error, :already_member} = Groups.join_by_invite_link(other.id, link.token)
  end

  test "only an admin makes or turns off a link", %{other: other, group: group} do
    assert {:error, :not_admin} = Groups.create_invite_link(other.id, group.id)
    assert {:error, :not_admin} = Groups.delete_invite_link(other.id, group.id)
  end

  test "a new link replaces the old one, and a turned-off one opens nothing", %{
    owner: owner,
    other: other,
    group: group
  } do
    {:ok, old} = Groups.create_invite_link(owner.id, group.id)
    {:ok, new} = Groups.create_invite_link(owner.id, group.id)

    refute new.token == old.token
    assert {:error, :not_found} = Groups.join_by_invite_link(other.id, old.token)
    assert Groups.get_invite_link(group.id).token == new.token

    assert :ok = Groups.delete_invite_link(owner.id, group.id)
    assert Groups.get_invite_link(group.id) == nil
    assert {:error, :not_found} = Groups.join_by_invite_link(other.id, new.token)
  end

  test "an expired link, and one whose maker left, open nothing", %{
    owner: owner,
    other: other,
    group: group
  } do
    {:ok, link} = Groups.create_invite_link(owner.id, group.id)
    past = DateTime.add(DateTime.utc_now(:second), -1, :day)
    Repo.update_all(where(GroupInviteLink, id: ^link.id), set: [expires_at: past])
    assert {:error, :not_found} = Groups.join_by_invite_link(other.id, link.token)

    {:ok, link} = Groups.create_invite_link(owner.id, group.id)
    {:ok, _member} = Groups.join_by_invite_link(other.id, link.token)
    {:ok, _left} = Groups.leave_group(owner.id, group.id)

    late = AccountsFixtures.user_fixture()
    assert Groups.get_invite_link_by_token(link.token) == nil
    assert {:error, :not_found} = Groups.join_by_invite_link(late.id, link.token)
  end

  test "a full group takes nobody through its link", %{owner: owner, other: other} do
    {:ok, group} =
      Groups.create_group(owner.id, %{
        "title" => "full-#{System.unique_integer([:positive])}",
        "max_members" => 1
      })

    {:ok, link} = Groups.create_invite_link(owner.id, group.id)
    assert {:error, :full} = Groups.join_by_invite_link(other.id, link.token)
  end

  test "link_days 0 turns links off", %{owner: owner, other: other, group: group} do
    {:ok, link} = Groups.create_invite_link(owner.id, group.id)

    Application.put_env(
      :gamend_core,
      Groups,
      Keyword.put(Application.get_env(:gamend_core, Groups, []), :link_days, 0)
    )

    refute Groups.invite_links?()
    assert {:error, :links_off} = Groups.create_invite_link(owner.id, group.id)
    assert Groups.get_invite_link(group.id) == nil
    assert {:error, :not_found} = Groups.join_by_invite_link(other.id, link.token)
  end
end
