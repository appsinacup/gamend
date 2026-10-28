defmodule GamendWeb.UserLive.GroupJoin do
  @moduledoc """
  The page a group's invite link opens (`Gamend.Groups.InviteLinks`): which
  group, who shared it, and a Join button that makes the reader a member,
  then opens the group (`GamendWeb.GroupLinks.group_path/2`).

  Signed in only: someone signed out is sent to log in or register and comes
  back here. A link that no longer works says so, and never which group it
  was for. Routed by `gamend_authenticated_live_routes/2` beside the groups
  page, at `/users/groups/join/:token` on a host whose groups are at
  `/users/groups`;
  closed with the rest of the groups pages, by `web_groups`.
  """
  use GamendWeb, :live_view

  alias Gamend.Accounts.Scope
  alias Gamend.Groups
  alias GamendWeb.GroupLinks
  alias GamendWeb.LiveHelpers

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    unless GamendWeb.Features.enabled?(:web_groups), do: raise(GamendWeb.NotFoundError)

    user = Scope.user(socket.assigns.current_scope)
    link = Groups.get_invite_link_by_token(token)

    {:ok,
     socket
     |> assign(:page_title, gettext("Groups"))
     |> assign(:user, user)
     |> assign(:token, token)
     |> assign(:link, link)
     |> assign(:member?, link != nil and Groups.member?(link.group_id, user.id))
     |> assign(:count, if(link, do: Groups.count_group_members(link.group_id), else: 0))
     |> assign(:group_path, link && GroupLinks.group_path(socket, link.group_id))}
  end

  @impl true
  def handle_event("join", _params, socket) do
    %{user: user, token: token, link: link} = socket.assigns

    case Groups.join_by_invite_link(user.id, token) do
      {:ok, _member} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("You joined %{name}.", name: link.group.title))
         |> push_navigate(to: socket.assigns.group_path)}

      {:error, :already_member} ->
        {:noreply, push_navigate(socket, to: socket.assigns.group_path)}

      {:error, :not_found} ->
        {:noreply, assign(socket, :link, nil)}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, LiveHelpers.failure_message(gettext("Failed"), reason))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="mx-auto mt-8 max-w-md">
        <div id="group-join" class="card border border-base-300 bg-base-100">
          <div :if={@link == nil} class="card-body items-center text-center">
            <.icon name="hero-link-slash" class="size-10 text-base-content/50" />
            <h1 class="text-lg font-semibold">{gettext("This invite link no longer works")}</h1>
            <p class="text-sm text-base-content/70">
              {gettext("It expired, or an admin made a new one. Ask them for the new link.")}
            </p>
          </div>

          <div :if={@link} class="card-body items-center text-center">
            <.icon name="hero-user-group" class="size-10 text-primary" />
            <h1 class="text-xl font-semibold">{@link.group.title}</h1>
            <p :if={@link.created_by} class="text-sm text-base-content/70">
              {gettext("%{name} invited you to join.",
                name: Gamend.Accounts.display_name(@link.created_by)
              )}
            </p>
            <p class="text-sm text-base-content/70">
              {ngettext("1 member", "%{count} members", @count)}
            </p>

            <div class="card-actions mt-4">
              <%= if @member? do %>
                <p class="w-full text-sm">{gettext("You are already in it.")}</p>
                <.link
                  id="group-join-open"
                  navigate={@group_path}
                  class="btn btn-primary btn-sm"
                >
                  {gettext("Open")}
                </.link>
              <% else %>
                <.link navigate={home_path()} class="btn btn-ghost btn-sm">
                  {gettext("Not now")}
                </.link>
                <button id="group-join-button" phx-click="join" class="btn btn-primary btn-sm">
                  {gettext("Join")}
                </button>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
