defmodule GamendWeb.UserLive.Settings.AccountTab do
  @moduledoc """
  Account tab of the user settings page: template, events, and helpers for
  email/password/display-name management, provider linking, and account
  deletion.
  """

  use GamendWeb, :html
  import Phoenix.LiveView

  alias Gamend.Accounts
  alias Gamend.OAuth.Providers
  alias Gamend.Storage
  alias GamendWeb.LiveHelpers
  alias GamendWeb.UserLive.Settings.Shared

  def assign_defaults(socket, user) do
    email_changeset = Accounts.change_user_email(user, %{}, validate_unique: false)
    password_changeset = Accounts.change_user_password(user, %{}, hash_password: false)

    socket
    |> assign(:current_email, user.email)
    |> assign(:email_form, to_form(email_changeset))
    |> assign(:display_form, to_form(Accounts.change_user_display_name(user)))
    |> assign(:username_form, to_form(Accounts.change_username(user)))
    |> assign(:password_form, to_form(password_changeset))
    |> assign(:trigger_submit, false)
    |> assign(:can_upload_avatar, Accounts.can_upload_avatar?(user))
    |> allow_upload(:avatar,
      accept: ~w(.png .jpg .jpeg .webp .gif),
      max_entries: 1,
      max_file_size: Gamend.Limits.get(:max_upload_bytes)
    )
  end

  def tab(assigns) do
    ~H"""
    <%!-- Account tab --%>
    <div :if={@settings_tab == "account"}>
      <div class="mt-6 grid grid-cols-1 md:grid-cols-2 gap-6">
        <div class="card bg-base-200 p-4 rounded-lg">
          <div class="font-semibold">{gettext("Account")}</div>

          <div class="flex items-center gap-4 mt-3">
            <.user_avatar user={@user} class="w-16 h-16" />
            <p :if={!@can_upload_avatar} class="text-xs text-base-content/60 max-w-xs">
              {gettext("Link an email or a sign-in provider to set a custom avatar.")}
            </p>
            <form
              :if={@can_upload_avatar}
              phx-change="validate_avatar"
              phx-no-unused-field
              phx-submit="save_avatar"
              id="avatar_form"
              class="space-y-2"
            >
              <.live_file_input
                upload={@uploads.avatar}
                class="file-input file-input-sm file-input-bordered w-full max-w-xs"
              />
              <%!-- The native file input clears its label on re-render, so show
                    the picked file here instead. --%>
              <div :for={entry <- @uploads.avatar.entries} class="flex items-center gap-2 text-xs">
                <.live_img_preview entry={entry} class="w-8 h-8 rounded-full object-cover" />
                <span class="truncate max-w-[10rem]">{entry.client_name}</span>
                <span class="text-base-content/60">{entry.progress}%</span>
                <button
                  type="button"
                  phx-click="cancel_avatar"
                  phx-value-ref={entry.ref}
                  class="btn btn-ghost btn-xs"
                  aria-label={gettext("Remove selected file")}
                >
                  <.icon name="hero-x-mark-solid" class="w-3 h-3" />
                </button>
                <span :if={upload_errors(@uploads.avatar, entry) != []} class="text-error">
                  {gettext("File is too large or not a supported image.")}
                </span>
              </div>
              <button
                type="submit"
                class="btn btn-primary btn-sm"
                disabled={@uploads.avatar.entries == []}
              >
                {gettext("Change avatar")}
              </button>
            </form>
          </div>

          <div class="text-sm mt-2 space-y-1 text-base-content/80">
            <div><strong>{gettext("ID")}:</strong> {@user.id}</div>
            <div><strong>{gettext("Email")}:</strong> {@current_email}</div>

            <.form
              for={@username_form}
              id="username_form"
              phx-change="validate_username"
              phx-submit="update_username"
            >
              <.input
                field={@username_form[:username]}
                type="text"
                label={gettext("Username")}
                required
              />
              <.button variant="primary" phx-disable-with={gettext("Saving...")}>
                {gettext("Save")}
              </.button>
            </.form>

            <.form
              for={@display_form}
              id="display_form"
              phx-change="validate_display_name"
              phx-submit="update_display_name"
            >
              <.input
                field={@display_form[:display_name]}
                type="text"
                label={gettext("Name")}
                required
              />
              <.button variant="primary" phx-disable-with={gettext("Saving...")}>
                {gettext("Save")}
              </.button>
            </.form>

            <.form
              for={@email_form}
              id="email_form"
              phx-submit="update_email"
              phx-change="validate_email"
            >
              <.input
                field={@email_form[:email]}
                type="email"
                label={gettext("Email")}
                autocomplete="username"
                required
              />
              <.button variant="primary" phx-disable-with={gettext("Loading...")}>
                {gettext("Save")}
              </.button>
            </.form>
          </div>
        </div>

        <div class="card bg-base-200 p-4 rounded-lg">
          <div class="font-semibold">{gettext("Password")}</div>

          <.form
            for={@password_form}
            id="password_form"
            action={~p"/users/update_password"}
            method="post"
            phx-change="validate_password"
            phx-submit="update_password"
            phx-trigger-action={@trigger_submit}
          >
            <input
              name={@password_form[:email].name}
              type="hidden"
              id="hidden_user_email"
              autocomplete="username"
              value={@current_email}
            />
            <.input
              field={@password_form[:password]}
              type="password"
              label={gettext("Password")}
              autocomplete="new-password"
              required
            />
            <.input
              field={@password_form[:password_confirmation]}
              type="password"
              label={gettext("Confirm password")}
              autocomplete="new-password"
            />
            <.button variant="primary" phx-disable-with={gettext("Saving...")}>
              {gettext("Save")}
            </.button>
          </.form>
        </div>
      </div>

      <div class="card bg-base-200 p-4 rounded-lg mt-6">
        <div class="font-semibold">{gettext("Account")}</div>
        <div class="mt-2 grid grid-cols-1 md:grid-cols-2 gap-4">
          <% provider_count =
            Enum.count(
              [
                @user.discord_id,
                @user.apple_id,
                @user.google_id,
                @user.facebook_id,
                @user.github_id,
                @user.steam_id
              ],
              fn v ->
                v && v != ""
              end
            ) %>

          <div
            :for={{provider, linked_id} <- provider_rows(@user)}
            class="flex items-center justify-between"
          >
            <div>
              <strong>{provider_name(provider)}</strong>
              <div class="text-sm text-base-content/70">
                {if linked_id, do: gettext("Linked"), else: gettext("Not linked")}
              </div>
            </div>
            <div class="flex items-center gap-2">
              <%= cond do %>
                <% linked_id && provider_count > 1 -> %>
                  <button
                    phx-click="unlink_provider"
                    phx-value-provider={provider}
                    class="btn btn-outline btn-sm"
                  >
                    {gettext("Remove")}
                  </button>
                <% linked_id -> %>
                  <button class="btn btn-disabled btn-sm" disabled aria-disabled>
                    {gettext("Remove")}
                  </button>
                <% true -> %>
                  <.link href={"/auth/#{provider}"} class="btn btn-primary btn-sm">
                    {gettext("Link")}
                  </.link>
              <% end %>
            </div>
          </div>
        </div>
      </div>

      <div class="card bg-base-200 p-4 rounded-lg mt-6">
        <div class="font-semibold">{gettext("Metadata")}</div>
        <div class="text-sm mt-2 font-mono text-xs bg-base-300 p-3 rounded-lg overflow-auto text-base-content/80">
          <pre phx-no-curly-interpolation><%= Jason.encode!(@user.metadata || %{}, pretty: true) %></pre>
        </div>
      </div>

      <div class="card bg-error/10 border-error p-4 rounded-lg mt-6">
        <div class="font-semibold text-error">{gettext("Danger zone")}</div>
        <div class="text-sm mt-2 text-base-content/80">
          <.link
            href={~p"/data_deletion"}
            class="link link-primary"
          >
            {gettext("Read data deletion instructions")}
          </.link>
        </div>
        <div class="mt-4">
          <button
            id="delete-account-button"
            phx-click="delete_user"
            class="btn btn-error"
            data-confirm={delete_confirmation(Accounts.deletion_grace_days())}
          >
            {gettext("Delete account")}
          </button>
        </div>
      </div>
    </div>

    <%!-- Friends tab --%>
    """
  end

  def handle_event("validate_email", %{"user" => user_params}, socket) do
    user = Shared.current_user(socket)

    email_form =
      user
      |> Accounts.change_user_email(user_params, validate_unique: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", %{"user" => user_params}, socket) do
    user = Shared.current_user(socket)

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/users/settings/confirm_email/#{&1}")
        )

        {:noreply,
         put_flash(
           socket,
           :info,
           gettext("Check your new email address for a link to confirm the change.")
         )}

      changeset ->
        {:noreply, assign(socket, :email_form, to_form(changeset, action: :insert))}
    end
  end

  def handle_event("validate_display_name", %{"user" => user_params}, socket) do
    user = Shared.current_user(socket)

    display_form =
      user
      |> Accounts.change_user_display_name(user_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, display_form: display_form)}
  end

  def handle_event("update_display_name", %{"user" => user_params}, socket) do
    user = Shared.current_user(socket)

    case Accounts.update_user_display_name(user, user_params) do
      {:ok, updated_user} ->
        updated_scope = socket.assigns.current_scope

        {:noreply,
         socket
         |> put_flash(:info, gettext("Success."))
         |> assign(:user, updated_user)
         |> assign(:current_scope, updated_scope)}

      {:error, changeset} ->
        {:noreply, assign(socket, display_form: to_form(changeset, action: :insert))}
    end
  end

  def handle_event("validate_username", %{"user" => user_params}, socket) do
    user = Shared.current_user(socket)

    username_form =
      user
      |> Accounts.change_username(user_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, username_form: username_form)}
  end

  def handle_event("update_username", %{"user" => user_params}, socket) do
    user = Shared.current_user(socket)

    case Accounts.update_username(user, user_params) do
      {:ok, updated_user} ->
        updated_scope = socket.assigns.current_scope

        {:noreply,
         socket
         |> put_flash(:info, gettext("Success."))
         |> assign(:user, updated_user)
         |> assign(:current_scope, updated_scope)
         |> assign(:username_form, to_form(Accounts.change_username(updated_user)))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, username_form: to_form(changeset, action: :insert))}

      # Anything else is the `before_user_update` hook refusing: its own words
      # when it gave a string, a plain refusal otherwise.
      {:error, reason} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           LiveHelpers.failure_message(gettext("Not allowed"), {:hook_rejected, reason})
         )}
    end
  end

  def handle_event("validate_avatar", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_avatar", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :avatar, ref)}
  end

  def handle_event("save_avatar", _params, socket) do
    user = Shared.current_user(socket)

    if Accounts.can_upload_avatar?(user),
      do: save_avatar(socket, user),
      else: {:noreply, put_flash(socket, :error, gettext("Avatar uploads are not available."))}
  end

  def handle_event("validate_password", %{"user" => user_params}, socket) do
    user = Shared.current_user(socket)

    password_form =
      user
      |> Accounts.change_user_password(user_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("update_password", %{"user" => user_params}, socket) do
    user = Shared.current_user(socket)

    case Accounts.change_user_password(user, user_params) do
      %{valid?: true} = changeset ->
        {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

      changeset ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
    end
  end

  def handle_event("unlink_provider", %{"provider" => provider}, socket) do
    user = Shared.current_user(socket)
    provider_atom = String.to_existing_atom(provider)

    case Accounts.unlink_provider(user, provider_atom) do
      {:ok, user} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Success."))
         |> assign(:user, user)}

      {:error, :last_provider} ->
        {:noreply, put_flash(socket, :error, gettext("Failed"))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Failed"))}
    end
  end

  def handle_event("delete_user", _params, socket) do
    user = Shared.current_user(socket)

    case Accounts.request_deletion(user) do
      {:ok, :deleted} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Success."))
         |> redirect(external: ~p"/")}

      {:ok, {:scheduled, _user, expired_tokens}} ->
        GamendWeb.UserAuth.disconnect_sessions(expired_tokens)

        {:noreply,
         socket
         |> put_flash(
           :info,
           ngettext(
             "Your account will be deleted in %{count} day. Sign in before then to keep it.",
             "Your account will be deleted in %{count} days. Sign in before then to keep it.",
             Accounts.deletion_grace_days()
           )
         )
         |> redirect(external: ~p"/")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, gettext("Failed"))}
    end
  end

  def handle_event("delete_conflicting_account", _params, socket) do
    # The target is the conflict resolved at mount, never an id from the event.
    # A LiveView event payload is client-controlled, so trusting the id in it
    # let any signed-in user delete any account without a password.
    case socket.assigns[:conflict_user] do
      %Accounts.User{} = other_user ->
        handle_delete_conflicting_account(socket, Shared.current_user(socket), other_user)

      _ ->
        {:noreply, put_flash(socket, :error, gettext("Not found"))}
    end
  end

  defp save_avatar(socket, user) do
    uploads =
      consume_uploaded_entries(socket, :avatar, fn %{path: path}, _entry ->
        data = File.read!(path)

        # `accept:` only screens the filename and the browser-declared type. Take
        # the extension from what the bytes actually are, so nothing but a real
        # image is ever stored under an image extension.
        case Storage.sniff_content_type(data) do
          nil ->
            {:ok, :not_an_image}

          content_type ->
            key = Storage.build_key("avatars", user.id, Storage.extension_for(content_type))
            {:ok, _} = Storage.put(key, data, content_type: content_type)
            {:ok, {key, Storage.url(key)}}
        end
      end)

    case uploads do
      [:not_an_image | _] ->
        {:noreply, put_flash(socket, :error, gettext("That file is not a valid image."))}

      [{key, url} | _] ->
        case Accounts.update_user_avatar(user, url) do
          {:ok, updated} ->
            # Drop the previous avatar object(s) now that the new one is live.
            _ = Accounts.prune_user_avatars(user.id, key)

            # The navbar reads its user via `Scope.user/1`, which re-fetches by id;
            # `update_user_avatar` invalidated the cache, so it picks up the new
            # avatar on this re-render without touching the scope.
            {:noreply,
             socket
             |> put_flash(:info, gettext("Avatar updated."))
             |> assign(:user, updated)}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, gettext("Could not update avatar."))}
        end

      [] ->
        {:noreply, put_flash(socket, :error, gettext("Please choose an image first."))}
    end
  end

  @doc """
  The pending OAuth link conflict for this session, as `{conflict_user, provider}`.

  A conflict exists only when `GamendWeb.AuthController` proved one: the caller
  completed a provider callback and that provider identity was already linked to
  another account. It is recorded in the session there, so the id can never be
  supplied by the reader.

  Re-validated on every mount, because the session outlives the situation: the
  other account may since have unlinked the provider, been deleted, or turned out
  to be the caller's own. Anything that no longer holds resolves to no conflict.
  """
  @spec resolve_link_conflict(map(), Accounts.User.t() | nil) ::
          {Accounts.User.t() | nil, String.t() | nil}
  def resolve_link_conflict(session, current_user)

  def resolve_link_conflict(
        %{"oauth_link_conflict" => %{"provider" => provider, "user_id" => user_id}},
        %Accounts.User{} = current_user
      )
      when is_binary(provider) and is_binary(user_id) do
    with true <- provider in Enum.map(Providers.all(), &to_string/1),
         %Accounts.User{} = other <- Accounts.get_user(user_id),
         true <- other.id != current_user.id,
         # Still claiming the identity we were blocked on.
         linked_id when is_binary(linked_id) <- linked_provider_id(other, provider) do
      {other, provider}
    else
      _ -> {nil, nil}
    end
  end

  def resolve_link_conflict(_session, _current_user), do: {nil, nil}

  # Deletion is allowed only for an account that is *nothing but* the provider
  # identity the caller has just proven they control: no password, no device
  # credential, and no second provider. Such a row is an orphan holding an
  # identity that is demonstrably the caller's.
  #
  # Anything else is a real account that merely shares one identity, and the
  # answer there is to sign in to it and unlink — never to let one party delete
  # another's account, their stored objects, KV entries and wallet along with it.
  defp handle_delete_conflicting_account(socket, current, other_user) do
    cond do
      other_user.id == current.id ->
        {:noreply, put_flash(socket, :error, gettext("Failed"))}

      orphaned_provider_account?(other_user) ->
        perform_conflicting_account_deletion(socket, other_user)

      true ->
        {:noreply,
         put_flash(
           socket,
           :error,
           gettext(
             "That account has its own sign-in method. Sign in to it and unlink the provider there."
           )
         )}
    end
  end

  defp orphaned_provider_account?(%Accounts.User{} = user) do
    linked_providers =
      Providers.all()
      |> Enum.map(&linked_provider_id(user, &1))
      |> Enum.count(&is_binary/1)

    is_nil(user.hashed_password) and user.device_id in [nil, ""] and linked_providers <= 1
  end

  defp perform_conflicting_account_deletion(socket, user) do
    case Accounts.delete_user(user) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Success."))
         |> assign(:conflict_user, nil)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Failed"))}
    end
  end

  defp delete_confirmation(0),
    do: gettext("Delete your account permanently? This cannot be undone.")

  defp delete_confirmation(days) do
    ngettext(
      "Delete your account? It will be deleted in %{count} day, and signing in before then keeps it.",
      "Delete your account? It will be deleted in %{count} days, and signing in before then keeps it.",
      days
    )
  end

  # Rows in the Account card: every linked provider (a disabled one must stay
  # unlinkable) plus every enabled one.
  # Brand names: never translated. `capitalize/1` covers every provider but
  # the one with a capital in the middle.
  defp provider_name(:github), do: "GitHub"
  defp provider_name(provider), do: provider |> Atom.to_string() |> String.capitalize()

  defp provider_rows(user) do
    Providers.all()
    |> Enum.map(&{&1, linked_provider_id(user, &1)})
    |> Enum.filter(fn {provider, linked_id} ->
      linked_id || Providers.enabled?(provider)
    end)
  end

  defp linked_provider_id(user, provider) do
    case Map.fetch!(user, :"#{provider}_id") do
      value when value in [nil, ""] -> nil
      value -> value
    end
  end
end
