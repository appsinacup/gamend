defmodule Gamend.KV do
  @moduledoc """
  Generic key/value storage.

  This is intentionally minimal and un-opinionated.

  If you want namespacing, encode it in `key` (e.g. `"my_game:key1"`).
  If you want per-user values, pass `user_id: ...` to `get/2`, `put/4`, and `delete/2`.
  If you want per-lobby values, pass `lobby_id: ...` to the same functions.
  You can also pass both to scope a key to a user within a lobby.

  This module uses the app cache (`Gamend.Cache`) as a best-effort read cache.
  Writes update the cache and deletes evict it.
  """

  import Ecto.Query

  alias Gamend.KV.Entry
  alias Gamend.Repo

  @typedoc """
  Value stored for a key. This is an arbitrary map and should contain JSON-serializable data.
  """
  @type value :: map()

  @typedoc """
  Metadata stored alongside a value. Typically a small map with auxiliary fields.
  """
  @type metadata :: map()

  @typedoc """
  Payload returned by `get/1` and `get/2`.
  """
  @type payload :: %{value: value(), metadata: metadata()}

  @typedoc """
  Attributes used when creating or updating entries.

  Expected keys (atom keys recommended):
  - `:key` — the entry key (`String.t()`)
    - `:user_id` — optional user id (`String.t()`)
    - `:lobby_id` — optional lobby id (`String.t()`)
  - `:value` — the stored value (`value()`)
  - `:metadata` — optional metadata (`metadata()`)
  """
  @type attrs :: %{
          required(:key) => String.t(),
          optional(:user_id) => String.t(),
          optional(:lobby_id) => String.t(),
          required(:value) => value(),
          optional(:metadata) => metadata()
        }

  @typedoc """
  Options accepted by `list_entries/1` and `count_entries/1`.

  Keys (all optional):
  - `:page` — page number (`pos_integer()`, defaults to `1`)
  - `:page_size` — page size (`pos_integer()`, defaults to `50`)
  - `:user_id` — filter by user id (`Ecto.UUID.t()`)
  - `:lobby_id` — filter by lobby id (`Ecto.UUID.t()`)
  - `:global_only` — when true, only return global entries (where `user_id` and `lobby_id` are `nil`) (`boolean()`)
  - `:key` — substring filter (`String.t()`)
  """
  @type list_opts :: [
          page: pos_integer(),
          page_size: pos_integer(),
          user_id: Ecto.UUID.t(),
          lobby_id: Ecto.UUID.t(),
          global_only: boolean(),
          key: String.t()
        ]

  @pubsub Gamend.PubSub

  @doc """
  Subscribe the current process to changes for a specific key/scope.
  """
  @spec subscribe(String.t(), keyword()) :: :ok | {:error, term()}
  def subscribe(key, opts \\ []) when is_binary(key) and is_list(opts) do
    Phoenix.PubSub.subscribe(
      @pubsub,
      topic(key, Keyword.get(opts, :user_id), Keyword.get(opts, :lobby_id))
    )
  end

  @doc """
  Unsubscribe the current process from changes for a specific key/scope.
  """
  @spec unsubscribe(String.t(), keyword()) :: :ok | {:error, term()}
  def unsubscribe(key, opts \\ []) when is_binary(key) and is_list(opts) do
    Phoenix.PubSub.unsubscribe(
      @pubsub,
      topic(key, Keyword.get(opts, :user_id), Keyword.get(opts, :lobby_id))
    )
  end

  defp topic(key, nil, nil), do: "kv:global:#{key}"
  defp topic(key, user_id, nil) when is_binary(user_id), do: "kv:user:#{user_id}:#{key}"
  defp topic(key, nil, lobby_id) when is_binary(lobby_id), do: "kv:lobby:#{lobby_id}:#{key}"

  defp topic(key, user_id, lobby_id) when is_binary(user_id) and is_binary(lobby_id),
    do: "kv:user_lobby:#{user_id}:#{lobby_id}:#{key}"

  defp entries_cache_version(:all) do
    Gamend.Cache.get!({:kv, :entries_version, :all}) || 1
  end

  defp entries_cache_version({:user, user_id}) when is_binary(user_id) do
    Gamend.Cache.get!({:kv, :entries_version, {:user, user_id}}) || 1
  end

  defp entries_cache_version({:lobby, lobby_id}) when is_binary(lobby_id) do
    Gamend.Cache.get!({:kv, :entries_version, {:lobby, lobby_id}}) || 1
  end

  defp entries_cache_version({:user_lobby, user_id, lobby_id})
       when is_binary(user_id) and is_binary(lobby_id) do
    Gamend.Cache.get!({:kv, :entries_version, {:user_lobby, user_id, lobby_id}}) || 1
  end

  defp scope_for_cache(nil, nil), do: :all
  defp scope_for_cache(user_id, nil) when is_binary(user_id), do: {:user, user_id}
  defp scope_for_cache(nil, lobby_id) when is_binary(lobby_id), do: {:lobby, lobby_id}

  defp scope_for_cache(user_id, lobby_id) when is_binary(user_id) and is_binary(lobby_id) do
    {:user_lobby, user_id, lobby_id}
  end

  defp invalidate_entries_cache(nil, nil) do
    _ = Gamend.Cache.bump_version({:kv, :entries_version, :all})
    :ok
  end

  defp invalidate_entries_cache(user_id, nil) when is_binary(user_id) do
    _ = Gamend.Cache.bump_version({:kv, :entries_version, :all})
    _ = Gamend.Cache.bump_version({:kv, :entries_version, {:user, user_id}})
    :ok
  end

  defp invalidate_entries_cache(nil, lobby_id) when is_binary(lobby_id) do
    _ = Gamend.Cache.bump_version({:kv, :entries_version, :all})
    _ = Gamend.Cache.bump_version({:kv, :entries_version, {:lobby, lobby_id}})
    :ok
  end

  defp invalidate_entries_cache(user_id, lobby_id)
       when is_binary(user_id) and is_binary(lobby_id) do
    _ = Gamend.Cache.bump_version({:kv, :entries_version, :all})
    _ = Gamend.Cache.bump_version({:kv, :entries_version, {:user, user_id}})
    _ = Gamend.Cache.bump_version({:kv, :entries_version, {:lobby, lobby_id}})

    _ =
      Gamend.Cache.bump_version({:kv, :entries_version, {:user_lobby, user_id, lobby_id}})

    :ok
  end

  @doc """
  Retrieve the value and metadata stored for `key`.

  Pass `user_id: id` or `lobby_id: id` in `opts` to scope the lookup.
  Returns `{:ok, %{value: map(), metadata: map()}}` when found, or `:error` when not present.
  """
  @spec get(String.t()) :: {:ok, payload()} | :error
  @spec get(String.t(), keyword()) :: {:ok, payload()} | :error
  def get(key, opts \\ []) when is_binary(key) and is_list(opts) do
    user_id = Keyword.get(opts, :user_id)
    lobby_id = Keyword.get(opts, :lobby_id)

    cached = Gamend.Cache.get!(cache_key(key, user_id, lobby_id))

    if is_map(cached) and Map.has_key?(cached, :value) and Map.has_key?(cached, :metadata) do
      {:ok, cached}
    else
      case fetch_entry(key, user_id, lobby_id) do
        nil ->
          :error

        %Entry{value: value, metadata: metadata} ->
          payload = %{value: value, metadata: metadata}

          Gamend.Async.run(fn ->
            _ =
              Gamend.Cache.put(
                cache_key(key, user_id, lobby_id),
                payload,
                ttl: Gamend.Cache.ttl()
              )

            :ok
          end)

          {:ok, payload}
      end
    end
  end

  @spec put(String.t(), value()) :: {:ok, Entry.t()} | {:error, Ecto.Changeset.t()}
  @spec put(String.t(), value(), metadata()) :: {:ok, Entry.t()} | {:error, Ecto.Changeset.t()}
  def put(key, value, metadata \\ %{})
      when is_binary(key) and is_map(value) and is_map(metadata) do
    put(key, value, metadata, [])
  end

  @doc """
  Store `value` with optional `metadata` at `key`.

  When using the 4-arity, supported options include `user_id: id` or `lobby_id: id` to scope
  the entry.
  Returns `{:ok, entry}` on success or `{:error, changeset}` on validation failure.
  """
  @spec put(String.t(), value(), metadata(), list_opts()) ::
          {:ok, Entry.t()} | {:error, Ecto.Changeset.t()}
  def put(key, value, metadata, opts)
      when is_binary(key) and is_map(value) and is_map(metadata) and is_list(opts) do
    user_id = Keyword.get(opts, :user_id)
    lobby_id = Keyword.get(opts, :lobby_id)
    now = DateTime.utc_now(:second)

    changeset =
      Entry.changeset(%Entry{}, %{
        key: key,
        user_id: user_id,
        lobby_id: lobby_id,
        value: value,
        metadata: metadata
      })

    try do
      case Repo.insert(changeset,
             on_conflict: [set: [value: value, metadata: metadata, updated_at: now]],
             conflict_target: kv_conflict_target(user_id, lobby_id)
           ) do
        {:ok, entry} ->
          _ = cache_put(key, user_id, lobby_id, entry)
          _ = invalidate_entries_cache(user_id, lobby_id)
          _ = broadcast_kv_updated(key, user_id, lobby_id, value, metadata)
          {:ok, entry}

        {:error, _} = error ->
          error
      end
    rescue
      e in Ecto.ConstraintError ->
        if Map.get(e, :type) == :foreign_key do
          changeset =
            changeset
            |> Ecto.Changeset.add_error(:user_id, "does not exist")
            |> Ecto.Changeset.add_error(:lobby_id, "does not exist")

          {:error, changeset}
        else
          reraise(e, __STACKTRACE__)
        end
    end
  end

  # Determine the correct partial unique index target based on scope
  defp kv_conflict_target(nil, nil) do
    {:unsafe_fragment, "(key) WHERE user_id IS NULL AND lobby_id IS NULL"}
  end

  defp kv_conflict_target(_user_id, nil) do
    {:unsafe_fragment, "(user_id, key) WHERE user_id IS NOT NULL AND lobby_id IS NULL"}
  end

  defp kv_conflict_target(nil, _lobby_id) do
    {:unsafe_fragment, "(lobby_id, key) WHERE lobby_id IS NOT NULL AND user_id IS NULL"}
  end

  defp kv_conflict_target(_user_id, _lobby_id) do
    {:unsafe_fragment,
     "(user_id, lobby_id, key) WHERE user_id IS NOT NULL AND lobby_id IS NOT NULL"}
  end

  @doc """
  Delete the entry at `key`.

  Pass `user_id: id` or `lobby_id: id` in `opts` to delete a scoped key. Returns `:ok`.
  """
  @spec delete(String.t()) :: :ok
  @spec delete(String.t(), keyword()) :: :ok
  def delete(key, opts \\ []) when is_binary(key) and is_list(opts) do
    user_id = Keyword.get(opts, :user_id)
    lobby_id = Keyword.get(opts, :lobby_id)

    _ = Gamend.Cache.invalidate(cache_key(key, user_id, lobby_id))

    _ = Repo.delete_all(entry_query(key, user_id, lobby_id))
    _ = invalidate_entries_cache(user_id, lobby_id)
    _ = broadcast_kv_deleted(key, user_id, lobby_id)
    :ok
  end

  @doc """
  Delete every entry scoped to a lobby, in one statement: for deleting the lobby.

  The per-entry cache invalidations and `kv_deleted` broadcasts wait for the
  enclosing transaction to commit (`Gamend.AfterCommit`). One `delete/2` per
  entry cost a statement and two cache round-trips each while the caller held
  the lobby's lock. Returns the number of entries deleted.
  """
  @spec delete_lobby_entries(Ecto.UUID.t()) :: non_neg_integer()
  def delete_lobby_entries(lobby_id) when is_binary(lobby_id) do
    scoped = where(Entry, [e], e.lobby_id == ^lobby_id)
    entries = scoped |> select([e], {e.key, e.user_id}) |> Repo.all()
    {count, _} = Repo.delete_all(scoped)

    Gamend.AfterCommit.defer(fn ->
      Enum.each(entries, fn {key, user_id} ->
        _ = Gamend.Cache.invalidate(cache_key(key, user_id, lobby_id))
        _ = broadcast_kv_deleted(key, user_id, lobby_id)
      end)

      entries
      |> Enum.map(&elem(&1, 1))
      |> Enum.uniq()
      |> Enum.each(&invalidate_entries_cache(&1, lobby_id))
    end)

    count
  end

  @doc """
  Delete every entry a user holds inside one lobby.

  Called when a user stops being a member of a lobby, so per-member lobby state
  (ready flags, loadouts, character picks) does not survive a leave and rejoin.
  Entries scoped to the lobby alone, or to the user alone, are left untouched.

  Returns the number of entries deleted.
  """
  @spec delete_user_lobby_entries(Ecto.UUID.t(), Ecto.UUID.t()) :: non_neg_integer()
  def delete_user_lobby_entries(user_id, lobby_id)
      when is_binary(user_id) and is_binary(lobby_id) do
    # The per-entry cache is keyed by key name, so the keys must be read before
    # the rows are deleted.
    keys =
      Entry
      |> where([e], e.user_id == ^user_id and e.lobby_id == ^lobby_id)
      |> select([e], e.key)
      |> Repo.all()

    if keys == [] do
      0
    else
      {count, _} =
        Entry
        |> where([e], e.user_id == ^user_id and e.lobby_id == ^lobby_id)
        |> Repo.delete_all()

      Enum.each(keys, fn key ->
        _ = Gamend.Cache.invalidate(cache_key(key, user_id, lobby_id))
        _ = broadcast_kv_deleted(key, user_id, lobby_id)
      end)

      _ = invalidate_entries_cache(user_id, lobby_id)

      count
    end
  end

  @doc """
  List key/value entries with optional pagination and filtering.

  Supported options: `:page`, `:page_size`, `:user_id`, `:lobby_id`, `:global_only`,
  and `:key` (substring filter).
  See `t:list_opts/0` for the expected option types.
  Returns a list of `Entry` structs ordered by most recently updated.
  """
  @spec list_entries() :: [Entry.t()]
  @spec list_entries(list_opts()) :: [Entry.t()]
  def list_entries(opts \\ []) when is_list(opts) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 50)
    global_only = Keyword.get(opts, :global_only, false)
    user_id = if(global_only, do: nil, else: Keyword.get(opts, :user_id))
    lobby_id = if(global_only, do: nil, else: Keyword.get(opts, :lobby_id))
    key_filter = normalize_key_filter(Keyword.get(opts, :key))

    version = entries_cache_version(scope_for_cache(user_id, lobby_id))

    cache_key =
      {:kv, :list_entries, version, user_id, lobby_id, global_only, key_filter, page, page_size}

    case Gamend.Cache.get!(cache_key) do
      entries when is_list(entries) ->
        entries

      _ ->
        query =
          from(e in Entry,
            order_by: [desc: e.updated_at, desc: e.id]
          )
          |> Gamend.Query.filter_id(:user_id, user_id)
          |> Gamend.Query.filter_id(:lobby_id, lobby_id)
          |> maybe_filter_global_only(global_only)
          |> maybe_filter_key(key_filter)

        entries =
          Repo.all(
            from(e in query,
              offset: ^((page - 1) * page_size),
              limit: ^page_size
            )
          )

        Gamend.Async.run(fn ->
          _ = Gamend.Cache.put(cache_key, entries, ttl: Gamend.Cache.ttl())
          :ok
        end)

        entries
    end
  end

  @doc """
  Count the number of entries that match the optional filter.

  Accepts the same options as `list_entries/1` (see `t:list_opts/0`). Returns a non-negative integer.
  """
  @spec count_entries() :: non_neg_integer()
  @spec count_entries(list_opts()) :: non_neg_integer()
  def count_entries(opts \\ []) when is_list(opts) do
    global_only = Keyword.get(opts, :global_only, false)
    user_id = if(global_only, do: nil, else: Keyword.get(opts, :user_id))
    lobby_id = if(global_only, do: nil, else: Keyword.get(opts, :lobby_id))
    key_filter = normalize_key_filter(Keyword.get(opts, :key))

    version = entries_cache_version(scope_for_cache(user_id, lobby_id))

    cache_key = {:kv, :count_entries, version, user_id, lobby_id, global_only, key_filter}

    case Gamend.Cache.get!(cache_key) do
      count when is_integer(count) ->
        count

      _ ->
        count =
          Entry
          |> Gamend.Query.filter_id(:user_id, user_id)
          |> Gamend.Query.filter_id(:lobby_id, lobby_id)
          |> maybe_filter_global_only(global_only)
          |> maybe_filter_key(key_filter)
          |> Repo.aggregate(:count)

        Gamend.Async.run(fn ->
          _ = Gamend.Cache.put(cache_key, count, ttl: Gamend.Cache.ttl())
          :ok
        end)

        count
    end
  end

  @doc """
  Fetch an `Entry` by its `id`.
  Returns the `Entry` struct or `nil` if not found.
  """
  @spec get_entry(Ecto.UUID.t()) :: Entry.t() | nil
  def get_entry(id) do
    Repo.get_uuid(Entry, id)
  end

  @doc """
  Create a new `Entry` from `attrs` (expecting `key`, optional `user_id`/`lobby_id`,
  `value`, `metadata`).
  Returns `{:ok, entry}` or `{:error, changeset}`.
  """
  @spec create_entry(attrs()) :: {:ok, Entry.t()} | {:error, Ecto.Changeset.t()}
  def create_entry(attrs) when is_map(attrs) do
    user_id = attrs[:user_id] || attrs["user_id"]

    with :ok <- check_kv_entries_limit(user_id) do
      do_create_entry(attrs)
    end
  end

  defp check_kv_entries_limit(nil), do: :ok

  defp check_kv_entries_limit(user_id) do
    max = Gamend.Limits.get(:max_kv_entries_per_user)
    current = count_entries(user_id: user_id)

    if current >= max do
      {:error, :too_many_entries}
    else
      :ok
    end
  end

  defp do_create_entry(attrs) do
    changeset = Entry.changeset(%Entry{}, attrs)

    try do
      case Repo.insert(changeset) do
        {:ok, entry} ->
          _ = cache_put(entry.key, entry.user_id, entry.lobby_id, entry)
          _ = invalidate_entries_cache(entry.user_id, entry.lobby_id)
          _ = broadcast_kv_updated(entry)
          {:ok, entry}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:error, changeset}
      end
    rescue
      e in Ecto.ConstraintError ->
        case Map.get(e, :type) do
          :foreign_key ->
            changeset =
              changeset
              |> maybe_add_fk_error(:user_id)
              |> maybe_add_fk_error(:lobby_id)

            {:error, changeset}

          :unique ->
            {:error, Ecto.Changeset.add_error(changeset, :key, "has already been taken")}

          _ ->
            reraise(e, __STACKTRACE__)
        end
    end
  end

  @doc """
  Update an existing entry by `id` with `attrs`.
  Returns `{:ok, entry}`, `{:error, :not_found}` if missing, or `{:error, changeset}` on validation error.
  """
  @spec update_entry(Ecto.UUID.t(), attrs()) ::
          {:ok, Entry.t()} | {:error, :not_found} | {:error, Ecto.Changeset.t()}
  def update_entry(id, attrs) when is_map(attrs) do
    case Repo.get_uuid(Entry, id) do
      nil ->
        {:error, :not_found}

      %Entry{} = entry ->
        old_cache_key = cache_key(entry.key, entry.user_id, entry.lobby_id)

        changeset = Entry.changeset(entry, attrs)

        try do
          case Repo.update(changeset) do
            {:ok, updated} ->
              if cache_key(updated.key, updated.user_id, updated.lobby_id) != old_cache_key do
                Gamend.Async.run(fn ->
                  _ = Gamend.Cache.invalidate(old_cache_key)
                  :ok
                end)
              end

              _ = cache_put(updated.key, updated.user_id, updated.lobby_id, updated)
              _ = invalidate_entries_cache(entry.user_id, entry.lobby_id)
              _ = invalidate_entries_cache(updated.user_id, updated.lobby_id)

              if cache_key(updated.key, updated.user_id, updated.lobby_id) != old_cache_key do
                _ = broadcast_kv_deleted(entry.key, entry.user_id, entry.lobby_id)
              end

              _ = broadcast_kv_updated(updated)
              {:ok, updated}

            {:error, %Ecto.Changeset{} = changeset} ->
              {:error, changeset}
          end
        rescue
          e in Ecto.ConstraintError ->
            cond do
              Map.get(e, :type) == :foreign_key ->
                changeset =
                  changeset
                  |> maybe_add_fk_error(:user_id)
                  |> maybe_add_fk_error(:lobby_id)

                {:error, changeset}

              Map.get(e, :type) in [:unique, :unique_constraint] ->
                {:error, Ecto.Changeset.add_error(changeset, :key, "has already been taken")}

              true ->
                reraise(e, __STACKTRACE__)
            end
        end
    end
  end

  @doc """
  Delete an entry by its `id`.

  Returns `:ok` whether or not the entry existed.
  """
  @spec delete_entry(Ecto.UUID.t()) :: :ok
  def delete_entry(id) do
    case Repo.get_uuid(Entry, id) do
      nil ->
        :ok

      %Entry{} = entry ->
        _ = Gamend.Cache.invalidate(cache_key(entry.key, entry.user_id, entry.lobby_id))

        _ = Repo.delete(entry)
        _ = invalidate_entries_cache(entry.user_id, entry.lobby_id)
        _ = broadcast_kv_deleted(entry.key, entry.user_id, entry.lobby_id)
        :ok
    end
  end

  defp broadcast_kv_updated(%Entry{} = entry) do
    broadcast_kv_updated(entry.key, entry.user_id, entry.lobby_id, entry.value, entry.metadata)
  end

  defp broadcast_kv_updated(key, user_id, lobby_id, value, metadata) do
    Gamend.Broadcast.publish(
      topic(key, user_id, lobby_id),
      {:kv_updated,
       %{
         key: key,
         user_id: user_id,
         lobby_id: lobby_id,
         data: value,
         metadata: metadata || %{}
       }}
    )
  end

  defp broadcast_kv_deleted(key, user_id, lobby_id) do
    Gamend.Broadcast.publish(
      topic(key, user_id, lobby_id),
      {:kv_deleted, %{key: key, user_id: user_id, lobby_id: lobby_id}}
    )
  end

  defp cache_key(key, nil, nil), do: {:kv, :global, key}
  defp cache_key(key, user_id, nil), do: {:kv, :user, user_id, key}
  defp cache_key(key, nil, lobby_id), do: {:kv, :lobby, lobby_id, key}
  defp cache_key(key, user_id, lobby_id), do: {:kv, :user_lobby, user_id, lobby_id, key}

  defp cache_put(key, user_id, lobby_id, %Entry{} = entry) do
    Gamend.Async.run(fn ->
      # Evict the key on all other instances first so their L1 refetches the
      # fresh value (from L2 or the DB) instead of serving the old one until
      # the TTL expires. The put below re-warms this node and L2.
      _ = Gamend.Cache.invalidate(cache_key(key, user_id, lobby_id))

      _ =
        Gamend.Cache.put(
          cache_key(key, user_id, lobby_id),
          %{value: entry.value, metadata: entry.metadata},
          ttl: Gamend.Cache.ttl()
        )

      :ok
    end)
  end

  defp fetch_entry(key, user_id, lobby_id) do
    Repo.one(entry_query(key, user_id, lobby_id))
  end

  defp entry_query(key, nil, nil) do
    from(e in Entry, where: e.key == ^key and is_nil(e.user_id) and is_nil(e.lobby_id))
  end

  defp entry_query(key, user_id, nil) do
    from(e in Entry, where: e.key == ^key and e.user_id == ^user_id)
  end

  defp entry_query(key, nil, lobby_id) do
    from(e in Entry, where: e.key == ^key and e.lobby_id == ^lobby_id)
  end

  defp entry_query(key, user_id, lobby_id) do
    from(e in Entry, where: e.key == ^key and e.user_id == ^user_id and e.lobby_id == ^lobby_id)
  end

  defp maybe_filter_global_only(query, true) do
    from(e in query, where: is_nil(e.user_id) and is_nil(e.lobby_id))
  end

  defp maybe_filter_global_only(query, _false), do: query

  defp maybe_filter_key(query, nil), do: query

  defp maybe_filter_key(query, key_filter) when is_binary(key_filter) do
    pattern = "%#{Repo.escape_like(key_filter)}%"

    from(e in query,
      where: fragment("lower(?) LIKE ? ESCAPE '\\'", e.key, ^pattern)
    )
  end

  defp normalize_key_filter(nil), do: nil

  defp normalize_key_filter(key_filter) when is_binary(key_filter) do
    key_filter = String.trim(key_filter)
    if key_filter == "", do: nil, else: String.downcase(key_filter)
  end

  defp maybe_add_fk_error(%Ecto.Changeset{} = changeset, field) do
    if Ecto.Changeset.get_field(changeset, field) do
      Ecto.Changeset.add_error(changeset, field, "does not exist")
    else
      changeset
    end
  end
end
