defmodule GamendWeb.UserLive.Groups do
  @moduledoc """
  The signed-in user's groups as a page of their own: the settings page's
  Groups tab (`GamendWeb.UserLive.Settings.GroupsTab`), whole. Their groups,
  a new one, invitations, and one group's members, invites, roles and edits.

  For a host whose navigation links to its groups. Forge and Gamend Cloud,
  whose groups own projects and servers, route it at `/users/groups`:

      gamend_authenticated_live_routes(@on_mount, groups: "/users/groups")

  `/users/groups/<owner>/<slug>` (or `/users/groups/<id>`,
  `GamendWeb.GroupLinks.group_path/2`) opens one of the reader's groups, a
  page under the list, and `?create=1` the form, as on the tab, so a host's
  page links straight to a team's members. Closed with the tab, by
  `web_groups`.
  """
  use GamendWeb, :live_view

  alias Gamend.Accounts.Scope
  alias Gamend.Groups
  alias GamendWeb.GroupLinks
  alias GamendWeb.HostLayouts
  alias GamendWeb.UserLive.Settings.GroupsTab

  require GamendWeb.UserLive.Settings.SettingsTab, as: SettingsTab

  @events GroupsTab.events()
  @reloads GroupsTab.reloads()

  @impl true
  def mount(_params, _session, socket) do
    unless GamendWeb.Features.enabled?(:web_groups), do: raise(GamendWeb.NotFoundError)

    user = Scope.user(socket.assigns.current_scope)

    if connected?(socket) do
      Groups.subscribe_groups()
      Phoenix.PubSub.subscribe(Gamend.PubSub, "user:#{user.id}")
    end

    {:ok,
     socket
     |> assign(:page_title, gettext("Groups"))
     |> assign(:user, user)
     |> assign(:settings_tab, SettingsTab.groups())
     |> GroupsTab.assign_defaults()}
  end

  # One group: its ref is the path under the list's (`*group`).
  @impl true
  def handle_params(%{"group" => [_ | _] = segments} = params, _uri, socket),
    do: {:noreply, apply_params(socket, %{params | "group" => Enum.join(segments, "/")})}

  # `?group=<ref>`, the list's link before a group had a path of its own:
  # the group's path, in place of the old entry.
  def handle_params(%{"group" => ref} = params, _uri, socket)
      when is_binary(ref) and ref != "" do
    query = params |> Map.delete("group") |> URI.encode_query()
    to = GroupLinks.group_path(socket, ref)

    {:noreply,
     push_patch(socket, to: if(query == "", do: to, else: to <> "?" <> query), replace: true)}
  end

  def handle_params(params, _uri, socket), do: {:noreply, apply_params(socket, params)}

  # The tab patches back to the list's own path (`groups_path`), without the
  # reader's locale prefix, as the routes are written.
  defp apply_params(socket, params) do
    socket
    |> assign(:groups_path, GroupLinks.groups_path(socket))
    |> GroupsTab.apply_params(params)
    |> GroupsTab.reload_groups()
  end

  @impl true
  def handle_event(event, params, socket) when event in @events,
    do: GroupsTab.handle_event(event, params, socket)

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info({event, _payload}, socket) when event in @reloads,
    do: {:noreply, GroupsTab.reload_groups(socket)}

  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div data-heading-fit class="flex items-center gap-3">
        <%!-- Back from a group to the list, where the reader came from. The
              list is the navbar's, with no Back of its own. --%>
        <.back_link :if={@group_detail} always navigate={@groups_path} />
        <.page_title
          icon={HostLayouts.nav_icon(@groups_path, "hero-user-group-solid")}
          tone={HostLayouts.nav_tone(@groups_path)}
        >
          {gettext("Groups")}
        </.page_title>
      </div>

      <GroupsTab.tab {Map.delete(assigns, :__changed__)} />
    </Layouts.app>
    """
  end
end
