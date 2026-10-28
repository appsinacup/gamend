defmodule GamendWeb.UserLive.Groups do
  @moduledoc """
  The signed-in user's groups as a page of their own: the settings page's
  Groups tab (`GamendWeb.UserLive.Settings.GroupsTab`), whole. Their groups,
  a new one, invitations, and one group's members, invites, roles and edits.

  For a host whose navigation links to its groups. Forge and Gamend Cloud,
  whose groups own projects and servers, route it at `/users/groups`:

      gamend_authenticated_live_routes(@on_mount, groups: "/users/groups")

  `?group=<id>` opens one of the reader's groups and `?create=1` the form, as
  on the tab, so a host's page links straight to a team's members. Closed
  with the tab, by `web_groups`.
  """
  use GamendWeb, :live_view

  alias Gamend.Accounts.Scope
  alias Gamend.Groups
  alias GamendWeb.HostLayouts
  alias GamendWeb.UserLive.Settings.GroupsTab

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
     |> assign(:settings_tab, "groups")
     |> GroupsTab.assign_defaults()}
  end

  # The tab patches back to this page's own path (`groups_path`), without
  # the reader's locale prefix, as the routes are written.
  @impl true
  def handle_params(params, uri, socket) do
    path =
      uri
      |> URI.parse()
      |> Map.get(:path)
      |> HostLayouts.strip_locale_prefix(GamendWeb.GettextSync.known_locales())

    {:noreply,
     socket
     |> assign(:groups_path, path)
     |> GroupsTab.apply_params(params)
     |> GroupsTab.reload_groups()}
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
        <.back_link href={home_path()} />
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
