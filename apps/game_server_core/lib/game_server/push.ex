defmodule GameServer.Push do
  @moduledoc """
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
  """

  import Ecto.Query, warn: false

  use Nebulex.Caching, cache: GameServer.Cache

  alias GameServer.Push.DeliveryWorker
  alias GameServer.Push.FanoutWorker
  alias GameServer.Push.Message
  alias GameServer.Push.PushToken
  alias GameServer.Repo

  @type user_id :: Ecto.UUID.t()

  @push_cache_ttl_ms 60_000

  # ---------------------------------------------------------------------------
  # Cache helpers
  # ---------------------------------------------------------------------------

  defp push_version(user_id) do
    GameServer.Cache.get!({:push, :version, user_id}) || 1
  end

  @doc false
  @spec invalidate_push_cache(user_id()) :: :ok
  def invalidate_push_cache(user_id) when is_binary(user_id) do
    GameServer.Async.run(fn ->
      _ = GameServer.Cache.bump_version({:push, :version, user_id})
      :ok
    end)

    :ok
  end

  # ---------------------------------------------------------------------------
  # Registration
  # ---------------------------------------------------------------------------

  @doc """
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
          {:ok, PushToken.t()} | {:error, :too_many_tokens | Ecto.Changeset.t()}
  def register_token(user_id, attrs) when is_binary(user_id) and is_map(attrs) do
    attrs = normalize_attrs(attrs)

    result =
      GameServer.Lock.serialize(:push_tokens, user_id, fn ->
        case upsert_token(user_id, attrs) do
          {:ok, token} -> token
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    case result do
      {:ok, %PushToken{} = token} ->
        invalidate_push_cache(user_id)
        {:ok, token}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_attrs(attrs) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

    attrs =
      if attrs["provider"] in [nil, ""], do: Map.delete(attrs, "provider"), else: attrs

    default_provider = if attrs["platform"] == "ios", do: "apns", else: "fcm"

    Map.put_new(attrs, "provider", default_provider)
  end

  # Token first: the token is globally unique (the physical device truth), so
  # matching it before (user_id, device_id) is what makes account switches on
  # one device safe and avoids unique-constraint conflicts between the two
  # upsert keys.
  defp upsert_token(user_id, attrs) do
    token = attrs["token"]
    device_id = attrs["device_id"]

    cond do
      existing = token && Repo.one(from(t in PushToken, where: t.token == ^token)) ->
        update_registration(existing, user_id, attrs)

      existing = device_id && find_by_device(user_id, device_id) ->
        update_registration(existing, user_id, attrs)

      true ->
        with :ok <- check_token_capacity(user_id) do
          %PushToken{}
          |> PushToken.changeset(Map.put(attrs, "user_id", user_id))
          |> Repo.insert()
        end
    end
  end

  defp find_by_device(user_id, device_id) do
    Repo.one(from(t in PushToken, where: t.user_id == ^user_id and t.device_id == ^device_id))
  end

  defp update_registration(existing, user_id, attrs) do
    previous_owner = existing.user_id

    with :ok <- claim_capacity(previous_owner, user_id),
         {:ok, _} = result <-
           existing
           |> PushToken.changeset(Map.put(attrs, "user_id", user_id))
           |> Ecto.Changeset.put_change(:disabled_at, nil)
           |> Repo.update() do
      if previous_owner != user_id, do: invalidate_push_cache(previous_owner)
      result
    end
  end

  # Rotating/re-enabling your own row never adds a device, but claiming a
  # token from another account does — it must respect the cap like an insert.
  defp claim_capacity(owner, owner), do: :ok
  defp claim_capacity(_previous_owner, user_id), do: check_token_capacity(user_id)

  defp check_token_capacity(user_id) do
    max = GameServer.Limits.get(:max_push_tokens_per_user)

    live =
      Repo.one(
        from(t in PushToken,
          where: t.user_id == ^user_id and is_nil(t.disabled_at),
          select: count(t.id)
        )
      ) || 0

    if live >= max, do: {:error, :too_many_tokens}, else: :ok
  end

  # ---------------------------------------------------------------------------
  # Removal / disabling
  # ---------------------------------------------------------------------------

  @doc """
  Remove a token row by its raw `token` value, scoped to `user_id`.

  Returns `{:ok, %PushToken{}}` or `{:error, :not_found}`.
  """
  @spec unregister_token(user_id(), String.t()) ::
          {:ok, PushToken.t()} | {:error, :not_found}
  def unregister_token(user_id, token) when is_binary(user_id) and is_binary(token) do
    delete_where(from(t in PushToken, where: t.user_id == ^user_id and t.token == ^token))
  end

  @doc """
  Remove a token row by id, scoped to `user_id` (the `DELETE /me/push_tokens/:id`
  path). Returns `{:ok, %PushToken{}}` or `{:error, :not_found}`.
  """
  @spec delete_token(user_id(), Ecto.UUID.t()) ::
          {:ok, PushToken.t()} | {:error, :not_found}
  def delete_token(user_id, id) when is_binary(user_id) and is_binary(id) do
    delete_where(from(t in PushToken, where: t.user_id == ^user_id and t.id == ^id))
  end

  @doc """
  Remove any token row by id (admin). Returns `{:ok, %PushToken{}}` or
  `{:error, :not_found}`.
  """
  @spec admin_delete_token(Ecto.UUID.t()) :: {:ok, PushToken.t()} | {:error, :not_found}
  def admin_delete_token(id) when is_binary(id) do
    delete_where(from(t in PushToken, where: t.id == ^id))
  end

  defp delete_where(query) do
    case Repo.one(query) do
      nil ->
        {:error, :not_found}

      %PushToken{} = token ->
        # allow_stale: a concurrent delete of the same row (double-click,
        # admin + user racing) must land as a no-op, not a StaleEntryError.
        case Repo.delete(token, allow_stale: true) do
          {:ok, deleted} ->
            invalidate_push_cache(deleted.user_id)
            {:ok, deleted}

          {:error, _} ->
            {:error, :not_found}
        end
    end
  end

  @doc """
  Soft-disable a token the provider reported dead. The row is kept —
  re-registration re-enables it — so a token bouncing between valid and
  invalid never loses its device association.
  """
  @spec disable_token(String.t()) :: :ok
  def disable_token(token) when is_binary(token) do
    users =
      Repo.all(
        from(t in PushToken,
          where: t.token == ^token and is_nil(t.disabled_at),
          select: t.user_id
        )
      )

    now = DateTime.utc_now(:second)

    from(t in PushToken, where: t.token == ^token and is_nil(t.disabled_at))
    |> Repo.update_all(set: [disabled_at: now, updated_at: now])

    Enum.each(users, &invalidate_push_cache/1)
    :ok
  end

  @doc "Bump `last_used_at` after a successful delivery."
  @spec mark_token_used(String.t()) :: :ok
  def mark_token_used(token) when is_binary(token) do
    now = DateTime.utc_now(:second)

    from(t in PushToken, where: t.token == ^token)
    |> Repo.update_all(set: [last_used_at: now, updated_at: now])

    :ok
  end

  # ---------------------------------------------------------------------------
  # Queries
  # ---------------------------------------------------------------------------

  @doc """
  List a user's registered tokens, newest first. Includes disabled rows (they
  are the user's devices; clients can show them greyed out).

  Supports pagination via `:page` and `:page_size` options.
  """
  @spec list_tokens(user_id(), keyword()) :: [PushToken.t()]
  def list_tokens(user_id, opts \\ []) when is_binary(user_id) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 25)
    offset = (page - 1) * page_size

    from(t in PushToken,
      where: t.user_id == ^user_id,
      order_by: [desc: t.inserted_at, desc: t.id],
      limit: ^page_size,
      offset: ^offset
    )
    |> Repo.all()
  end

  @doc "Count a user's registered tokens (including disabled)."
  @spec count_tokens(user_id()) :: non_neg_integer()
  def count_tokens(user_id) when is_binary(user_id) do
    Repo.one(from(t in PushToken, where: t.user_id == ^user_id, select: count(t.id))) || 0
  end

  @doc """
  The user's live (non-disabled) tokens — the delivery fan-out set. Unpaginated
  by design: bounded by `max_push_tokens_per_user`.
  """
  @spec live_tokens(user_id()) :: [PushToken.t()]
  def live_tokens(user_id) when is_binary(user_id) do
    from(t in PushToken, where: t.user_id == ^user_id and is_nil(t.disabled_at))
    |> Repo.all()
  end

  @doc """
  Whether the user has any live device. Cached (60s TTL + version bump on
  register/remove/disable): `Notifications` asks this on every insert, and the
  common no-device answer must not cost a query.
  """
  @spec user_has_live_tokens?(user_id()) :: boolean()
  @decorate cacheable(
              key: {:push, :has_tokens, push_version(user_id), user_id},
              opts: [ttl: @push_cache_ttl_ms]
            )
  def user_has_live_tokens?(user_id) when is_binary(user_id) do
    Repo.exists?(from(t in PushToken, where: t.user_id == ^user_id and is_nil(t.disabled_at)))
  end

  @doc """
  Admin listing across all users. Supported `filters` keys (atom or string):
  `:user_id`, `:platform`, `:provider`, and `:status` (`"live"` | `"disabled"`).

  Supports pagination via `:page` and `:page_size` options; preloads `:user`
  so the admin UI can show names, not UUIDs.
  """
  @spec list_all_tokens(map(), keyword()) :: [PushToken.t()]
  def list_all_tokens(filters \\ %{}, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 25)
    offset = (page - 1) * page_size

    all_tokens_query(filters)
    |> order_by([t], desc: t.inserted_at, desc: t.id)
    |> limit(^page_size)
    |> offset(^offset)
    |> preload(:user)
    |> Repo.all()
  end

  @doc "Count for `list_all_tokens/2` (same filters)."
  @spec count_all_tokens(map()) :: non_neg_integer()
  def count_all_tokens(filters \\ %{}) do
    all_tokens_query(filters)
    |> select([t], count(t.id))
    |> Repo.one() || 0
  end

  defp all_tokens_query(filters) do
    filters = Map.new(filters, fn {k, v} -> {to_string(k), v} end)

    PushToken
    |> maybe_filter_user(filters["user_id"])
    |> maybe_filter(:platform, filters["platform"])
    |> maybe_filter(:provider, filters["provider"])
    |> maybe_filter_status(filters["status"])
  end

  # Cast before querying: a half-typed id in the admin filter box must be
  # ignored (the notifications-filter convention), not raise a CastError on
  # Postgres.
  defp maybe_filter_user(query, value) do
    case value != nil and GameServer.UUIDv7.cast_or_nil(value) do
      id when is_binary(id) -> where(query, [t], t.user_id == ^id)
      _ -> query
    end
  end

  defp maybe_filter(query, _field, value) when value in [nil, ""], do: query
  defp maybe_filter(query, field, value), do: where(query, [t], field(t, ^field) == ^value)

  defp maybe_filter_status(query, "live"), do: where(query, [t], is_nil(t.disabled_at))
  defp maybe_filter_status(query, "disabled"), do: where(query, [t], not is_nil(t.disabled_at))
  defp maybe_filter_status(query, _), do: query

  @doc """
  Aggregate token counts for the admin stat card and runtime introspection:
  `%{total: n, live: n, disabled: n, by_platform: %{...}, by_provider: %{...}}`
  (platform/provider maps count live tokens only).
  """
  @spec token_stats() :: map()
  def token_stats do
    {total, live} =
      Repo.one(
        from(t in PushToken,
          select: {count(t.id), filter(count(t.id), is_nil(t.disabled_at))}
        )
      ) || {0, 0}

    live_query = from(t in PushToken, where: is_nil(t.disabled_at))

    by_platform =
      live_query
      |> group_by([t], t.platform)
      |> select([t], {t.platform, count(t.id)})
      |> Repo.all()
      |> Map.new()

    by_provider =
      live_query
      |> group_by([t], t.provider)
      |> select([t], {t.provider, count(t.id)})
      |> Repo.all()
      |> Map.new()

    %{
      total: total,
      live: live,
      disabled: total - live,
      by_platform: by_platform,
      by_provider: by_provider
    }
  end

  # ---------------------------------------------------------------------------
  # Delivery
  # ---------------------------------------------------------------------------

  # Above this many recipients, token resolution + job insertion move to a
  # FanoutWorker job so the caller returns immediately and no transaction
  # grows with audience size.
  @fanout_inline_threshold 100

  # Delivery jobs are bulk-inserted in bounded chunks: SQLite is
  # single-writer, so one unbounded insert_all would stall every other write.
  @fanout_chunk_size 500

  # Compiled-in so every host (including the starter repo) routes correctly
  # with zero config; the `:providers` config key exists only to swap
  # implementations (tests, custom transports).
  @default_providers %{
    "fcm" => GameServer.Push.Providers.FCM,
    "apns" => GameServer.Push.Providers.APNs
  }

  # With nothing configured, neither dispatcher starts and every delivery
  # routes to the Log provider — the whole flow works with zero credentials.
  # The APNs four are all-or-nothing: a partial set means someone meant to
  # enable it and mistyped, which is worth a warning rather than silence.
  use GameServer.Settings.Provider,
    app: :game_server_core,
    group: :push,
    label: "Push notifications"

  setting(:adapter, :atom,
    default: :auto,
    doc: "Set to `log` to route every delivery to the Log provider, credentials or not."
  )

  setting(:queue_concurrency, :integer,
    default: 10,
    doc: "Per-node concurrent deliveries on the push queue."
  )

  setting(:fcm_credentials, :string,
    secret: true,
    doc: "FCM service-account JSON, inline or a path to the file."
  )

  setting(:fcm_project_id, :string, doc: "Defaults to the project id inside the FCM credentials.")

  @apns_group [:apns_private_key, :apns_key_id, :apns_team_id, :apns_topic]

  setting(:apns_private_key, :string,
    secret: true,
    required: :warn,
    with: @apns_group,
    doc: "APNs .p8 key contents, or a path to the file."
  )

  setting(:apns_key_id, :string,
    required: :warn,
    with: @apns_group,
    doc: "10-character key id of the APNs auth key."
  )

  setting(:apns_team_id, :string,
    required: :warn,
    with: @apns_group,
    doc: "Apple developer team id."
  )

  setting(:apns_topic, :string,
    required: :warn,
    with: @apns_group,
    doc: "App bundle id, sent as apns-topic."
  )

  setting(:apns_env, :atom,
    default: :production,
    doc: "`production`, or `sandbox` for dev builds."
  )

  @doc "Whether every delivery is forced to the Log provider (`PUSH_ADAPTER=log`)."
  @spec force_log?() :: boolean()
  def force_log?, do: GameServer.Settings.get(__MODULE__, :adapter) == :log

  @doc """
  Resolve the delivery provider for a token: its `provider` column's module
  when that module's `configured?/0` says it can deliver, else the zero-config
  `Log` provider. `PUSH_ADAPTER=log` short-circuits everything to `Log`.
  """
  @spec provider_for(PushToken.t()) :: module()
  def provider_for(%PushToken{provider: provider}) do
    config = Application.get_env(:game_server_core, __MODULE__, [])
    providers = config[:providers] || @default_providers

    with false <- force_log?(),
         module when module != nil <- providers[provider],
         true <- module.configured?() do
      module
    else
      _ -> GameServer.Push.Providers.Log
    end
  end

  @doc """
  Queue a push message to all of `user_id`'s live devices.

  Server-authoritative: exposed to plugins through the SDK and to admins —
  never as a public client endpoint. Best-effort by design: no live devices
  means no jobs, and delivery failures never propagate back to the caller.

  Returns `:ok` or `{:error, errors}` when the message fails validation
  (see `GameServer.Push.Message.new/1`).
  """
  @spec send_to_user(user_id(), map(), keyword()) :: :ok | {:error, map()}
  def send_to_user(user_id, message_attrs, opts \\ [])
      when is_binary(user_id) and is_map(message_attrs) do
    send_to_users([user_id], message_attrs, opts)
  end

  @doc """
  Queue a push message to every live device of `user_ids`.

  Small audiences enqueue delivery jobs inline; past #{@fanout_inline_threshold}
  recipients the expansion itself becomes a `FanoutWorker` job (chunked,
  restart-safe, deduped against identical double-broadcasts).
  """
  @spec send_to_users([user_id()], map(), keyword()) :: :ok | {:error, map() | term()}
  def send_to_users(user_ids, message_attrs, _opts \\ []) when is_list(user_ids) do
    with {:ok, message} <- Message.new(message_attrs) do
      if length(user_ids) <= @fanout_inline_threshold do
        enqueue_deliveries(user_ids, message)
      else
        %{"user_ids" => user_ids, "message" => Message.to_map(message)}
        |> FanoutWorker.new()
        |> Oban.insert()
        |> case do
          {:ok, _job} -> :ok
          {:error, reason} -> {:error, reason}
        end
      end
    end
  end

  @doc false
  @spec enqueue_deliveries([user_id()], Message.t()) :: :ok
  def enqueue_deliveries(user_ids, %Message{} = message) do
    message_map = Message.to_map(message)

    user_ids
    |> Enum.uniq()
    |> Stream.chunk_every(@fanout_chunk_size)
    |> Enum.each(fn user_chunk ->
      messages = resolve_messages(user_chunk, message_map)
      recipient_ids = Map.keys(messages)

      from(t in PushToken,
        where: t.user_id in ^recipient_ids and is_nil(t.disabled_at),
        select: {t.id, t.user_id}
      )
      |> Repo.all()
      |> Stream.map(fn {token_id, user_id} ->
        DeliveryWorker.new(%{
          "token_id" => token_id,
          "user_id" => user_id,
          "message" => messages[user_id]
        })
      end)
      |> Stream.chunk_every(@fanout_chunk_size)
      |> Enum.each(&Oban.insert_all/1)
    end)

    :ok
  end

  # Runs the before_push_send pipeline per recipient: a plugin can rewrite the
  # message (re-validated — a plugin must not bypass the Limits caps) or veto
  # it with {:error, _}. Returns %{user_id => message_map} minus vetoed users.
  defp resolve_messages(user_ids, message_map) do
    Enum.reduce(user_ids, %{}, fn user_id, acc ->
      with {:ok, returned} <-
             GameServer.Hooks.internal_call(:before_push_send, [user_id, message_map]),
           {:ok, message} <- Message.new(returned) do
        Map.put(acc, user_id, Message.to_map(message))
      else
        {:error, reason} ->
          require Logger
          Logger.debug("[push] before_push_send dropped push to #{user_id}: #{inspect(reason)}")
          acc
      end
    end)
  end
end
