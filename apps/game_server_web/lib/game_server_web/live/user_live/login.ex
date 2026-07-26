defmodule GameServerWeb.UserLive.Login do
  use GameServerWeb, :live_view

  alias GameServer.Accounts
  alias GameServer.Accounts.Scope

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="mx-auto max-w-sm lg:max-w-4xl space-y-4">
        <div class="text-center">
          <h1 class="text-3xl font-bold">{gettext("Log in")}</h1>
          <p class="text-sm text-base-content/70 mt-2">
            <%= if @current_scope do %>
              {gettext("Confirm")}
            <% else %>
              <.link
                navigate={~p"/users/register"}
                class="font-semibold text-brand hover:underline"
              >
                {gettext("Register")}
              </.link>
            <% end %>
          </p>
        </div>

        <div :if={local_mail_adapter?()} class="alert alert-info">
          <div>
            <p>You are running the local mail adapter.</p>
            <p>
              To see sent emails, visit <.link href="/dev/mailbox" class="underline">the mailbox page</.link>.
            </p>
          </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
          <.form
            :let={f}
            for={@form}
            id="login_form_magic"
            action={~p"/users/log_in"}
            phx-submit="submit_magic"
          >
            <.input
              readonly={!!@current_scope}
              field={f[:email]}
              type="email"
              label={gettext("Email")}
              autocomplete="username"
              required
              phx-mounted={JS.focus()}
            />
            <.button class="btn btn-primary w-full">
              {gettext("Send magic link")} <span aria-hidden="true">→</span>
            </.button>
          </.form>

          <div class="divider lg:hidden">{gettext("or")}</div>

          <.form
            :let={f}
            for={@form}
            id="login_form_password"
            action={~p"/users/log_in"}
            phx-submit="submit_password"
            phx-trigger-action={@trigger_submit}
          >
            <.input
              readonly={!!@current_scope}
              field={f[:email]}
              type="email"
              label={gettext("Email")}
              autocomplete="username"
              required
            />
            <.input
              field={@form[:password]}
              type="password"
              label={gettext("Password")}
              autocomplete="current-password"
            />
            <.button class="btn btn-primary w-full" name={@form[:remember_me].name} value="true">
              {gettext("Log in and remember me")} <span aria-hidden="true">→</span>
            </.button>
            <.button class="btn btn-primary btn-soft w-full mt-2">
              {gettext("Log in")}
            </.button>
          </.form>
        </div>

        <div class="divider">{gettext("or")}</div>

        <div class="grid grid-cols-1 sm:grid-cols-1 lg:grid-cols-2 gap-4">
          <.link
            href={~p"/auth/discord"}
            class="btn btn-neutral w-full flex items-center justify-center gap-2"
          >
            <svg
              class="w-5 h-5"
              fill="currentColor"
              viewBox="0 0 24 24"
              xmlns="http://www.w3.org/2000/svg"
            >
              <path d="M20.317 4.492c-1.53-.69-3.17-1.2-4.885-1.49a.075.075 0 0 0-.079.036c-.21.369-.444.85-.608 1.23a18.566 18.566 0 0 0-5.487 0 12.36 12.36 0 0 0-.617-1.23A.077.077 0 0 0 8.562 3c-1.714.29-3.354.8-4.885 1.491a.07.07 0 0 0-.032.027C.533 9.093-.32 13.555.099 17.961a.08.08 0 0 0 .031.055 20.03 20.03 0 0 0 5.993 2.98.078.078 0 0 0 .084-.026 13.83 13.83 0 0 0 1.226-1.963.074.074 0 0 0-.041-.104 13.201 13.201 0 0 1-1.872-.878.075.075 0 0 1-.008-.125c.126-.093.252-.19.372-.287a.075.075 0 0 1 .078-.01c3.927 1.764 8.18 1.764 12.061 0a.075.075 0 0 1 .079.009c.12.098.245.195.372.288a.075.075 0 0 1-.006.125c-.598.344-1.22.635-1.873.877a.075.075 0 0 0-.041.105c.36.687.772 1.341 1.225 1.962a.077.077 0 0 0 .084.028 19.963 19.963 0 0 0 6.002-2.981.076.076 0 0 0 .032-.054c.5-5.094-.838-9.52-3.549-13.442a.06.06 0 0 0-.031-.028zM8.02 15.278c-1.182 0-2.157-1.069-2.157-2.38 0-1.312.956-2.38 2.157-2.38 1.21 0 2.176 1.077 2.157 2.38 0 1.312-.956 2.38-2.157 2.38zm7.975 0c-1.183 0-2.157-1.069-2.157-2.38 0-1.312.955-2.38 2.157-2.38 1.21 0 2.176 1.077 2.157 2.38 0 1.312-.946 2.38-2.157 2.38z" />
            </svg>
            {gettext("Log in")}
          </.link>

          <.link
            href={~p"/auth/apple"}
            class="btn btn-neutral w-full flex items-center justify-center gap-2"
          >
            <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
              <path d="M17.05 20.28c-.98.95-2.05.8-3.08.35-1.09-.46-2.09-.48-3.24 0-1.44.62-2.2.44-3.06-.35C2.79 15.25 3.51 7.59 9.05 7.31c1.35.07 2.29.74 3.08.8 1.18-.24 2.31-.93 3.57-.84 1.51.12 2.65.72 3.4 1.8-3.12 1.87-2.38 5.98.48 7.13-.57 1.5-1.31 2.99-2.54 4.09l.01-.01zM12.03 7.25c-.15-2.23 1.66-4.07 3.74-4.25.29 2.58-2.34 4.5-3.74 4.25z" />
            </svg>
            {gettext("Log in")}
          </.link>

          <.link
            href={~p"/auth/google"}
            class="btn btn-neutral w-full flex items-center justify-center gap-2"
          >
            <svg class="w-5 h-5" viewBox="0 0 24 24" fill="currentColor">
              <path
                d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"
                fill="#4285F4"
              />
              <path
                d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"
                fill="#34A853"
              />
              <path
                d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"
                fill="#FBBC05"
              />
              <path
                d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"
                fill="#EA4335"
              />
            </svg>
            {gettext("Log in")}
          </.link>

          <.link
            href={~p"/auth/facebook"}
            class="btn btn-neutral w-full flex items-center justify-center gap-2"
          >
            <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
              <path d="M24 12.073c0-6.627-5.373-12-12-12s-12 5.373-12 12c0 5.99 4.388 10.954 10.125 11.854v-8.385H7.078v-3.47h3.047V9.43c0-3.007 1.792-4.669 4.533-4.669 1.312 0 2.686.235 2.686.235v2.953H15.83c-1.491 0-1.956.925-1.956 1.874v2.25h3.328l-.532 3.47h-2.796v8.385C19.612 23.027 24 18.062 24 12.073z" />
            </svg>
            {gettext("Log in")}
          </.link>

          <.link
            href={~p"/auth/steam"}
            class="btn btn-neutral w-full flex items-center justify-center gap-2"
          >
            <svg class="w-5 h-5" viewBox="0 0 24 24" fill="currentColor">
              <path d="M11.979 0C5.678 0 .511 4.86.022 11.037l6.432 2.658c.545-.371 1.203-.59 1.912-.59.063 0 .125.004.188.006l2.861-4.142V8.91c0-2.495 2.028-4.524 4.524-4.524 2.494 0 4.524 2.031 4.524 4.527s-2.03 4.525-4.524 4.525h-.105l-4.076 2.911c0 .052.004.105.004.159 0 1.875-1.515 3.396-3.39 3.396-1.635 0-3.016-1.173-3.331-2.727L.436 15.27C1.862 20.307 6.486 24 11.979 24c6.627 0 11.999-5.373 11.999-12S18.605 0 11.979 0zM7.54 18.21l-1.473-.61c.262.543.714.999 1.314 1.25 1.297.539 2.793-.076 3.332-1.375.263-.63.264-1.319.005-1.949s-.75-1.121-1.377-1.383c-.624-.26-1.29-.249-1.878-.03l1.523.63c.956.4 1.409 1.5 1.009 2.455-.397.957-1.497 1.41-2.454 1.012H7.54zm11.415-9.303c0-1.662-1.353-3.015-3.015-3.015-1.665 0-3.015 1.353-3.015 3.015 0 1.665 1.35 3.015 3.015 3.015 1.663 0 3.015-1.35 3.015-3.015zm-5.273-.005c0-1.252 1.013-2.266 2.265-2.266 1.249 0 2.266 1.014 2.266 2.266 0 1.251-1.017 2.265-2.266 2.265-1.253 0-2.265-1.014-2.265-2.265z" />
            </svg>
            {gettext("Log in")}
          </.link>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    current_user = Scope.user(socket.assigns[:current_scope])

    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        (current_user && current_user.email)

    form = to_form(%{"email" => email}, as: "user")

    client_ip = GameServerWeb.LiveHelpers.client_ip(socket)

    {:ok,
     assign(socket,
       form: form,
       trigger_submit: false,
       page_title: gettext("Log in"),
       client_ip: client_ip
     )}
  end

  @impl true
  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end

  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    case GameServerWeb.LiveHelpers.check_rate_limit(socket.assigns.client_ip, :auth) do
      :ok ->
        if user = Accounts.get_user_by_email(email) do
          Accounts.deliver_login_instructions(
            user,
            &url(~p"/users/log_in/#{&1}")
          )
        end

        info = gettext("Success.")

        {:noreply,
         socket
         |> put_flash(:info, info)
         |> push_navigate(to: ~p"/users/log_in")}

      {:error, _retry_after} ->
        {:noreply,
         put_flash(socket, :error, gettext("Too many attempts. Please try again later."))}
    end
  end

  # Only show the local-mailbox helper in development builds.
  # In production we may use Swoosh.Local when no SMTP is configured, but we
  # don't want the UI to advertise that to end users.
  defp local_mail_adapter? do
    adapter_is_local? =
      Application.get_env(:game_server_core, GameServer.Mailer)[:adapter] == Swoosh.Adapters.Local

    mailbox_preview_enabled? =
      GameServerWeb.Features.enabled?(:mailbox_preview)

    adapter_is_local? and (dev_env?() or mailbox_preview_enabled?)
  end

  defp dev_env? do
    Application.get_env(:game_server_web, :environment, :prod) == :dev
  end
end
