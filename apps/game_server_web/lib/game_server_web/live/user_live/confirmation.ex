defmodule GameServerWeb.UserLive.Confirmation do
  use GameServerWeb, :live_view

  alias GameServer.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="mx-auto max-w-sm">
        <div class="text-center">
          <.header>{@user.email}</.header>
        </div>

        <.form
          :if={!@user.confirmed_at}
          for={@form}
          id="confirmation_form"
          phx-mounted={JS.focus_first()}
          phx-submit="submit"
          action={~p"/users/log_in?_action=confirmed"}
          phx-trigger-action={@trigger_submit}
        >
          <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
          <.button
            name={@form[:remember_me].name}
            value="true"
            phx-disable-with={gettext("Loading...")}
            class="btn btn-primary w-full"
          >
            {gettext("Confirm and remember me")}
          </.button>
          <.button
            phx-disable-with={gettext("Loading...")}
            class="btn btn-primary btn-soft w-full mt-2"
          >
            {gettext("Confirm")}
          </.button>
        </.form>

        <.form
          :if={@user.confirmed_at}
          for={@form}
          id="login_form"
          phx-submit="submit"
          phx-mounted={JS.focus_first()}
          action={~p"/users/log_in"}
          phx-trigger-action={@trigger_submit}
        >
          <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
          <%= if @current_scope do %>
            <.button
              phx-disable-with={gettext("Loading...")}
              class="btn btn-primary w-full"
            >
              {gettext("Log in")}
            </.button>
          <% else %>
            <.button
              name={@form[:remember_me].name}
              value="true"
              phx-disable-with={gettext("Loading...")}
              class="btn btn-primary w-full"
            >
              {gettext("Log in and remember me")}
            </.button>
            <.button
              phx-disable-with={gettext("Loading...")}
              class="btn btn-primary btn-soft w-full mt-2"
            >
              {gettext("Log in")}
            </.button>
          <% end %>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"token" => token}, _session, socket) do
    if user = Accounts.get_user_by_magic_link_token(token) do
      form = to_form(%{"token" => token}, as: "user")

      {:ok,
       assign(socket,
         user: user,
         form: form,
         trigger_submit: false,
         page_title: gettext("Confirm")
       ), temporary_assigns: [form: nil]}
    else
      {:ok,
       socket
       |> put_flash(:error, gettext("Failed"))
       |> push_navigate(to: ~p"/users/log_in")}
    end
  end

  @impl true
  def handle_event("submit", %{"user" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: "user"), trigger_submit: true)}
  end
end
