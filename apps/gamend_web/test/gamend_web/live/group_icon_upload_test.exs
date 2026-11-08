defmodule GamendWeb.GroupIconUploadTest.Host do
  @moduledoc false
  # A page with the New group dialog, as Forge's and Gamend Cloud's: the
  # reader given by id only, as Forge's settings give it.
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
    <p :if={@created} id="created">{@created.icon_url}</p>
    <.live_component module={GamendWeb.NewGroupComponent} id="new-team" user={@user} />
    """
  end
end

defmodule GamendWeb.GroupIconUploadTest do
  # A group's icon as an image of one's own (`GamendWeb.GroupIconUpload`):
  # on the groups page, new and edit, and in the New group dialog; and an
  # icon of the site's in a colour of the site's.
  # async: false — the tests swap the global Storage.Local dir.
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gamend.AccountsFixtures
  alias Gamend.Groups

  @png <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13>>

  setup do
    dir = Path.join(System.tmp_dir!(), "gs_group_icon_#{System.unique_integer([:positive])}")
    old = Application.get_env(:gamend_core, Gamend.Storage.Local)
    Application.put_env(:gamend_core, Gamend.Storage.Local, dir: dir)

    on_exit(fn ->
      File.rm_rf(dir)

      if old,
        do: Application.put_env(:gamend_core, Gamend.Storage.Local, old),
        else: Application.delete_env(:gamend_core, Gamend.Storage.Local)
    end)

    # The first account is the site's admin; the people here are not.
    _first = AccountsFixtures.user_fixture()
    %{user: AccountsFixtures.user_fixture()}
  end

  defp png(name \\ "team.png"), do: [%{name: name, content: @png, type: "image/png"}]

  test "the dialog takes an image, the group's icon once it is made", %{conn: conn, user: user} do
    {:ok, view, _html} =
      live_isolated(conn, __MODULE__.Host, session: %{"user_id" => user.id})

    view |> element("#open-new-team") |> render_click()
    assert has_element?(view, "#new-team-icon-upload input[type=file]")

    upload = file_input(view, "#new-team-form", :group_icon, png())
    assert render_upload(upload, "team.png") =~ "team.png"

    view |> form("#new-team-form", group: %{title: "Painted"}) |> render_submit()

    [{group, "admin"}] = Groups.list_user_groups_with_role(user.id)
    assert group.icon_url =~ "icons/groups/#{group.id}/"
    assert view |> element("#created") |> render() =~ "icons/groups/#{group.id}/"
  end

  test "the dialog's colour lands on the icon picked", %{conn: conn, user: user} do
    {:ok, view, _html} =
      live_isolated(conn, __MODULE__.Host, session: %{"user_id" => user.id})

    view |> element("#open-new-team") |> render_click()

    view
    |> form("#new-team-form",
      group: %{title: "Tinted", icon_url: "/icons/star.svg", icon_url_color: "info"}
    )
    |> render_change()

    assert has_element?(
             view,
             "#new-team-form input[name='group[icon_url_color]'][value=info][checked]"
           )

    view |> form("#new-team-form") |> render_submit()

    [{group, "admin"}] = Groups.list_user_groups_with_role(user.id)
    assert group.icon_url == "/icons/star.svg?color=info"
  end

  test "closing the dialog drops the picked image", %{conn: conn, user: user} do
    {:ok, view, _html} =
      live_isolated(conn, __MODULE__.Host, session: %{"user_id" => user.id})

    view |> element("#open-new-team") |> render_click()
    view |> file_input("#new-team-form", :group_icon, png()) |> render_upload("team.png")
    view |> element("#new-team .modal-backdrop") |> render_click()
    view |> element("#open-new-team") |> render_click()
    refute render(view) =~ "team.png"
  end

  test "the groups page takes an image on New and on Edit", %{conn: conn, user: user} do
    {:ok, view, _html} = conn |> log_in_user(user) |> live("/users/groups?create=1")

    view
    |> file_input("#create-group-form", :group_icon, png())
    |> render_upload("team.png")

    view |> form("#create-group-form", group: %{title: "Studio"}) |> render_submit()

    [{group, "admin"}] = Groups.list_user_groups_with_role(user.id)
    first = group.icon_url
    assert first =~ "icons/groups/#{group.id}/"

    {:ok, view, _html} = conn |> log_in_user(user) |> live("/users/groups/#{group.id}")
    render_click(view, "group_toggle_edit", %{})
    assert has_element?(view, "#group-edit-form input[type=file]")

    view
    |> file_input("#group-edit-form", :group_icon, png("other.png"))
    |> render_upload("other.png")

    # Saved as it arrived, with no Save.
    icon = Groups.get_group(group.id).icon_url
    assert icon =~ "icons/groups/#{group.id}/"
    refute icon == first
  end

  describe "the groups page's buttons" do
    setup %{user: user} do
      {:ok, group} = Groups.create_group(user.id, %{"title" => "Studio"})
      {:ok, group: group}
    end

    test "only the list has Create", %{conn: conn, user: user, group: group} do
      conn = log_in_user(conn, user)

      {:ok, list, _html} = live(conn, "/users/groups")
      assert has_element?(list, "#groups-toggle-create", "Create")

      {:ok, page, _html} = live(conn, "/users/groups/#{group.id}")
      refute has_element?(page, "#groups-toggle-create")

      {:ok, edit, _html} = live(conn, "/users/groups/#{group.id}?edit=1")
      refute has_element?(edit, "#groups-toggle-create")
      assert has_element?(edit, "button#group-edit-save[form=group-edit-form]", "Save")
    end

    test "Cancel goes back to the group", %{conn: conn, user: user, group: group} do
      {:ok, view, _html} = conn |> log_in_user(user) |> live("/users/groups/#{group.id}?edit=1")

      view |> element("#group-edit-cancel") |> render_click()

      refute has_element?(view, "#group-edit-form")
      assert_patch(view)
    end

    test "Save goes to the list as a navigation", %{conn: conn, user: user, group: group} do
      {:ok, view, _html} = conn |> log_in_user(user) |> live("/users/groups/#{group.id}?edit=1")

      view |> form("#group-edit-form", group: %{title: "Renamed"}) |> render_submit()

      assert_redirect(view, "/users/groups")
      assert Groups.get_group(group.id).title == "Renamed"
    end

    test "an icon saves as it is picked, the rest waits for Save",
         %{conn: conn, user: user, group: group} do
      {:ok, view, _html} = conn |> log_in_user(user) |> live("/users/groups/#{group.id}?edit=1")

      view
      |> form("#group-edit-form",
        group: %{title: "Typed", icon_url: "/icons/star.svg", icon_url_color: "info"}
      )
      |> render_change()

      saved = Groups.get_group(group.id)
      assert saved.icon_url == "/icons/star.svg?color=info"
      assert saved.title == "Studio"
    end

    test "the colours are there before an icon is, one chosen",
         %{conn: conn, user: user, group: group} do
      {:ok, _} = Groups.set_icon_url(user.id, group.id, "/storage/icons/groups/x/a.png")
      {:ok, view, _html} = conn |> log_in_user(user) |> live("/users/groups/#{group.id}?edit=1")

      refute has_element?(view, "#group-edit-form input[name='group[icon_url]'][checked]")

      chosen =
        Enum.filter(Gamend.Icons.colors(), fn color ->
          has_element?(view, "input[name='group[icon_url_color]'][value='#{color}'][checked]")
        end)

      assert length(chosen) == 1
      [color] = chosen

      # The icon clicked next comes in it.
      view
      |> form("#group-edit-form", group: %{icon_url: "/icons/star.svg", icon_url_color: color})
      |> render_change()

      assert Groups.get_group(group.id).icon_url == "/icons/star.svg?color=#{color}"
    end

    test "a colour chosen before an icon stays chosen", %{conn: conn, user: user, group: group} do
      {:ok, _} = Groups.set_icon_url(user.id, group.id, "/storage/icons/groups/x/a.png")
      {:ok, view, _html} = conn |> log_in_user(user) |> live("/users/groups/#{group.id}?edit=1")

      for color <- Gamend.Icons.colors() do
        view |> form("#group-edit-form", group: %{icon_url_color: color}) |> render_change()

        assert has_element?(
                 view,
                 "input[name='group[icon_url_color]'][value='#{color}'][checked]"
               )
      end
    end
  end
end
