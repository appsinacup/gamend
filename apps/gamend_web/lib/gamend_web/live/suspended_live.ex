defmodule GamendWeb.SuspendedLive do
  @moduledoc """
  `/suspended`: where a banned account (`Gamend.Bans`, kind `:account`) lands
  on the website. It says until when and why, and leads to the two things the
  account may still do, its settings (deleting it included) and logging out.

  `GamendWeb.UserAuth` sends a banned account here from every other LiveView.
  An account that is not banned is sent home.
  """
  use GamendWeb, :live_view

  alias Gamend.Accounts.Scope
  alias Gamend.Bans

  @impl true
  def mount(_params, _session, socket) do
    case Bans.account_ban(Scope.user_id(socket.assigns.current_scope)) do
      nil ->
        {:ok, redirect(socket, to: home_path())}

      ban ->
        {:ok,
         socket
         |> assign(:page_title, gettext("Account suspended"))
         |> assign(:ban, ban)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <.page_title icon="hero-no-symbol-solid">{gettext("Account suspended")}</.page_title>

      <.panel class="space-y-4">
        <dl class="grid gap-x-6 gap-y-2 sm:grid-cols-[auto_1fr]">
          <dt class="text-muted">{gettext("Suspended until")}</dt>
          <dd id="suspended-until">
            <%= if @ban.expires_at do %>
              <.timestamp at={@ban.expires_at} />
            <% else %>
              {gettext("Permanent")}
            <% end %>
          </dd>
          <%= if @ban.reason not in [nil, ""] do %>
            <dt class="text-muted">{gettext("Reason")}</dt>
            <dd id="suspended-reason" class="break-words">{@ban.reason}</dd>
          <% end %>
        </dl>

        <p>{gettext("You can still change your settings or delete your account.")}</p>

        <div class="flex flex-wrap gap-2">
          <.link navigate={~p"/users/settings"} class="btn btn-primary">
            {gettext("Settings")}
          </.link>
          <.link href={~p"/users/log_out"} method="delete" class="btn btn-surface">
            {gettext("Log out")}
          </.link>
        </div>
      </.panel>
    </Layouts.app>
    """
  end
end
