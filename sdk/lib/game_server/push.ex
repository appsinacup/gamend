defmodule GameServer.Push do
  @moduledoc ~S"""
  Push context – device push-token registry and (see `send_to_user/3`)
  server-authoritative delivery of push notifications.
  
  Devices register their FCM registration token or APNs device token against
  the authenticated user; a user has many devices. Delivery routes **per
  token** off the `provider` column (`"fcm"` | `"apns"`), falling back to the
  zero-config `Log` provider when nothing is configured
  (see `docs/specs/push.md`).
  
  ## Usage
  
      # Register a device (typically via POST /me/push_tokens)
      {:ok, token} = Push.register_token(user_id, %{
        "token" => "fcm-registration-token",
        "platform" => "android",
        "device_id" => "stable-device-key"
      })
  
      # List a user's devices
      tokens = Push.list_tokens(user_id, page: 1, page_size: 25)
  
      # Remove one (DELETE /me/push_tokens/:id)
      {:ok, _} = Push.delete_token(user_id, token.id)
  

  **Note:** This is an SDK stub. Calling these functions will raise an error.
  The actual implementation runs on the GameServer.
  """

  @type user_id() :: Ecto.UUID.t()

  @doc ~S"""
    Remove any token row by id (admin). Returns `{:ok, %PushToken{}}` or
    `{:error, :not_found}`.
    
  """
  @spec admin_delete_token(Ecto.UUID.t()) :: {:ok, GameServer.Push.PushToken.t()} | {:error, :not_found}
  def admin_delete_token(_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, %GameServer.Push.PushToken{id: "", user_id: "", token: "", platform: "android", provider: "fcm", device_id: nil, disabled_at: nil, last_used_at: nil, metadata: %{}, inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}}

      _ ->
        raise "GameServer.Push.admin_delete_token/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Count for `list_all_tokens/2` (same filters).
  """
  @spec count_all_tokens(map()) :: non_neg_integer()
  def count_all_tokens(_filters) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.Push.count_all_tokens/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Count a user's registered tokens (including disabled).
  """
  @spec count_tokens(user_id()) :: non_neg_integer()
  def count_tokens(_user_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "GameServer.Push.count_tokens/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Remove a token row by id, scoped to `user_id` (the `DELETE /me/push_tokens/:id`
    path). Returns `{:ok, %PushToken{}}` or `{:error, :not_found}`.
    
  """
  @spec delete_token(user_id(), Ecto.UUID.t()) ::
  {:ok, GameServer.Push.PushToken.t()} | {:error, :not_found}
  def delete_token(_user_id, _id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, %GameServer.Push.PushToken{id: "", user_id: "", token: "", platform: "android", provider: "fcm", device_id: nil, disabled_at: nil, last_used_at: nil, metadata: %{}, inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}}

      _ ->
        raise "GameServer.Push.delete_token/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Soft-disable a token the provider reported dead. The row is kept —
    re-registration re-enables it — so a token bouncing between valid and
    invalid never loses its device association.
    
  """
  @spec disable_token(String.t()) :: :ok
  def disable_token(_token) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "GameServer.Push.disable_token/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Whether every delivery is forced to the Log provider (`PUSH_ADAPTER=log`).
  """
  @spec force_log?() :: boolean()
  def force_log?() do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        :erlang.phash2(make_ref(), 2) == 0

      _ ->
        raise "GameServer.Push.force_log?/0 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Admin listing across all users. Supported `filters` keys (atom or string):
    `:user_id`, `:platform`, `:provider`, and `:status` (`"live"` | `"disabled"`).
    
    Supports pagination via `:page` and `:page_size` options; preloads `:user`
    so the admin UI can show names, not UUIDs.
    
  """
  @spec list_all_tokens(
  map(),
  keyword()
) :: [GameServer.Push.PushToken.t()]
  def list_all_tokens(_filters, _opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "GameServer.Push.list_all_tokens/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    List a user's registered tokens, newest first. Includes disabled rows (they
    are the user's devices; clients can show them greyed out).
    
    Supports pagination via `:page` and `:page_size` options.
    
  """
  @spec list_tokens(
  user_id(),
  keyword()
) :: [GameServer.Push.PushToken.t()]
  def list_tokens(_user_id, _opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "GameServer.Push.list_tokens/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    The user's live (non-disabled) tokens — the delivery fan-out set. Unpaginated
    by design: bounded by `max_push_tokens_per_user`.
    
  """
  @spec live_tokens(user_id()) :: [GameServer.Push.PushToken.t()]
  def live_tokens(_user_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "GameServer.Push.live_tokens/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Bump `last_used_at` after a successful delivery.
  """
  @spec mark_token_used(String.t()) :: :ok
  def mark_token_used(_token) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "GameServer.Push.mark_token_used/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Resolve the delivery provider for a token: its `provider` column's module
    when that module's `configured?/0` says it can deliver, else the zero-config
    `Log` provider. `PUSH_ADAPTER=log` short-circuits everything to `Log`.
    
  """
  @spec provider_for(GameServer.Push.PushToken.t()) :: module()
  def provider_for(_push_token) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "GameServer.Push.provider_for/1 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Register (or refresh) a device push token for `user_id`.
    
    Upsert semantics, serialized under the `:push_tokens` advisory lock:
    
    - a row with the same `token` already exists → it is claimed for this
      user/device (a device that logged into another account must not keep
      receiving the old account's pushes) and re-enabled;
    - else a row with the same `(user_id, device_id)` exists → its token is
      rotated in place and the row re-enabled;
    - else a new row is inserted, subject to `max_push_tokens_per_user`
      (counting live tokens only).
    
    `provider` defaults from the platform when omitted: `"ios"` → `"apns"`,
    anything else → `"fcm"`.
    
    Returns `{:ok, %PushToken{}}`, `{:error, :too_many_tokens}`, or
    `{:error, changeset}`.
    
  """
  @spec register_token(user_id(), map()) ::
  {:ok, GameServer.Push.PushToken.t()} | {:error, :too_many_tokens | Ecto.Changeset.t()}
  def register_token(_user_id, _attrs) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, %GameServer.Push.PushToken{id: "", user_id: "", token: "", platform: "android", provider: "fcm", device_id: nil, disabled_at: nil, last_used_at: nil, metadata: %{}, inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}}

      _ ->
        raise "GameServer.Push.register_token/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Queue a push message to all of `user_id`'s live devices.
    
    Server-authoritative: exposed to plugins through the SDK and to admins —
    never as a public client endpoint. Best-effort by design: no live devices
    means no jobs, and delivery failures never propagate back to the caller.
    
    Returns `:ok` or `{:error, errors}` when the message fails validation
    (see `GameServer.Push.Message.new/1`).
    
  """
  @spec send_to_user(user_id(), map(), keyword()) :: :ok | {:error, map()}
  def send_to_user(_user_id, _message_attrs, _opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "GameServer.Push.send_to_user/3 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Queue a push message to every live device of `user_ids`.
    
    Small audiences enqueue delivery jobs inline; past 100
    recipients the expansion itself becomes a `FanoutWorker` job (chunked,
    restart-safe, deduped against identical double-broadcasts).
    
  """
  @spec send_to_users([user_id()], map(), keyword()) :: :ok | {:error, map() | term()}
  def send_to_users(_user_ids, _message_attrs, _opts) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "GameServer.Push.send_to_users/3 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Aggregate token counts for the admin stat card and runtime introspection:
    `%{total: n, live: n, disabled: n, by_platform: %{...}, by_provider: %{...}}`
    (platform/provider maps count live tokens only).
    
  """
  @spec token_stats() :: map()
  def token_stats() do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        %{}

      _ ->
        raise "GameServer.Push.token_stats/0 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Remove a token row by its raw `token` value, scoped to `user_id`.
    
    Returns `{:ok, %PushToken{}}` or `{:error, :not_found}`.
    
  """
  @spec unregister_token(user_id(), String.t()) ::
  {:ok, GameServer.Push.PushToken.t()} | {:error, :not_found}
  def unregister_token(_user_id, _token) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, %GameServer.Push.PushToken{id: "", user_id: "", token: "", platform: "android", provider: "fcm", device_id: nil, disabled_at: nil, last_used_at: nil, metadata: %{}, inserted_at: ~U[1970-01-01 00:00:00Z], updated_at: ~U[1970-01-01 00:00:00Z]}}

      _ ->
        raise "GameServer.Push.unregister_token/2 is a stub - only available at runtime on GameServer"
    end
  end


  @doc ~S"""
    Whether the user has any live device. Cached (60s TTL + version bump on
    register/remove/disable): `Notifications` asks this on every insert, and the
    common no-device answer must not cost a query.
    
  """
  @spec user_has_live_tokens?(user_id()) :: boolean()
  def user_has_live_tokens?(_user_id) do
    case Application.get_env(:game_server_sdk, :stub_mode, :raise) do
      :placeholder ->
        :erlang.phash2(make_ref(), 2) == 0

      _ ->
        raise "GameServer.Push.user_has_live_tokens?/1 is a stub - only available at runtime on GameServer"
    end
  end

end
