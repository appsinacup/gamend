defmodule GamendWeb.UserLive.Confirmation do
  @moduledoc """
  The page an emailed link opens: a magic link (`:new`, `/users/log_in/:token`)
  or an account's confirmation link (`:confirm_email`, `/users/confirm/:token`).
  Opening it changes nothing; its button posts the token, so a mail scanner
  that follows every link in an email neither confirms nor spends it.
  """
  use GamendWeb, :live_view

  alias Gamend.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="mx-auto max-w-narrow">
        <div class="text-center">
          <.header class="break-all">{@user.email}</.header>
        </div>

        <.form
          :if={!@user.confirmed_at}
          for={@form}
          id="confirmation_form"
          phx-mounted={JS.focus_first()}
          phx-submit="submit"
          action={@confirm_action}
          phx-trigger-action={@trigger_submit}
        >
          <input type="hidden" name={@form[:token].name} value={@form[:token].value} />
          <%!-- Confirming drops a password set before the email was confirmed
               (Accounts.login_user_by_magic_link/1, confirm_user_by_token/1). --%>
          <p
            :if={@user.hashed_password}
            id="confirmation-password-notice"
            class="mb-4 text-sm text-muted"
          >
            {gettext(
              "Confirming with this link removes the password this account was registered with, so set a new one in your account settings afterwards."
            )}
          </p>
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
          :if={@user.confirmed_at && @live_action == :new}
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
    if user = user_for(socket.assigns.live_action, token) do
      form = to_form(%{"token" => token}, as: "user")

      {:ok,
       assign(socket,
         user: user,
         form: form,
         confirm_action: confirm_action(socket.assigns.live_action),
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

  # A confirmation link is spent when the account is confirmed, so it only
  # ever finds an account still waiting.
  defp user_for(:confirm_email, token), do: Accounts.get_user_by_confirm_token(token)
  defp user_for(_magic_link, token), do: Accounts.get_user_by_magic_link_token(token)

  defp confirm_action(:confirm_email), do: ~p"/users/confirm"
  defp confirm_action(_magic_link), do: ~p"/users/log_in?_action=confirmed"

  @impl true
  def handle_event("submit", %{"user" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: "user"), trigger_submit: true)}
  end
end
