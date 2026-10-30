defmodule Gamend.Accounts.Profile do
  @moduledoc """
  Changing what a user shows the world: display name, username, avatar, age and
  metadata, and the storage that goes with them.

  Split out of `Gamend.Accounts`, which still exposes every function here under
  the same name.
  """

  import Ecto.Query, warn: false
  require Logger
  alias Gamend.Accounts.AgePolicy
  alias Gamend.Accounts.User
  alias Gamend.Repo

  # Upper bound on cross-node staleness for cached user structs: explicit
  # invalidations propagate immediately via `Gamend.Cache.invalidate/1`,
  # and this TTL caps staleness if an invalidation broadcast is ever missed.
  alias Gamend.Accounts

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user display_name.
  """
  @spec change_user_display_name(User.t()) :: Ecto.Changeset.t()
  @spec change_user_display_name(User.t(), map()) :: Ecto.Changeset.t()
  def change_user_display_name(user, attrs \\ %{}) do
    User.display_name_changeset(user, attrs)
  end

  @spec change_username(User.t()) :: Ecto.Changeset.t()
  @spec change_username(User.t(), map()) :: Ecto.Changeset.t()
  def change_username(user, attrs \\ %{}) do
    User.username_changeset(user, attrs)
  end

  @doc """
  Set the user's avatar URL (`profile_url`), typically after an upload confirmed
  by `Gamend.Storage`. Same cache/broadcast/hook path as other profile edits.
  """
  @spec update_user_avatar(User.t(), String.t()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def update_user_avatar(%User{} = user, url) when is_binary(url) do
    case User.avatar_changeset(user, %{"profile_url" => url}) |> Repo.update() do
      {:ok, updated} = ok ->
        Accounts.invalidate_user_cache(user)
        Accounts.invalidate_user_cache(updated)
        Accounts.broadcast_user_update(updated)
        Accounts.broadcast_member_update(updated)

        Gamend.Async.run(fn ->
          Gamend.Hooks.internal_call(:after_user_updated, [updated])
        end)

        ok

      err ->
        err
    end
  end

  @doc """
  Removes every stored object belonging to `user_id`.

  Best-effort, like `prune_user_avatars/2`: a storage backend that is down must
  not block an account deletion that has already happened at the database level.
  """
  @spec delete_user_storage(Ecto.UUID.t()) :: :ok
  def delete_user_storage(user_id) when is_binary(user_id) do
    case Gamend.Storage.delete_prefix("avatars/#{user_id}/") do
      {:ok, _count} -> :ok
      {:error, reason} -> log_storage_cleanup_failure(user_id, reason)
    end
  rescue
    e -> log_storage_cleanup_failure(user_id, e)
  end

  defp log_storage_cleanup_failure(user_id, reason) do
    Logger.warning("storage cleanup failed user=#{user_id}: #{inspect(reason)}")
    :ok
  end

  @doc """
  Delete a user's stored avatar objects except `keep_key`.

  Each new avatar gets a fresh random key (`avatars/<user_id>/<rand><ext>`), so
  without this the previous upload or mirror copy lingers in storage forever.
  Best-effort: a failed cleanup leaves the old object rather than failing the
  update that already succeeded.
  """
  @spec prune_user_avatars(Ecto.UUID.t(), String.t()) :: :ok
  def prune_user_avatars(user_id, keep_key) when is_binary(user_id) and is_binary(keep_key) do
    [prefix: "avatars/#{user_id}/", limit: 100]
    |> Gamend.Storage.list_objects()
    |> Enum.reject(&(&1.key == keep_key))
    |> Enum.each(fn %{key: key} -> Gamend.Storage.delete(key) end)

    :ok
  rescue
    e ->
      Logger.warning("avatar prune failed user=#{user_id}: #{inspect(e)}")
      :ok
  end

  @doc """
  Merges `patch` into the user's metadata, leaving untouched every key it does
  not mention.

  The counterpart to `Gamend.Lobbies.merge_metadata/2`, and for the same
  reason: `metadata` is one shared map, so a writer that replaces it wipes keys
  belonging to code it has never heard of. Top-level merge, serialized so two
  concurrent merges cannot lose each other.
  """
  @spec merge_metadata(User.t(), map()) :: {:ok, User.t()} | {:error, term()}
  def merge_metadata(%User{} = user, patch) when is_map(patch) do
    result =
      Gamend.Lock.serialize("user_metadata", user.id, fn ->
        case Repo.get(User, user.id) do
          nil ->
            {:error, :not_found}

          current ->
            merged =
              Map.merge(
                current.metadata || %{},
                Map.new(patch, fn {k, v} -> {to_string(k), v} end)
              )

            current
            |> Ecto.Changeset.change(metadata: merged)
            |> Repo.update()
        end
      end)

    case result do
      {:ok, {:ok, updated}} ->
        Accounts.invalidate_user_cache(updated)
        {:ok, updated}

      {:ok, other} ->
        other

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Updates the user's display name and broadcasts the change.
  """
  @spec update_user_display_name(User.t(), map()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def update_user_display_name(%User{} = user, attrs) do
    case Gamend.Hooks.internal_call(:before_user_update, [user, attrs]) do
      {:ok, returned} ->
        attrs_to_use =
          if is_map(returned) and not is_struct(returned) do
            returned
          else
            attrs
          end

        case User.display_name_changeset(user, attrs_to_use) |> Repo.update() do
          {:ok, updated} = ok ->
            Accounts.invalidate_user_cache(user)
            Accounts.invalidate_user_cache(updated)
            Accounts.broadcast_user_update(updated)
            Accounts.broadcast_member_update(updated)

            Gamend.Async.run(fn ->
              Gamend.Hooks.internal_call(:after_user_updated, [updated])
            end)

            ok

          err ->
            err
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Record a user's age answer and re-derive what it permits.

  Three things happen together, and they have to: the answer is stored, the
  denormalised `account_class` is recomputed from it, and `grandfathered_at` is
  cleared. That last one is the point — an account that predated the age gate
  stops being treated as an adult-by-default the moment it tells us what it
  actually is, in whichever direction that goes.

  Refuses with `{:error, :age_change_not_allowed}` when the answer would raise
  the user's age without a stronger signal than the one already recorded. See
  `AgePolicy.may_change_age?/4`: lowering is always allowed, because it only
  ever increases protection.

  `attrs` must carry `birth_year`, `birth_month` and `age_method`, and should
  carry `age_country` — without it the highest digital-consent age in the table
  applies, which is the safe reading but not always the right one.
  """
  @spec set_user_age(User.t(), map()) :: {:ok, User.t()} | {:error, term()}
  def set_user_age(%User{} = user, attrs) when is_map(attrs) do
    attrs = normalize_age_attrs(attrs)

    with {:ok, year} <- fetch_age_field(attrs, "birth_year"),
         {:ok, month} <- fetch_age_field(attrs, "birth_month"),
         method when is_binary(method) <- attrs["age_method"],
         true <- AgePolicy.may_change_age?(user, year, month, method) do
      country = attrs["age_country"] || user.age_country

      class =
        year
        |> AgePolicy.age_in_years(month, Date.utc_today())
        |> AgePolicy.class_for_age(country)

      changeset =
        user
        |> User.age_changeset(attrs)
        |> Ecto.Changeset.put_change(:account_class, Atom.to_string(class))
        |> Ecto.Changeset.put_change(
          :age_locked_at,
          DateTime.utc_now(:second)
        )
        |> Ecto.Changeset.put_change(:grandfathered_at, nil)

      case Repo.update(changeset) do
        {:ok, updated} = ok ->
          Accounts.invalidate_user_cache(user)
          Accounts.invalidate_user_cache(updated)
          ok

        err ->
          err
      end
    else
      false -> {:error, :age_change_not_allowed}
      :error -> {:error, :invalid_age}
      nil -> {:error, :invalid_age}
      other -> other
    end
  end

  # Accepts either string or atom keys, because this is reached from an RPC
  # payload and from internal callers.
  defp normalize_age_attrs(attrs) do
    Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
  end

  defp fetch_age_field(attrs, key) do
    case attrs[key] do
      value when is_integer(value) -> {:ok, value}
      value when is_binary(value) -> parse_age_integer(value)
      _ -> :error
    end
  end

  defp parse_age_integer(value) do
    case Integer.parse(value) do
      {parsed, ""} -> {:ok, parsed}
      _ -> :error
    end
  end

  @doc """
  Re-derive `account_class` for a user whose stored answer has not changed.

  An account graduates on the first of its birth month, and nothing writes to it
  on that day — the derivation is a function of the calendar, not of an event.
  Call this to bring the denormalised column back in step, from a scheduled
  sweep or on login.
  """
  @spec refresh_account_class(User.t()) :: {:ok, User.t()} | {:error, term()}
  def refresh_account_class(%User{} = user) do
    current = user.account_class
    derived = user |> AgePolicy.classify() |> Atom.to_string()

    if current == derived do
      {:ok, user}
    else
      user
      |> Ecto.Changeset.change(account_class: derived)
      |> Repo.update()
      |> case do
        {:ok, updated} = ok ->
          Accounts.invalidate_user_cache(updated)
          ok

        err ->
          err
      end
    end
  end

  @doc """
  Updates the user's unique username handle and broadcasts the change.

  Strict, unlike registration: an invalid or taken username returns
  `{:error, changeset}` with no generated fallback, so the player can pick
  again. Routed through the `before_user_update` hook pipeline, where games
  can forbid changes entirely or reject names (profanity, reserved words).
  """
  @spec update_username(User.t(), map()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t() | term()}
  def update_username(%User{} = user, attrs) do
    case Gamend.Hooks.internal_call(:before_user_update, [user, attrs]) do
      {:ok, returned} ->
        attrs_to_use =
          if is_map(returned) and not is_struct(returned) do
            returned
          else
            attrs
          end

        case User.username_changeset(user, attrs_to_use) |> Repo.update() do
          {:ok, updated} = ok ->
            Accounts.invalidate_user_cache(user)
            Accounts.invalidate_user_cache(updated)
            Accounts.broadcast_user_update(updated)
            Accounts.broadcast_member_update(updated)

            Gamend.Async.run(fn ->
              Gamend.Hooks.internal_call(:after_user_updated, [updated])
            end)

            ok

          err ->
            err
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
