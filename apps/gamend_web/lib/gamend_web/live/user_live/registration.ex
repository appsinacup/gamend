defmodule GamendWeb.UserLive.Registration do
  use GamendWeb, :live_view

  alias Gamend.Accounts
  alias Gamend.Accounts.{Scope, User, UserToken}
  alias Gamend.Notifications.Preferences
  alias Gamend.Repo

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="mx-auto max-w-narrow space-y-4">
        <div class="text-center">
          <div class="flex items-center justify-center gap-3">
            <.back_link href={home_path()} />
            <h1 class="text-4xl font-black text-base-content">{gettext("Register")}</h1>
          </div>
          <p class="text-sm text-muted mt-2">
            <.link navigate={~p"/users/log_in"} class="font-semibold text-brand hover:underline">
              {gettext("Log in")}
            </.link>
          </p>
        </div>

        <.form for={@form} id="registration_form" phx-submit="save" phx-change="validate">
          <.input
            field={@form[:email]}
            type="email"
            label={gettext("Email")}
            autocomplete="username"
            required
            phx-mounted={JS.focus()}
          />

          <%!-- Opt-in, never pre-ticked: `Preferences.signup_groups/0`. --%>
          <fieldset :if={@signup_groups != []} class="my-3 space-y-2">
            <label
              :for={group <- @signup_groups}
              class="flex items-center gap-2 text-sm"
            >
              <input
                type="checkbox"
                name={"notify[#{group.key}]"}
                value="true"
                id={"registration-notify-#{group.key}"}
                checked={@notify[group.key] == "true"}
                class="checkbox checkbox-sm"
              />
              {gettext("Email me: %{group}", group: GamendWeb.NotificationEmail.group_label(group))}
            </label>
          </fieldset>

          <.captcha id="registration_captcha" />

          <.button
            phx-disable-with={gettext("Loading...")}
            class="btn btn-primary w-full"
          >
            {gettext("Register")}
          </.button>
        </.form>

        <.oauth_buttons action={:register} />
      </div>
    </Layouts.app>
    """
  end

  @impl true
  # A guest (an anonymous account, `Scope.anonymous?/1`) registers like anyone
  # else; the email then goes on the account they are already using, so it
  # keeps everything (`Accounts.upgrade_anonymous_user_and_deliver/4`).
  def mount(params, session, %{assigns: %{current_scope: %{user_id: user_id} = scope}} = socket)
      when is_binary(user_id) do
    if Scope.anonymous?(scope) do
      mount_form(params, session, socket)
    else
      require Logger
      Logger.info("[Registration] User already logged in, redirecting to signed_in_path")
      {:ok, Phoenix.LiveView.redirect(socket, external: ~p"/users/settings")}
    end
  end

  def mount(params, session, socket), do: mount_form(params, session, socket)

  defp mount_form(_params, session, socket) do
    changeset = Accounts.change_user_email(%User{}, %{}, validate_unique: false)

    client_ip = GamendWeb.LiveHelpers.client_ip(socket, session)

    {:ok,
     socket
     |> assign(:page_title, gettext("Register"))
     |> assign(:client_ip, client_ip)
     |> assign(:signup_groups, Preferences.signup_groups())
     |> assign(:notify, %{})
     |> assign_form(changeset), temporary_assigns: [form: nil]}
  end

  @impl true
  def handle_event("save", %{"user" => user_params} = params, socket) do
    with :ok <- GamendWeb.LiveHelpers.check_rate_limit(socket.assigns.client_ip, :auth),
         :ok <- GamendWeb.LiveHelpers.check_captcha(socket, params) do
      do_save(user_params, Map.get(params, "notify", %{}), socket)
    else
      {:error, %Phoenix.LiveView.Socket{} = socket} ->
        {:noreply, socket}

      {:error, _retry_after} ->
        {:noreply,
         put_flash(socket, :error, gettext("Too many attempts. Please try again later."))}
    end
  end

  def handle_event("validate", %{"user" => user_params} = params, socket) do
    # The keystroke path skips the uniqueness query — see
    # `Accounts.change_user_registration_for_validation/2` for why. `save`
    # below uses the checking form.
    changeset =
      %User{}
      |> Accounts.change_user_registration_for_validation(user_params)
      |> Map.put(:action, :validate)

    # The boxes are not in the changeset, so a re-render would untick them:
    # keep what the reader ticked.
    {:noreply,
     socket
     |> assign(:notify, notify_params(params))
     |> assign_form(changeset)}
  end

  defp notify_params(%{"notify" => %{} = notify}), do: notify
  defp notify_params(_params), do: %{}

  # A guest's email goes on the account they already have, which keeps what
  # they did; anyone else gets a new account.
  defp register(socket, user_params, notifier) do
    url_fun = fn t -> url(~p"/users/confirm/#{t}") end

    case Scope.user(socket.assigns[:current_scope]) do
      %User{} = user ->
        Accounts.upgrade_anonymous_user_and_deliver(user, user_params, url_fun, notifier)

      nil ->
        Accounts.register_user_and_deliver(user_params, url_fun, notifier)
    end
  end

  defp do_save(user_params, notify, socket) do
    notifier =
      Application.get_env(:gamend_web, :user_notifier, Gamend.Accounts.UserNotifier)

    case register(socket, user_params, notifier) do
      {:ok, user} ->
        opt_in(user, notify, socket.assigns.signup_groups)

        # Check if this is the first user (admin users are auto-created as first user)
        is_first_user = user.is_admin

        if is_first_user do
          # First user: registered confirmed, and logged in straight away.
          # Generate a magic link token for auto-login
          {token, user_token} = UserToken.build_email_token(user, "login")
          Repo.insert!(user_token)

          # Redirect to login with the token (will auto-login the confirmed user)
          {:noreply,
           socket
           |> put_flash(
             :info,
             gettext("Success.")
           )
           |> push_navigate(to: ~p"/users/log_in/#{token}")}
        else
          # Not the first user: the confirmation email is queued and goes out
          # in the background. Inform the user to check their inbox.
          {:noreply,
           socket
           |> put_flash(
             :info,
             gettext("Account created. Check your email for a link to confirm it.")
           )
           |> push_navigate(to: ~p"/users/log_in")}
        end

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, socket |> assign(check_errors: true) |> assign_form(changeset)}

      {:error, reason} ->
        # A `before_user_register` plugin refused the sign-up (the email is
        # queued, so it cannot fail here). Keep the form open.
        require Logger
        Logger.error("register_user_and_deliver failed: #{inspect(reason)}")

        changeset = Accounts.change_user_registration(%User{}, user_params)

        {:noreply,
         socket
         |> put_flash(
           :error,
           gettext("Failed")
         )
         |> assign(check_errors: true)
         |> assign_form(Map.put(changeset, :action, :insert))}
    end
  end

  defp opt_in(user, notify, groups) when is_map(notify) do
    for %{key: key} <- groups, notify[key] == "true" do
      Preferences.put(user, key, "email", true)
    end
  end

  defp opt_in(_user, _notify, _groups), do: []

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    form = to_form(changeset, as: "user")
    assign(socket, form: form)
  end
end
