defmodule GamendWeb.UserLive.GroupsPageTest.Host do
  @moduledoc false
  # A page with a form of its own, as Forge's and Gamend Cloud's, that
  # makes a team from `NewGroupComponent`.
  use GamendWeb, :live_view

  @impl true
  def mount(_params, %{"user_id" => user_id}, socket) do
    {:ok, assign(socket, user: %{id: user_id}, created: nil)}
  end

  @impl true
  def handle_info({GamendWeb.NewGroupComponent, {:created, group}}, socket),
    do: {:noreply, assign(socket, :created, group)}

  @impl true
  def render(assigns) do
    ~H"""
    <GamendWeb.NewGroupComponent.open_button target="#new-team" id="open-new-team" />
    <p :if={@created} id="created">{@created.title}</p>
    <.live_component module={GamendWeb.NewGroupComponent} id="new-team" user={@user} />
    """
  end
end

defmodule GamendWeb.UserLive.GroupsPageTest do
  # The groups as a page of their own (`UserLive.Groups`, Forge's and Gamend
  # Cloud's Groups) on a host whose groups are hidden only, anyone invited.
  # A team is made there and opened from its URL, a colleague found by their
  # exact email and invited; nothing offers a type, a listing or requests.
  # And `NewGroupComponent`, which makes one from another page's form.
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gamend.AccountsFixtures
  alias Gamend.Groups

  setup do
    previous = Application.get_env(:gamend_core, Groups, [])

    Application.put_env(
      :gamend_core,
      Groups,
      Keyword.merge(previous, types: ["hidden"], invites: :anyone)
    )

    on_exit(fn -> Application.put_env(:gamend_core, Groups, previous) end)

    # The first account is the site's admin; the people here are not.
    _first = AccountsFixtures.user_fixture()
    %{user: AccountsFixtures.user_fixture(), other: AccountsFixtures.user_fixture()}
  end

  defp assigns(view), do: :sys.get_state(view.pid).socket.assigns

  test "the page is the groups: no type, no listing, no requests", %{conn: conn, user: user} do
    {:ok, view, html} = conn |> log_in_user(user) |> live("/users/groups?create=1")

    assert html =~ "Groups"
    refute html =~ "Find groups"
    refute html =~ "My requests"
    assert has_element?(view, "#create-group-form")
    refute has_element?(view, "#create-group-form select[name='group[type]']")

    render_submit(view, "group_create", %{"group" => %{"title" => "Studio"}})
    assert [{%{title: "Studio", type: "hidden"}, "admin"}] = assigns(view).my_groups
    assert_patch(view, "/users/groups")
  end

  test "a fixed cap is not asked; the slug follows the title until typed into", %{
    conn: conn,
    user: user
  } do
    Application.put_env(
      :gamend_core,
      Groups,
      Keyword.merge(Application.get_env(:gamend_core, Groups), max_members: 100)
    )

    {:ok, view, _html} = conn |> log_in_user(user) |> live("/users/groups?create=1")
    refute has_element?(view, "#create-group-form input[name='group[max_members]']")

    render_change(view, "group_validate_create", %{"group" => %{"title" => "Big Studio"}})
    assert has_element?(view, "#create-group-form input[name='group[slug]'][value='big-studio']")

    render_change(view, "group_validate_create", %{
      "group" => %{"title" => "Big Studio 2", "slug" => "big-studio"}
    })

    assert has_element?(
             view,
             "#create-group-form input[name='group[slug]'][value='big-studio-2']"
           )

    render_change(view, "group_validate_create", %{
      "group" => %{"title" => "Big Studio 3", "slug" => "mine"}
    })

    assert has_element?(view, "#create-group-form input[name='group[slug]'][value='mine']")

    render_submit(view, "group_create", %{
      "group" => %{"title" => "Big Studio 3", "slug" => "mine"}
    })

    assert [{%{slug: "mine", max_members: 100}, "admin"}] = assigns(view).my_groups
  end

  test "a row opens its group, by slug in the URL; leaving is on the group's page", %{
    conn: conn,
    user: user
  } do
    {:ok, team} = Groups.create_group(user.id, %{"title" => "Studio"})
    {:ok, view, _html} = conn |> log_in_user(user) |> live("/users/groups")

    refute has_element?(view, "#my-group-#{team.id} button", "Leave")
    view |> element("#my-group-#{team.id} a") |> render_click()

    assert_patch(view, "/users/groups?" <> URI.encode_query(group: "#{user.username}/studio"))
    assert assigns(view).group_detail.id == team.id
    assert has_element?(view, "button[phx-click='group_leave']")
  end

  test "a team opens from its URL and a colleague is invited by email", %{
    conn: conn,
    user: user,
    other: other
  } do
    {:ok, team} = Groups.create_group(user.id, %{"title" => "Studio"})
    {:ok, view, _html} = conn |> log_in_user(user) |> live("/users/groups?group=#{team.id}")
    assert assigns(view).group_detail.id == team.id

    render_keyup(view, "group_invite_search", %{"value" => String.upcase(other.email)})
    assert [%{id: other_id}] = assigns(view).invite_search_results
    assert other_id == other.id

    render_click(view, "group_invite_user", %{"group_id" => team.id, "user_id" => other.id})
    assert [%{recipient_id: ^other_id}] = Groups.list_sent_invitations(user.id)
  end

  # The invitations tabs read the invite's `group_title`; they read a
  # `group_name` invites have not had since groups lost their name, and
  # crashed the page for anyone with an invite pending.
  test "the invited colleague sees the invite and accepts it", %{
    conn: conn,
    user: user,
    other: other
  } do
    {:ok, team} = Groups.create_group(user.id, %{"title" => "Studio"})
    {:ok, _invite} = Groups.invite_to_group(user.id, team.id, other.id)

    {:ok, view, _html} = conn |> log_in_user(user) |> live("/users/groups")

    assert view |> element("button[phx-value-tab='sent_invitations']") |> render_click() =~
             "Studio"

    {:ok, view, _html} = build_conn() |> log_in_user(other) |> live("/users/groups")
    html = view |> element("button[phx-value-tab='invitations']") |> render_click()
    assert html =~ "Studio"
    assert html =~ Gamend.Accounts.display_name(user)

    view |> element("button[phx-click='group_accept_invite']") |> render_click()
    assert Groups.member?(team.id, other.id)
  end

  test "an admin shares an invite link, and whoever opens it joins", %{
    conn: conn,
    user: user,
    other: other
  } do
    {:ok, team} = Groups.create_group(user.id, %{"title" => "Studio"})
    {:ok, view, _html} = conn |> log_in_user(user) |> live("/users/groups?group=#{team.id}")

    view |> element("#group-invite-link-create") |> render_click()
    %{token: token} = Groups.get_invite_link(team.id)
    url = view |> element("#group-invite-link-url") |> render()
    assert url =~ "/users/groups/join/#{token}"

    view |> element("#group-invite-link-new") |> render_click()
    %{token: new_token} = Groups.get_invite_link(team.id)
    refute new_token == token
    assert view |> element("#group-invite-link-url") |> render() =~ new_token

    {:ok, join, html} = build_conn() |> log_in_user(other) |> live("/users/groups/join/#{token}")
    assert html =~ "no longer works"
    refute html =~ "Studio"
    refute has_element?(join, "#group-join-button")

    {:ok, join, html} =
      build_conn() |> log_in_user(other) |> live("/users/groups/join/#{new_token}")

    assert html =~ "Studio"
    assert html =~ Gamend.Accounts.display_name(user)

    assert {:error, {:live_redirect, %{to: to}}} =
             join |> element("#group-join-button") |> render_click()

    assert to == "/users/groups?group=#{team.id}"
    assert Groups.member?(team.id, other.id)

    view |> element("#group-invite-link-off") |> render_click()
    assert Groups.get_invite_link(team.id) == nil
    assert has_element?(view, "#group-invite-link-create")
  end

  test "an invite link sends someone signed out to log in first", %{conn: conn, user: user} do
    {:ok, team} = Groups.create_group(user.id, %{"title" => "Studio"})
    {:ok, %{token: token}} = Groups.create_invite_link(user.id, team.id)

    assert {:error, {:redirect, %{to: to}}} = live(conn, "/users/groups/join/#{token}")
    assert to =~ "/users/log_in"
  end

  test "an admin sees the group's pending invites, the invited stay marked, and one is cancelled",
       %{conn: conn, user: user, other: other} do
    {:ok, team} = Groups.create_group(user.id, %{"title" => "Studio"})
    {:ok, view, _html} = conn |> log_in_user(user) |> live("/users/groups?group=#{team.id}")
    refute has_element?(view, "#group-pending-invites")

    render_keyup(view, "group_invite_search", %{"value" => other.email})
    render_click(view, "group_invite_user", %{"group_id" => team.id, "user_id" => other.id})

    # Still in the results, marked Invited, and listed under the group.
    assert [%{id: other_id}] = assigns(view).invite_search_results
    assert other_id == other.id
    assert render(view) =~ "Invited"

    refute has_element?(
             view,
             "button[phx-click='group_invite_user'][phx-value-user_id='#{other.id}']"
           )

    assert [%{id: invite_id}] = assigns(view).group_pending_invites
    assert has_element?(view, "#group-pending-invite-#{invite_id}")

    view |> element("#group-pending-invite-#{invite_id} button") |> render_click()
    refute has_element?(view, "#group-pending-invites")
    assert {:ok, []} = Groups.list_group_invites(user.id, team.id)
  end

  test "someone with an invite lands on Invitations, and on their groups once it is accepted",
       %{conn: conn, user: user, other: other} do
    {:ok, team} = Groups.create_group(user.id, %{"title" => "Studio"})
    {:ok, _invite} = Groups.invite_to_group(user.id, team.id, other.id)

    {:ok, view, html} = conn |> log_in_user(other) |> live("/users/groups")
    assert assigns(view).groups_tab == "invitations"
    assert html =~ "Studio"

    view |> element("button[phx-click='group_accept_invite']") |> render_click()
    assert assigns(view).groups_tab == "my_groups"
    assert Groups.member?(team.id, other.id)
  end

  test "a stranger's team does not open", %{conn: conn, user: user, other: other} do
    {:ok, team} = Groups.create_group(other.id, %{"title" => "Theirs"})
    {:ok, view, _html} = conn |> log_in_user(user) |> live("/users/groups?group=#{team.id}")
    assert assigns(view).group_detail == nil
  end

  test "the dialog makes a team and tells the page", %{conn: conn, user: user} do
    {:ok, view, _html} = live_isolated(conn, __MODULE__.Host, session: %{"user_id" => user.id})
    refute has_element?(view, "#new-team-form")

    view |> element("#open-new-team") |> render_click()
    assert has_element?(view, "#new-team-form")
    assert render(view) =~ "New group"

    view |> form("#new-team-form", group: %{title: ""}) |> render_submit()
    assert has_element?(view, "#new-team-form")

    view |> form("#new-team-form", group: %{title: "Night shift"}) |> render_submit()
    refute has_element?(view, "#new-team-form")
    assert view |> element("#created") |> render() =~ "Night shift"

    assert [{%{title: "Night shift", type: "hidden"}, "admin"}] =
             Groups.list_user_groups_with_role(user.id)
  end

  test "the dialog offers the types when the host allows more than one", %{
    conn: conn,
    user: user
  } do
    Application.put_env(
      :gamend_core,
      Groups,
      Keyword.put(Application.get_env(:gamend_core, Groups), :types, ["hidden", "private"])
    )

    {:ok, view, _html} = live_isolated(conn, __MODULE__.Host, session: %{"user_id" => user.id})
    view |> element("#open-new-team") |> render_click()

    assert has_element?(view, "#new-team-form select option[value='hidden'][selected]")
    assert render(view) =~ "people ask to join"
    refute has_element?(view, "#new-team-form option[value='public']")

    view
    |> form("#new-team-form", group: %{title: "Open studio", type: "private"})
    |> render_submit()

    assert [{%{title: "Open studio", type: "private"}, "admin"}] =
             Groups.list_user_groups_with_role(user.id)
  end
end
