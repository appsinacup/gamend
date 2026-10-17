defmodule Gamend.Accounts.Identities do
  @moduledoc """
  How a person signs in without a password — Discord, Apple, Google, Facebook,
  GitHub, Steam or a device id — and linking those identities to an existing account or
  removing them from one.

  Split out of `Gamend.Accounts`, which still exposes every function here under
  the same name.
  """

  import Ecto.Query, warn: false
  alias Gamend.Accounts.AvatarMirror
  alias Gamend.Accounts.User
  alias Gamend.Repo

  # Upper bound on cross-node staleness for cached user structs: explicit
  # invalidations propagate immediately via `Gamend.Cache.invalidate/1`,
  # and this TTL caps staleness if an invalidation broadcast is ever missed.
  alias Gamend.Accounts
  alias Gamend.Accounts.Registration

  # Mirror an external (OAuth provider) avatar into our object storage so avatars
  # render from our storage/CDN rather than hotlinking the provider. Enqueued
  # whenever the user's avatar is not already one of our stored objects — once
  # mirrored the URL points at our storage, so `our_stored_avatar?/1`
  # short-circuits every later sign-in and we never re-fetch.
  #
  # Uniqueness deliberately omits `:discarded` and `:cancelled`. Counting those
  # meant one failed download — a provider 429 is enough — blocked every future
  # job for that user forever, leaving the avatar hotlinked to the provider for
  # good. Excluding them lets the next sign-in try again, while a job still
  # in flight or already completed keeps the dedupe.
  #
  # `source_url` is part of the key on purpose: enqueueing is already gated on
  # "avatar is not one of our stored objects", so a completed job only blocks
  # re-mirroring the *same* URL. Without it, an account healed after storage
  # loss (see `dangling_stored_avatar?/1`) could never mirror its fresh
  # provider URL — the years-old completed job would swallow it.
  @mirror_dedupe_states [:available, :scheduled, :executing, :retryable, :completed]

  @doc """
  Finds a user by Discord ID or creates a new user from OAuth data.

  ## Examples

      iex> find_or_create_from_discord(%{discord_id: "123", email: "user@example.com"})
      {:ok, %User{}}

  """
  @spec find_or_create_from_discord(map()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t() | term()}
  def find_or_create_from_discord(attrs) do
    find_or_create_from_oauth(
      attrs,
      :discord_id,
      &User.discord_oauth_changeset/2
    )
  end

  @doc """
  Finds a user by Apple ID or creates a new user from OAuth data.

  ## Examples

      iex> find_or_create_from_apple(%{apple_id: "123", email: "user@example.com"})
      {:ok, %User{}}

  """
  @spec find_or_create_from_apple(map()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t() | term()}
  def find_or_create_from_apple(attrs) do
    find_or_create_from_oauth(
      attrs,
      :apple_id,
      &User.apple_oauth_changeset/2
    )
  end

  @doc """
  Finds a user by Google ID or creates a new user from OAuth data.

  ## Examples

      iex> find_or_create_from_google(%{google_id: "123", email: "user@example.com"})
      {:ok, %User{}}

  """
  @spec find_or_create_from_google(map()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t() | term()}
  def find_or_create_from_google(attrs) do
    find_or_create_from_oauth(
      attrs,
      :google_id,
      &User.google_oauth_changeset/2
    )
  end

  @doc """
  Finds a user by Facebook ID or creates a new user from OAuth data.

  ## Examples

      iex> find_or_create_from_facebook(%{facebook_id: "123", email: "user@example.com"})
      {:ok, %User{}}

  """
  @spec find_or_create_from_facebook(map()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t() | term()}
  def find_or_create_from_facebook(attrs) do
    find_or_create_from_oauth(
      attrs,
      :facebook_id,
      &User.facebook_oauth_changeset/2
    )
  end

  @doc """
  Finds a user by GitHub ID or creates a new user from OAuth data.

  ## Examples

      iex> find_or_create_from_github(%{github_id: "123", email: "user@example.com"})
      {:ok, %User{}}

  """
  @spec find_or_create_from_github(map()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t() | term()}
  def find_or_create_from_github(attrs) do
    find_or_create_from_oauth(
      attrs,
      :github_id,
      &User.github_oauth_changeset/2
    )
  end

  @doc """
  Finds a user by Steam ID or creates a new user from Steam OpenID data.

  ## Examples

      iex> find_or_create_from_steam(%{steam_id: "12345", email: "user@example.com"})
      {:ok, %User{}}

  """
  @spec find_or_create_from_steam(map()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t() | term()}
  def find_or_create_from_steam(attrs) do
    find_or_create_from_oauth(
      attrs,
      :steam_id,
      &User.steam_oauth_changeset/2
    )
  end

  defp get_user_by_device_id(device_id) when is_binary(device_id) do
    Accounts.get_user_by_field(:device_id, device_id)
  end

  @doc """
  Finds or creates a user associated with the given device_id.

  If a user already exists with the device_id we return it. Otherwise we
  create an anonymous confirmed user and attach the device_id.
  """
  @spec find_or_create_from_device(String.t()) ::
          {:ok, User.t()} | {:error, :disabled | Ecto.Changeset.t() | term()}
  @spec find_or_create_from_device(String.t(), map()) ::
          {:ok, User.t()} | {:error, :disabled | Ecto.Changeset.t() | term()}
  def find_or_create_from_device(device_id, attrs \\ %{}) when is_binary(device_id) do
    if Accounts.device_auth_enabled?() do
      do_find_or_create_from_device(device_id, attrs)
    else
      {:error, :disabled}
    end
  end

  defp do_find_or_create_from_device(device_id, attrs) do
    case get_user_by_device_id(device_id) do
      %User{} = user ->
        {:ok, user}

      nil ->
        # Create a new anonymous user for the device. Allow callers to
        # specify optional display_name/metadata via attrs.
        attrs =
          attrs
          |> Map.new(fn {k, v} -> {to_string(k), v} end)
          |> Map.put_new("display_name", nil)

        is_first_user = Registration.first_user?()

        changeset_fun = fn attrs ->
          %User{}
          |> User.device_changeset(attrs)
          |> User.username_changeset(attrs)
          |> Registration.maybe_make_first_user_admin(is_first_user)
          |> Registration.maybe_deactivate_new_user(is_first_user)
          |> User.attach_device_changeset(%{device_id: device_id})
        end

        with {:ok, attrs} <- Registration.run_before_user_register(changeset_fun, attrs),
             {:ok, user} = ok <-
               Registration.insert_user_with_username_retry(changeset_fun, attrs) do
          Accounts.invalidate_users_count_cache()

          Gamend.Async.run(fn ->
            Gamend.Hooks.internal_call(:after_user_register, [user])
          end)

          ok
        end
    end
  end

  @doc """
  Attach a device_id to an existing user record. Returns {:ok, user} or
  {:error, changeset} if the device_id is already used.
  """
  @spec attach_device_to_user(User.t(), String.t()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def attach_device_to_user(%User{} = user, device_id) when is_binary(device_id) do
    case user
         |> User.attach_device_changeset(%{device_id: device_id})
         |> Repo.update() do
      {:ok, %User{} = updated} = ok ->
        Accounts.invalidate_user_cache(user)
        Accounts.invalidate_user_cache(updated)
        ok

      other ->
        other
    end
  end

  # Generic OAuth find or create helper
  defp find_or_create_from_oauth(attrs, provider_id_field, changeset_fn) do
    provider_id = Map.get(attrs, provider_id_field)
    email = Map.get(attrs, :email)

    result =
      cond do
        provider_id != nil ->
          handle_provider_id(provider_id, attrs, provider_id_field, changeset_fn)

        email != nil ->
          handle_by_email(email, attrs, provider_id_field, changeset_fn)

        true ->
          create_user_from_provider(attrs, changeset_fn)
      end

    with {:ok, %User{} = user} <- result do
      {:ok, maybe_mirror_avatar(user)}
    end
  end

  defp handle_provider_id(provider_id, attrs, provider_id_field, changeset_fn) do
    case Accounts.get_user_by_field(provider_id_field, provider_id) do
      %User{} = user ->
        attrs = scrub_attrs_for_update(user, attrs, provider_id_field)

        case user
             |> changeset_fn.(attrs)
             |> Repo.update() do
          {:ok, %User{} = updated} = ok ->
            Accounts.invalidate_user_cache(user)
            Accounts.invalidate_user_cache(updated)
            ok

          other ->
            other
        end

      nil ->
        handle_provider_id_missing(attrs, provider_id_field, changeset_fn)
    end
  end

  defp handle_provider_id_missing(attrs, provider_id_field, changeset_fn) do
    case Map.get(attrs, :email) && Accounts.get_user_by_email(Map.get(attrs, :email)) do
      %User{} = user -> link_provider_to_user(user, attrs, provider_id_field, changeset_fn)
      _ -> create_user_from_provider(attrs, changeset_fn)
    end
  end

  defp handle_by_email(email, attrs, provider_id_field, changeset_fn) do
    case Accounts.get_user_by_email(email) do
      nil -> create_user_from_provider(attrs, changeset_fn)
      %User{} = user -> link_provider_to_user(user, attrs, provider_id_field, changeset_fn)
    end
  end

  # Only attach a provider to a pre-existing account when the provider asserts
  # the email is verified — otherwise an attacker with a provider account
  # bearing the victim's email could take over the account. Callers set
  # `:email_verified` from the provider's claim (see oauth_user_params).
  defp link_provider_to_user(user, attrs, provider_id_field, changeset_fn) do
    if Map.get(attrs, :email_verified) == true do
      attrs = scrub_attrs_for_update(user, attrs, provider_id_field)
      claim(user, user |> changeset_fn.(attrs) |> drop_device_credential())
    else
      changeset =
        user
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.add_error(
          :email,
          "is already registered — sign in with your existing method, then link this provider from account settings"
        )

      {:error, %{changeset | action: :update}}
    end
  end

  # The provider's changeset confirms the email, and a provider vouching for
  # the address proves the inbox as an emailed login link does
  # (`Gamend.Accounts.Sessions.login_user_by_magic_link/1`). Like that link, it
  # must not keep what was set on an unconfirmed account before anyone proved
  # the inbox: whoever registered the address chose its password, and was
  # handed any token issued to it, and may not be its owner. So the password
  # goes, and every token is revoked, as the owner claims the account.
  defp claim(%User{confirmed_at: nil} = user, changeset) do
    result =
      changeset
      |> Ecto.Changeset.put_change(:hashed_password, nil)
      |> Accounts.update_user_and_delete_all_tokens()

    case result do
      {:ok, {%User{} = updated, _expired}} ->
        # Drop what the old struct was cached under (a retired device id among
        # it), then re-warm with the revoked one last, as the revocation does.
        Accounts.invalidate_user_cache(user)
        {:ok, Accounts.cache_user(updated)}

      other ->
        other
    end
  end

  defp claim(%User{} = user, changeset) do
    case Repo.update(changeset) do
      {:ok, %User{} = updated} = ok ->
        Accounts.invalidate_user_cache(user)
        Accounts.invalidate_user_cache(updated)
        ok

      other ->
        other
    end
  end

  # Linking a provider to an existing account retires that account's device
  # credential. The provider is linked as usual — the account keeps working, and
  # gains a sign-in method — but device auth is no longer one of its methods.
  #
  # The reason is that a device id is a bearer credential nobody has to prove
  # they still hold: it is a plain column lookup, unaffected by `token_version`,
  # and it may predate the link (an anonymous device account, or a value planted
  # before this account was ever claimed). Once a real identity is attached, that
  # standing key should not remain. Re-attach a device deliberately, while
  # authenticated, via `link_device_id/2`.
  defp drop_device_credential(%Ecto.Changeset{data: %User{device_id: nil}} = changeset),
    do: changeset

  defp drop_device_credential(%Ecto.Changeset{} = changeset),
    do: Ecto.Changeset.put_change(changeset, :device_id, nil)

  defp maybe_mirror_avatar(%User{profile_url: url} = user) when is_binary(url) and url != "" do
    unless our_stored_avatar?(user) do
      _ =
        Oban.insert(
          AvatarMirror.new(
            %{"user_id" => user.id, "source_url" => url},
            unique: [
              keys: [:user_id, :source_url],
              period: :infinity,
              states: @mirror_dedupe_states
            ]
          )
        )
    end

    user
  end

  defp maybe_mirror_avatar(user), do: user

  # Our stored avatars live under the `avatars/<user_id>/…` key namespace, so a
  # profile URL containing that segment is one we already host (uploaded or
  # previously mirrored) — anything else is an external provider link. The same
  # test decides what is ever shown (`User.public_avatar_url/1`).
  defp our_stored_avatar?(%User{id: id, profile_url: url}),
    do: User.hosted_avatar_url?(id, url)

  # True when the profile URL points at our own avatar storage but the object
  # is gone. Storage errors count as "not dangling": healing on uncertainty
  # would overwrite a stored avatar just because the backend blipped.
  defp dangling_stored_avatar?(%User{} = user) do
    with true <- our_stored_avatar?(user),
         key when is_binary(key) <- stored_avatar_key(user) do
      not Gamend.Storage.exists?(key)
    else
      _ -> false
    end
  rescue
    _ -> false
  end

  defp stored_avatar_key(%User{id: id, profile_url: url}) do
    case :binary.match(url, "avatars/#{id}") do
      {pos, _len} ->
        url
        |> binary_part(pos, byte_size(url) - pos)
        |> String.split("?", parts: 2)
        |> hd()

      :nomatch ->
        nil
    end
  end

  defp create_user_from_provider(attrs, changeset_fn) do
    is_first_user = Registration.first_user?()

    # For new user creation when provider didn't return an email, avoid
    # passing a nil email into the changeset (update_change will crash).
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
    attrs = if attrs["email"] in [nil, ""], do: Map.delete(attrs, "email"), else: attrs

    # Admin is granted via put_change (server-side), never cast from provider
    # attrs — the OAuth changesets must not accept :is_admin.
    changeset_fun = fn attrs ->
      %User{}
      |> changeset_fn.(attrs)
      |> User.username_changeset(attrs)
      |> Registration.maybe_make_first_user_admin(is_first_user)
      |> Registration.maybe_deactivate_new_user(is_first_user)
    end

    with {:ok, attrs} <- Registration.run_before_user_register(changeset_fun, attrs),
         {:ok, user} = ok <- Registration.insert_user_with_username_retry(changeset_fun, attrs) do
      Accounts.invalidate_users_count_cache()

      Gamend.Async.run(fn ->
        Gamend.Hooks.internal_call(:after_user_register, [user])
      end)

      ok
    end
  end

  # When updating an existing user from provider data we should avoid
  # destructive changes:
  # - Do not overwrite an existing, non-empty email (email is used for
  #   password-login accounts and should be preserved when present).
  # - Only set provider avatar if the user's avatar field for that provider
  #   is empty - prefer not to clobber user-set values.
  defp scrub_attrs_for_update(user, attrs, _provider_id_field) do
    attrs = Map.new(attrs)

    # Remove email if user already has one
    attrs =
      if user.email && user.email != "" do
        Map.delete(attrs, :email)
      else
        attrs
      end

    # Only set provider avatar if user doesn't already have one — unless the
    # one they "have" is a mirrored/uploaded avatar whose storage object no
    # longer exists (wiped volume, pruned bucket). A dangling stored URL would
    # otherwise block the provider avatar on every future sign-in, leaving the
    # account with a permanently broken image nothing can heal.
    # Store provider profile images/URLs in the generic `profile_url` field.
    provider_avatar_key = :profile_url

    attrs =
      cond do
        Map.get(user, provider_avatar_key) in [nil, ""] -> attrs
        dangling_stored_avatar?(user) -> attrs
        true -> Map.delete(attrs, provider_avatar_key)
      end

    # Also avoid overwriting an existing explicit display_name set by the user.
    if Map.get(user, :display_name) && Map.get(user, :display_name) != "" do
      Map.delete(attrs, :display_name)
    else
      attrs
    end
  end

  @doc """
  Link an OAuth provider to an existing user account. Updates the user
  via the provider's oauth changeset while being careful not to overwrite
  existing email or avatars.

  Example: link_account(user, %{discord_id: "123", profile_url: "https://..."}, :discord_id, &User.discord_oauth_changeset/2)
  """
  @spec link_account(User.t(), map(), atom(), (User.t(), map() -> Ecto.Changeset.t())) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t() | {:conflict, User.t()}}
  def link_account(%User{} = user, attrs, provider_id_field, changeset_fn) do
    attrs = scrub_attrs_for_update(user, attrs, provider_id_field)

    # Same rule as the find-or-create link path: gaining a provider identity
    # retires the account's standing device credential.
    changeset = user |> changeset_fn.(attrs) |> drop_device_credential()

    case Repo.update(changeset) do
      {:ok, %User{} = updated_user} ->
        Accounts.invalidate_user_cache(user)
        Accounts.invalidate_user_cache(updated_user)
        Accounts.invalidate_users_stats_cache()
        # Broadcast user update to user channel
        Accounts.broadcast_user_update(updated_user)

        {:ok, maybe_mirror_avatar(updated_user)}

      {:error, changeset} ->
        handle_link_error(user, attrs, provider_id_field, changeset)
    end
  end

  defp handle_link_error(user, attrs, provider_id_field, changeset) do
    # If the update failed due to the provider ID being already taken,
    # return a conflict with the existing account so the UI can guide
    # the user (e.g., delete the other account or sign into it).
    provider_value = Map.get(attrs, provider_id_field)

    if provider_value do
      case Accounts.get_user_by_field(provider_id_field, provider_value) do
        %User{} = other_user when other_user.id != user.id ->
          {:error, {:conflict, other_user}}

        _ ->
          {:error, changeset}
      end
    else
      {:error, changeset}
    end
  end

  @doc """
  Link a device_id to an existing user account. This allows the user to
  authenticate using the device_id in addition to their OAuth providers.

  Returns {:ok, user} on success or {:error, changeset} if the device_id
  is already used by another account.
  """
  @spec link_device_id(User.t(), String.t()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def link_device_id(%User{} = user, device_id) when is_binary(device_id) do
    changeset = User.attach_device_changeset(user, %{device_id: device_id})

    case Repo.update(changeset) do
      {:ok, %User{} = updated_user} ->
        Accounts.invalidate_user_cache(user)
        Accounts.invalidate_user_cache(updated_user)
        Accounts.invalidate_users_stats_cache()
        # Broadcast user update to user channel
        Accounts.broadcast_user_update(updated_user)
        {:ok, updated_user}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Unlink the device_id from a user's account.

  Returns {:ok, user} when successful or {:error, reason}.

  Guard: we only allow unlinking when the user will still have at least
  one authentication method remaining (OAuth provider or password).
  This prevents users losing all login methods unexpectedly.
  """
  @spec unlink_device_id(User.t()) ::
          {:ok, User.t()} | {:error, :last_auth_method | Ecto.Changeset.t()}
  def unlink_device_id(%User{} = user) do
    # If device_id is already nil, just return success
    if user.device_id in [nil, ""] do
      {:ok, user}
    else
      # Check if user has at least one OAuth provider or password
      providers = [:discord_id, :apple_id, :google_id, :facebook_id, :github_id, :steam_id]

      has_provider =
        Enum.any?(providers, fn f ->
          case Map.get(user, f) do
            v when is_binary(v) -> String.trim(v) != ""
            _ -> false
          end
        end)

      has_password = Accounts.has_password?(user)

      if has_provider or has_password do
        changes = %{device_id: nil}

        case user |> Ecto.Changeset.change(changes) |> Repo.update() do
          {:ok, %User{} = updated_user} ->
            Accounts.invalidate_user_cache(user)
            Accounts.invalidate_user_cache(updated_user)
            Accounts.invalidate_users_stats_cache()
            # Broadcast user update to user channel
            Accounts.broadcast_user_update(updated_user)
            {:ok, updated_user}

          {:error, changeset} ->
            {:error, changeset}
        end
      else
        {:error, :last_auth_method}
      end
    end
  end

  @doc """
  Unlink an OAuth provider from a user's account.

  provider should be one of :discord, :apple, :google, :facebook, :github, :steam.
  This will return {:ok, user} when successful or {:error, reason}.

  Guard: we only allow unlinking when the user will still have at least
  one other social provider remaining. This prevents users losing all
  social logins unexpectedly.
  """
  @spec unlink_provider(
          User.t(),
          :discord | :apple | :google | :facebook | :github | :steam
        ) ::
          {:ok, User.t()} | {:error, :last_provider | Ecto.Changeset.t() | term()}
  def unlink_provider(%User{} = user, provider)
      when provider in [:discord, :apple, :google, :facebook, :github, :steam] do
    provider_field = provider_field(provider)

    # Count remaining linked providers (only non-empty, non-nil strings)
    providers = [:discord_id, :apple_id, :google_id, :facebook_id, :github_id, :steam_id]

    present =
      Enum.count(providers, fn f ->
        case Map.get(user, f) do
          v when is_binary(v) -> String.trim(v) != ""
          _ -> false
        end
      end)

    if present <= 1 do
      {:error, :last_provider}
    else
      changes = %{provider_field => nil}

      # If unlinking discord and profile_url is a discord CDN URL, clear it
      changes =
        if provider == :discord && user.profile_url &&
             String.contains?(user.profile_url, "cdn.discordapp.com/avatars") do
          Map.put(changes, :profile_url, nil)
        else
          changes
        end

      case user
           |> Ecto.Changeset.change(changes)
           |> Repo.update() do
        {:ok, updated_user} ->
          Accounts.invalidate_user_cache(user)
          Accounts.invalidate_user_cache(updated_user)
          Accounts.invalidate_users_stats_cache()
          # Broadcast user update to user channel
          Accounts.broadcast_user_update(updated_user)
          {:ok, updated_user}

        error ->
          error
      end
    end
  end

  defp provider_field(:discord), do: :discord_id
  defp provider_field(:apple), do: :apple_id
  defp provider_field(:google), do: :google_id
  defp provider_field(:facebook), do: :facebook_id
  defp provider_field(:github), do: :github_id
  defp provider_field(:steam), do: :steam_id
end
