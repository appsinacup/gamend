defmodule GamendWeb.UserLive.Login do
  use GamendWeb, :live_view

  alias Gamend.Accounts
  alias Gamend.Accounts.Scope
  require Logger

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="mx-auto max-w-narrow space-y-4">
        <div class="text-center">
          <div class="flex items-center justify-center gap-3">
            <.back_link href={home_path()} />
            <h1 class="text-4xl font-black text-base-content">{gettext("Log in")}</h1>
          </div>
          <p class="text-sm text-muted mt-2">
            <%= if @reauth? do %>
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

        <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
          <.form
            :let={f}
            for={@form}
            id="login_form_magic"
            action={~p"/users/log_in"}
            phx-change="remember_email"
            phx-submit="submit_magic"
          >
            <.input
              readonly={@reauth?}
              field={f[:email]}
              value={@email}
              type="email"
              label={gettext("Email")}
              autocomplete="username"
              required
              phx-mounted={JS.focus()}
            />
            <.captcha id="login_magic_captcha" />
            <.button class="btn btn-primary w-full">
              {gettext("Send magic link")} <span aria-hidden="true">→</span>
            </.button>
          </.form>

          <div class="divider md:hidden">{gettext("or")}</div>

          <%!-- `phx-change` on the email input, not the form: a form-level
                change event serializes every field, and the password has no
                business crossing the socket on each keystroke. Only this input
                is sent. The magic-link form above carries the form-level
                binding that reconnect recovery needs, and both inputs render
                `@email`, so an address typed here comes back too. --%>
          <.form
            :let={f}
            for={@form}
            id="login_form_password"
            action={~p"/users/log_in"}
            phx-submit="submit_password"
            phx-trigger-action={@trigger_submit}
          >
            <.input
              readonly={@reauth?}
              field={f[:email]}
              value={@email}
              type="email"
              label={gettext("Email")}
              autocomplete="username"
              required
              phx-change="remember_email"
            />
            <.input
              field={@form[:password]}
              type="password"
              label={gettext("Password")}
              autocomplete="current-password"
            />
            <%!-- `@form`, not `f`: a `:let` variable re-renders with the slot, and
                  a re-render would put the box back to checked under the player. --%>
            <div class="flex items-center justify-between gap-2">
              <.input
                field={@form[:remember_me]}
                type="checkbox"
                label={gettext("Remember me")}
                checked
              />
              <%!-- There is no reset flow: a magic link logs the player in, and
                    the Account page takes a new password without asking for the old one. --%>
              <button
                type="button"
                id="forgot_password_link"
                class="mb-2 text-sm font-semibold text-brand hover:underline"
                phx-click={
                  JS.show(to: "#forgot_password_hint")
                  |> JS.focus(to: "#login_form_magic input[type=email]")
                }
              >
                {gettext("Forgot password?")}
              </button>
            </div>
            <p id="forgot_password_hint" class="hidden text-sm text-muted mb-2">
              {gettext(
                "Send yourself a magic link to log in, then set a new password on your Account page."
              )}
            </p>
            <.button class="btn btn-primary w-full">
              {gettext("Log in")} <span aria-hidden="true">→</span>
            </.button>
          </.form>
        </div>

        <.oauth_buttons action={:login} />
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, session, socket) do
    current_user = Scope.user(socket.assigns[:current_scope])

    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        (current_user && current_user.email)

    form = to_form(%{"email" => email}, as: "user")

    client_ip = GamendWeb.LiveHelpers.client_ip(socket, session)

    {:ok,
     assign(socket,
       form: form,
       # Both forms' email inputs are bound to this rather than to `form`, so a
       # reconnect's form recovery can put a typed address back without
       # re-rendering (and emptying) the password input beside it.
       email: email,
       # Confirming the account already signed in: its address, fixed. Only
       # an account with one: a guest (a device account) or a provider-only
       # one has none to fix, and comes here to log in to another account.
       reauth?: is_binary(current_user && current_user.email),
       trigger_submit: false,
       page_title: gettext("Log in"),
       client_ip: client_ip
     )}
  end

  @impl true
  def handle_event("remember_email", %{"user" => %{"email" => email}}, socket) do
    {:noreply, assign(socket, :email, email)}
  end

  def handle_event("remember_email", _params, socket), do: {:noreply, socket}

  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end

  def handle_event("submit_magic", %{"user" => %{"email" => email}} = params, socket) do
    with :ok <- GamendWeb.LiveHelpers.check_rate_limit(socket.assigns.client_ip, :auth),
         :ok <- GamendWeb.LiveHelpers.check_captcha(socket, params) do
      if user = Accounts.get_user_by_email(email) do
        deliver_magic_link(user)
      end

      info =
        gettext("If that email has an account, we sent it a login link. Check your inbox.")

      {:noreply,
       socket
       |> put_flash(:info, info)
       |> push_navigate(to: ~p"/users/log_in")}
    else
      {:error, %Phoenix.LiveView.Socket{} = socket} ->
        {:noreply, socket}

      {:error, _retry_after} ->
        {:noreply,
         put_flash(socket, :error, gettext("Too many attempts. Please try again later."))}
    end
  end

  # The player always gets the same message so this cannot be used to probe which
  # emails exist — which also means a failure here is invisible unless it is
  # logged. A raise (a locked database, an unreachable relay) would otherwise
  # only kill the event and look like the button did nothing.
  defp deliver_magic_link(user) do
    case Accounts.deliver_login_instructions(user, &url(~p"/users/log_in/#{&1}")) do
      {:ok, _email} ->
        :ok

      {:error, reason} ->
        Logger.error("magic link delivery failed user=#{user.id}: #{inspect(reason)}")
        :error
    end
  rescue
    e ->
      Logger.error("magic link delivery crashed user=#{user.id}: #{Exception.message(e)}")
      :error
  end

  # Only show the local-mailbox helper in development builds.
  # In production we may use Swoosh.Local when no SMTP is configured, but we
  # don't want the UI to advertise that to end users.
  defp local_mail_adapter? do
    adapter_is_local? =
      Application.get_env(:gamend_core, Gamend.Mailer)[:adapter] == Swoosh.Adapters.Local

    mailbox_preview_enabled? =
      GamendWeb.Features.enabled?(:mailbox_preview)

    adapter_is_local? and (dev_env?() or mailbox_preview_enabled?)
  end

  defp dev_env? do
    Application.get_env(:gamend_web, :environment, :prod) == :dev
  end
end
