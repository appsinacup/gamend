defmodule Gamend.KV do
  @moduledoc ~S"""
  Generic key/value storage.

  This is intentionally minimal and un-opinionated.

  If you want namespacing, encode it in `key` (e.g. `"my_game:key1"`).
  If you want per-user values, pass `user_id: ...` to `get/2`, `put/4`, and `delete/2`.
  If you want per-lobby values, pass `lobby_id: ...` to the same functions.
  You can also pass both to scope a key to a user within a lobby.

  This module uses the app cache (`Gamend.Cache`) as a best-effort read cache.
  Writes update the cache and deletes evict it.


  **Note:** This is an SDK stub. Calling these functions will raise an error.
  The actual implementation runs on the Gamend.
  """

  @type list_opts() :: [
          page: pos_integer(),
          page_size: pos_integer(),
          user_id: Ecto.UUID.t(),
          lobby_id: Ecto.UUID.t(),
          global_only: boolean(),
          key: String.t()
        ]
  @type attrs() :: %{
          :key => String.t(),
          optional(:user_id) => String.t(),
          optional(:lobby_id) => String.t(),
          :value => value(),
          optional(:metadata) => metadata()
        }
  @type payload() :: %{value: value(), metadata: metadata()}
  @type metadata() :: map()
  @type value() :: map()

  @doc ~S"""
    Count the number of entries that match the optional filter.
    
    Accepts the same options as `list_entries/1` (see `t:list_opts/0`). Returns a non-negative integer.
    
  """
  @spec count_entries() :: non_neg_integer()
  def count_entries() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.KV.count_entries/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count the number of entries that match the optional filter.
    
    Accepts the same options as `list_entries/1` (see `t:list_opts/0`). Returns a non-negative integer.
    
  """
  @spec count_entries(list_opts()) :: non_neg_integer()
  def count_entries(_opts) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.KV.count_entries/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Create a new `Entry` from `attrs` (expecting `key`, optional `user_id`/`lobby_id`,
    `value`, `metadata`).
    Returns `{:ok, entry}` or `{:error, changeset}`.
    
  """
  @spec create_entry(attrs()) :: {:ok, Gamend.KV.Entry.t()} | {:error, Ecto.Changeset.t()}
  def create_entry(_attrs) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.KV.create_entry/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Delete the entry at `key`.
    
    Pass `user_id: id` or `lobby_id: id` in `opts` to delete a scoped key. Returns `:ok`.
    
  """
  @spec delete(String.t()) :: :ok
  def delete(_key) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.KV.delete/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Delete the entry at `key`.
    
    Pass `user_id: id` or `lobby_id: id` in `opts` to delete a scoped key. Returns `:ok`.
    
  """
  @spec delete(
          String.t(),
          keyword()
        ) :: :ok
  def delete(_key, _opts) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.KV.delete/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Delete an entry by its `id`.
    
    Returns `:ok` whether or not the entry existed.
    
  """
  @spec delete_entry(Ecto.UUID.t()) :: :ok
  def delete_entry(_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.KV.delete_entry/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Delete every entry scoped to a lobby, in one statement: for deleting the lobby.
    
    The per-entry cache invalidations and `kv_deleted` broadcasts wait for the
    enclosing transaction to commit (`Gamend.AfterCommit`). One `delete/2` per
    entry cost a statement and two cache round-trips each while the caller held
    the lobby's lock. Returns the number of entries deleted.
    
  """
  @spec delete_lobby_entries(Ecto.UUID.t()) :: non_neg_integer()
  def delete_lobby_entries(_lobby_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.KV.delete_lobby_entries/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Delete every entry a user holds inside one lobby.
    
    Called when a user stops being a member of a lobby, so per-member lobby state
    (ready flags, loadouts, character picks) does not survive a leave and rejoin.
    Entries scoped to the lobby alone, or to the user alone, are left untouched.
    
    Returns the number of entries deleted.
    
  """
  @spec delete_user_lobby_entries(Ecto.UUID.t(), Ecto.UUID.t()) :: non_neg_integer()
  def delete_user_lobby_entries(_user_id, _lobby_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.KV.delete_user_lobby_entries/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Retrieve the value and metadata stored for `key`.
    
    Pass `user_id: id` or `lobby_id: id` in `opts` to scope the lookup.
    Returns `{:ok, %{value: map(), metadata: map()}}` when found, or `:error` when not present.
    
  """
  @spec get(String.t()) :: {:ok, payload()} | :error
  def get(_key) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0,
          do: :error,
          else: {:ok, %{value: %{}, metadata: %{}}}

      _ ->
        raise "Gamend.KV.get/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Retrieve the value and metadata stored for `key`.
    
    Pass `user_id: id` or `lobby_id: id` in `opts` to scope the lookup.
    Returns `{:ok, %{value: map(), metadata: map()}}` when found, or `:error` when not present.
    
  """
  @spec get(
          String.t(),
          keyword()
        ) :: {:ok, payload()} | :error
  def get(_key, _opts) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if :erlang.phash2(make_ref(), 2) == 0,
          do: :error,
          else: {:ok, %{value: %{}, metadata: %{}}}

      _ ->
        raise "Gamend.KV.get/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Fetch an `Entry` by its `id`.
    Returns the `Entry` struct or `nil` if not found.
    
  """
  @spec get_entry(Ecto.UUID.t()) :: Gamend.KV.Entry.t() | nil
  def get_entry(_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.KV.get_entry/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    List key/value entries with optional pagination and filtering.
    
    Supported options: `:page`, `:page_size`, `:user_id`, `:lobby_id`, `:global_only`,
    and `:key` (substring filter).
    See `t:list_opts/0` for the expected option types.
    Returns a list of `Entry` structs ordered by most recently updated.
    
  """
  @spec list_entries() :: [Gamend.KV.Entry.t()]
  def list_entries() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.KV.list_entries/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    List key/value entries with optional pagination and filtering.
    
    Supported options: `:page`, `:page_size`, `:user_id`, `:lobby_id`, `:global_only`,
    and `:key` (substring filter).
    See `t:list_opts/0` for the expected option types.
    Returns a list of `Entry` structs ordered by most recently updated.
    
  """
  @spec list_entries(list_opts()) :: [Gamend.KV.Entry.t()]
  def list_entries(_opts) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.KV.list_entries/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Store `value` with optional `metadata` at `key`.
    
    When using the 4-arity, supported options include `user_id: id` or `lobby_id: id` to scope
    the entry.
    Returns `{:ok, entry}` on success or `{:error, changeset}` on validation failure.
    
  """
  @spec put(String.t(), value()) :: {:ok, Gamend.KV.Entry.t()} | {:error, Ecto.Changeset.t()}
  def put(_key, _value) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.KV.put/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc false
  @spec put(String.t(), value(), metadata()) ::
          {:ok, Gamend.KV.Entry.t()} | {:error, Ecto.Changeset.t()}
  def put(_key, _value, _metadata) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.KV.put/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Store `value` with optional `metadata` at `key`.
    
    When using the 4-arity, supported options include `user_id: id` or `lobby_id: id` to scope
    the entry.
    Returns `{:ok, entry}` on success or `{:error, changeset}` on validation failure.
    
  """
  @spec put(String.t(), value(), metadata(), list_opts()) ::
          {:ok, Gamend.KV.Entry.t()} | {:error, Ecto.Changeset.t()}
  def put(_key, _value, _metadata, _opts) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.KV.put/4 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Subscribe the current process to changes for a specific key/scope.
    
  """
  @spec subscribe(
          String.t(),
          keyword()
        ) :: :ok | {:error, term()}
  def subscribe(_key, _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.KV.subscribe/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Unsubscribe the current process from changes for a specific key/scope.
    
  """
  @spec unsubscribe(
          String.t(),
          keyword()
        ) :: :ok | {:error, term()}
  def unsubscribe(_key, _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.KV.unsubscribe/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Update an existing entry by `id` with `attrs`.
    Returns `{:ok, entry}`, `{:error, :not_found}` if missing, or `{:error, changeset}` on validation error.
    
  """
  @spec update_entry(Ecto.UUID.t(), attrs()) ::
          {:ok, Gamend.KV.Entry.t()} | {:error, :not_found} | {:error, Ecto.Changeset.t()}
  def update_entry(_id, _attrs) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.KV.update_entry/2 is a stub - only available at runtime on Gamend"
    end
  end
end
