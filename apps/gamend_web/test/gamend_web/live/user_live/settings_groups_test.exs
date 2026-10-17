defmodule GamendWeb.UserLive.SettingsGroupsTest do
  # The settings page's Groups tab (`UserLive.Settings.GroupsTab`): a group
  # created from the form (and refused when invalid), groups browsed and
  # filtered, a public one joined and left, a private one asked to join (the
  # request cancelled, or approved or rejected by its admin), an invite sent
  # from the member search and accepted, declined or cancelled, and a group's
  # members promoted, demoted and kicked by its admin, who edits it.
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gamend.Accounts
  alias Gamend.AccountsFixtures
  alias Gamend.Friends
  alias Gamend.Groups

  setup do
    # The first account is the site's admin; the players here are not.
    _first = AccountsFixtures.user_fixture()
    %{user: AccountsFixtures.user_fixture(), other: AccountsFixtures.user_fixture()}
  end

  defp page(conn, user, query \\ "") do
    {:ok, view, _html} = conn |> log_in_user(user) |> live("/users/settings?tab=groups" <> query)
    view
  end

  defp assigns(view), do: :sys.get_state(view.pid).socket.assigns
  defp flash(view, key), do: Phoenix.Flash.get(assigns(view).flash, key)
  defp member?(group, user), do: Groups.get_membership(group.id, user.id) != nil

  # An invite goes only to a friend.
  defp friends!(a, b) do
    {:ok, request} = Friends.create_request(a, b.id)
    {:ok, _} = Friends.accept_friend_request(request.id, b)
  end

  defp group(owner, attrs \\ %{}) do
    {:ok, group} =
      Groups.create_group(
        owner.id,
        Map.merge(%{"title" => "crew-#{System.unique_integer([:positive])}"}, attrs)
      )

    group
  end

  test "a group is created from the form; an invalid one is refused", %{conn: conn, user: user} do
    view = page(conn, user)
    render_click(view, "groups_toggle_create", %{})
    assert assigns(view).groups_show_create

    render_change(view, "group_validate_create", %{"group" => %{"title" => ""}})
    refute assigns(view).create_group_form.source.valid?

    render_submit(view, "group_create", %{"group" => %{"title" => "", "type" => "public"}})
    assert flash(view, :error) == "Failed"

    render_submit(view, "group_create", %{"group" => %{"title" => "Sailors", "type" => "public"}})
    assert [{%{title: "Sailors"}, "admin"}] = assigns(view).my_groups
    refute assigns(view).groups_show_create
  end

  test "groups are browsed, filtered by title and type, and the filter cleared", %{
    conn: conn,
    user: user,
    other: other
  } do
    group(other, %{"title" => "Romanian learners", "type" => "public"})
    group(other, %{"title" => "Quiet room", "type" => "private"})
    view = page(conn, user)
    render_click(view, "groups_tab", %{"tab" => "browse"})
    assert assigns(view).groups_tab == "browse"

    render_change(view, "browse_groups_filter", %{
      "browse_groups" => %{"title" => " Romanian ", "type" => "public"}
    })

    assert assigns(view).browse_groups_filters == %{"title" => "Romanian", "type" => "public"}
    assert assigns(view).browse_groups_total == 1

    render_click(view, "browse_groups_next", %{})
    render_click(view, "browse_groups_prev", %{})
    render_click(view, "browse_groups_clear", %{})
    assert assigns(view).browse_groups_filters == %{}
    assert assigns(view).browse_groups_total >= 2
  end

  test "a public group is joined and left; leaving one not joined is refused", %{
    conn: conn,
    user: user,
    other: other
  } do
    public = group(other)
    view = page(conn, user)

    render_click(view, "group_join", %{"group_id" => public.id})
    assert member?(public, user)
    assert flash(view, :info)

    render_click(view, "group_leave", %{"group_id" => public.id})
    refute member?(public, user)

    render_click(view, "group_leave", %{"group_id" => public.id})
    assert flash(view, :error)

    render_click(view, "group_join", %{"group_id" => Ecto.UUID.generate()})
    assert flash(view, :error)
  end

  test "a private group's request is cancelled by its sender, or rejected", %{
    conn: conn,
    user: user,
    other: other
  } do
    private = group(other, %{"type" => "private"})
    view = page(conn, user)

    render_click(view, "group_request_join", %{"group_id" => private.id})
    assert [request] = assigns(view).group_pending_requests
    render_click(view, "group_cancel_request", %{"request_id" => request.id})
    assert assigns(view).group_pending_requests == []

    render_click(view, "group_cancel_request", %{"request_id" => Ecto.UUID.generate()})
    assert flash(view, :error)

    {:ok, request} = Groups.request_join(user.id, private.id)
    admin_view = page(conn, other, "&group=#{private.id}")
    render_click(admin_view, "group_reject_request", %{"request_id" => request.id})
    refute member?(private, user)
  end

  test "an admin approves a request from the group's page", %{
    conn: conn,
    user: user,
    other: other
  } do
    private = group(other, %{"type" => "private"})
    {:ok, request} = Groups.request_join(user.id, private.id)

    view = page(conn, other, "&group=#{private.id}")
    assert assigns(view).group_detail.id == private.id
    render_click(view, "group_approve_request", %{"request_id" => request.id})
    assert member?(private, user)

    render_click(view, "group_approve_request", %{"request_id" => request.id})
    assert flash(view, :error)
    render_click(view, "group_reject_request", %{"request_id" => Ecto.UUID.generate()})
    assert flash(view, :error)
  end

  test "an invite found from the search is sent, then accepted", %{
    conn: conn,
    user: user,
    other: other
  } do
    mine = group(other)
    friends!(other, user)
    {:ok, _} = Accounts.update_user_display_name(user, %{"display_name" => "InviteMe"})
    view = page(conn, other, "&group=#{mine.id}")

    render_click(view, "group_invite_search", %{"value" => "  "})
    assert assigns(view).invite_search_results == []

    render_click(view, "group_invite_search", %{"value" => "InviteMe"})
    assert Enum.any?(assigns(view).invite_search_results, &(&1.id == user.id))

    render_click(view, "group_invite_user", %{"group_id" => mine.id, "user_id" => user.id})
    refute Enum.any?(assigns(view).invite_search_results, &(&1.id == user.id))
    # Inviting again replaces the invite rather than adding a second.
    render_click(view, "group_invite_user", %{"group_id" => mine.id, "user_id" => user.id})
    assert length(Groups.list_invitations(user.id)) == 1

    # Someone who is no friend cannot be invited.
    stranger = AccountsFixtures.user_fixture()
    render_click(view, "group_invite_user", %{"group_id" => mine.id, "user_id" => stranger.id})
    assert flash(view, :error)

    invited = page(conn, user)
    assert [invite] = assigns(invited).group_invitations
    render_click(invited, "group_accept_invite", %{"invite_id" => invite.id})
    assert member?(mine, user)

    render_click(invited, "group_accept_invite", %{"invite_id" => invite.id})
    assert flash(invited, :error)
  end

  test "an invite is declined by the invited, or cancelled by its sender", %{
    conn: conn,
    user: user,
    other: other
  } do
    mine = group(other)
    friends!(other, user)
    {:ok, invite} = Groups.invite_to_group(other.id, mine.id, user.id)
    view = page(conn, user)
    render_click(view, "group_decline_invite", %{"invite_id" => invite.id})
    assert assigns(view).group_invitations == []
    render_click(view, "group_decline_invite", %{"invite_id" => invite.id})
    assert flash(view, :error)

    {:ok, invite} = Groups.invite_to_group(other.id, mine.id, user.id)
    sender = page(conn, other)
    assert [_] = assigns(sender).group_sent_invitations
    render_click(sender, "group_cancel_invite", %{"invite_id" => invite.id})
    assert assigns(sender).group_sent_invitations == []
    render_click(sender, "group_cancel_invite", %{"invite_id" => invite.id})
    assert flash(sender, :error)
  end

  test "the admin promotes, demotes and kicks a member, and edits the group", %{
    conn: conn,
    user: user,
    other: other
  } do
    mine = group(other)
    {:ok, _} = Groups.join_group(user.id, mine.id)
    view = page(conn, other)

    render_click(view, "group_view_detail", %{"group_id" => mine.id})
    assert assigns(view).group_detail.id == mine.id
    assert assigns(view).group_detail_role == "admin"

    render_click(view, "group_promote", %{"group_id" => mine.id, "user_id" => user.id})
    assert Groups.get_membership(mine.id, user.id).role == "admin"
    render_click(view, "group_demote", %{"group_id" => mine.id, "user_id" => user.id})
    assert Groups.get_membership(mine.id, user.id).role == "member"
    render_click(view, "group_members_next", %{})
    render_click(view, "group_members_prev", %{})

    render_click(view, "group_kick", %{"group_id" => mine.id, "user_id" => user.id})
    refute member?(mine, user)
    render_click(view, "group_kick", %{"group_id" => mine.id, "user_id" => user.id})
    assert flash(view, :error)
    render_click(view, "group_promote", %{"group_id" => mine.id, "user_id" => user.id})
    assert flash(view, :error)
    render_click(view, "group_demote", %{"group_id" => mine.id, "user_id" => user.id})
    assert flash(view, :error)

    render_click(view, "group_toggle_edit", %{})
    assert assigns(view).group_editing
    render_change(view, "group_validate_edit", %{"group" => %{"title" => ""}})
    refute assigns(view).group_edit_form.source.valid?
    render_submit(view, "group_save_edit", %{"group" => %{"title" => ""}})
    assert assigns(view).group_edit_form
    render_submit(view, "group_save_edit", %{"group" => %{"title" => "Renamed crew"}})
    assert Groups.get_group(mine.id).title == "Renamed crew"
    refute assigns(view).group_editing

    render_click(view, "group_close_detail", %{})
    assert assigns(view).group_detail == nil
  end

  test "a member who is not an admin cannot edit the group", %{
    conn: conn,
    user: user,
    other: other
  } do
    mine = group(other)
    {:ok, _} = Groups.join_group(user.id, mine.id)
    view = page(conn, user, "&group=#{mine.id}&edit=1")
    render_submit(view, "group_save_edit", %{"group" => %{"title" => "Mine now"}})
    refute Groups.get_group(mine.id).title == "Mine now"
  end

  test "the open group and its create form come back from the URL", %{conn: conn, other: other} do
    mine = group(other)
    view = page(conn, other, "&group=#{mine.id}&edit=1&create=1")
    assert assigns(view).group_detail.id == mine.id
    assert assigns(view).group_editing
    assert assigns(view).groups_show_create
  end
end
