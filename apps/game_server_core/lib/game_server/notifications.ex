defmodule GameServer.Notifications do
  @moduledoc """
  Notifications context – create, list, and delete persisted user-to-user
  notifications.

  Notifications can only be sent to accepted friends. They are stored in the
  database so that recipients receive them even when offline. On WebSocket
  connect the client gets all undeleted notifications (ordered by timestamp).
  New notifications are also pushed in real-time via PubSub.

  ## PubSub Events

  This module broadcasts to the `"notifications:user:<user_id>"` topic:

  - `{:notification_created, notification}` – a new notification was created

  ## Usage

      # Send a notification to a friend
      {:ok, notification} = Notifications.send_notification(sender_id, %{
        "user_id" => recipient_id,
        "title" => "Game invite",
        "content" => "Join my lobby!",
        "metadata" => %{"lobby_id" => "0198c0de-7f2a-7e3b-9c4d-1a2b3c4d5e6f"}
      })

      # List all notifications for a user (ordered oldest-first)
      notifications = Notifications.list_notifications(user_id)

      # Delete notifications by IDs (only owner can delete)
      {deleted_count, nil} = Notifications.delete_notifications(user_id, [1, 2, 3])

      # Count notifications for a user
      count = Notifications.count_notifications(user_id)
  """

  import Ecto.Query, warn: false

  use Nebulex.Caching, cache: GameServer.Cache

  alias GameServer.Friends
  alias GameServer.Notifications.Notification
  alias GameServer.Repo
  alias GameServer.Repo.AdvisoryLock

  @type user_id :: Ecto.UUID.t()

  @notifications_cache_ttl_ms 60_000

  # ---------------------------------------------------------------------------
  # PubSub
  # ---------------------------------------------------------------------------

  @doc "Subscribe to notification events for a specific user."
  @spec subscribe(user_id()) :: :ok | {:error, term()}
  def subscribe(user_id) when is_binary(user_id) do
    Phoenix.PubSub.subscribe(GameServer.PubSub, "notifications:user:#{user_id}")
  end

  @doc "Unsubscribe from notification events for a specific user."
  @spec unsubscribe(user_id()) :: :ok
  def unsubscribe(user_id) when is_binary(user_id) do
    Phoenix.PubSub.unsubscribe(GameServer.PubSub, "notifications:user:#{user_id}")
  end

  defp broadcast_user(user_id, event) when is_binary(user_id) do
    Phoenix.PubSub.broadcast(GameServer.PubSub, "notifications:user:#{user_id}", event)
  end

  # ---------------------------------------------------------------------------
  # Cache helpers
  # ---------------------------------------------------------------------------

  @doc false
  defp notifications_version(user_id) do
    GameServer.Cache.get!({:notifications, :version, user_id}) || 1
  end

  # Global row-version for get_notification/1 (no user_id available at read time),
  # bumped when an existing notification row changes (update/delete/bulk) — not on
  # insert, since a new row can't invalidate a cached existing one.
  defp notification_row_version, do: GameServer.Cache.get!({:notifications, :row_version}) || 1
  defp bump_notification_row, do: GameServer.Cache.bump_version({:notifications, :row_version})

  @doc false
  @spec invalidate_notifications_cache(user_id()) :: :ok
  def invalidate_notifications_cache(user_id) when is_binary(user_id) do
    GameServer.Async.run(fn ->
      _ = GameServer.Cache.bump_version({:notifications, :version, user_id})
      _ = bump_notification_row()
      :ok
    end)

    :ok
  end

  # ---------------------------------------------------------------------------
  # Queries
  # ---------------------------------------------------------------------------

  @doc """
  List all notifications for a user, ordered oldest-first so the client
  receives them in chronological order.

  Supports pagination via `:page` and `:page_size` options.
  """
  @spec list_notifications(user_id(), keyword()) :: [Notification.t()]
  @decorate cacheable(
              key:
                {:notifications, :list, notifications_version(user_id), user_id,
                 Keyword.get(opts, :page, 1), Keyword.get(opts, :page_size, 25)},
              opts: [ttl: @notifications_cache_ttl_ms]
            )
  def list_notifications(user_id, opts \\ []) when is_binary(user_id) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 25)
    offset = (page - 1) * page_size

    from(n in Notification,
      where: n.recipient_id == ^user_id,
      order_by: [asc: n.inserted_at, asc: n.id],
      limit: ^page_size,
      offset: ^offset,
      preload: [:sender]
    )
    |> Repo.all()
  end

  @doc """
  Returns the `limit` most recent notifications, ordered oldest-first (so they
  can be replayed in chronological order on connect without loading the user's
  entire history).
  """
  @spec list_recent_notifications(Ecto.UUID.t(), pos_integer()) :: [Notification.t()]
  def list_recent_notifications(user_id, limit)
      when is_binary(user_id) and is_integer(limit) and limit > 0 do
    from(n in Notification,
      where: n.recipient_id == ^user_id,
      order_by: [desc: n.inserted_at, desc: n.id],
      limit: ^limit,
      preload: [:sender]
    )
    |> Repo.all()
    |> Enum.reverse()
  end

  @doc "Count total notifications for a user."
  @spec count_notifications(user_id()) :: non_neg_integer()
  @decorate cacheable(
              key: {:notifications, :count, notifications_version(user_id), user_id},
              opts: [ttl: @notifications_cache_ttl_ms]
            )
  def count_notifications(user_id) when is_binary(user_id) do
    Repo.one(
      from(n in Notification,
        where: n.recipient_id == ^user_id,
        select: count(n.id)
      )
    ) || 0
  end

  @doc "Count unread notifications for a user."
  @spec count_unread_notifications(user_id()) :: non_neg_integer()
  @decorate cacheable(
              key: {:notifications, :count_unread, notifications_version(user_id), user_id},
              opts: [ttl: @notifications_cache_ttl_ms]
            )
  def count_unread_notifications(user_id) when is_binary(user_id) do
    Repo.one(
      from(n in Notification,
        where: n.recipient_id == ^user_id and n.read == false,
        select: count(n.id)
      )
    ) || 0
  end

  @doc """
  List notifications for a user filtered by title (e.g. `\"party_invite\"`, `\"group_invite\"`).

  Results are ordered newest-first and cached with the same version-based TTL
  as `list_notifications/2`.
  """
  @spec list_notifications_by_title(user_id(), String.t()) :: [Notification.t()]
  @decorate cacheable(
              key: {:notifications, :by_title, notifications_version(user_id), user_id, title},
              opts: [ttl: @notifications_cache_ttl_ms]
            )
  def list_notifications_by_title(user_id, title)
      when is_binary(user_id) and is_binary(title) do
    from(n in Notification,
      where: n.recipient_id == ^user_id and n.title == ^title,
      order_by: [desc: n.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  List notifications sent by a user filtered by title.

  Useful for a leader to see which invites they have sent that are still pending.
  Results are ordered newest-first and cached with the same version-based TTL.
  """
  @spec list_sent_notifications_by_title(user_id(), String.t()) :: [Notification.t()]
  @decorate cacheable(
              key:
                {:notifications, :sent_by_title, notifications_version(user_id), user_id, title},
              opts: [ttl: @notifications_cache_ttl_ms]
            )
  def list_sent_notifications_by_title(user_id, title)
      when is_binary(user_id) and is_binary(title) do
    from(n in Notification,
      where: n.sender_id == ^user_id and n.title == ^title,
      order_by: [desc: n.inserted_at]
    )
    |> Repo.all()
  end

  @doc "Mark a single notification as read. Only the recipient can mark it."
  @spec mark_notification_read(user_id(), Ecto.UUID.t()) ::
          {:ok, Notification.t()} | {:error, atom()}
  def mark_notification_read(user_id, notification_id)
      when is_binary(user_id) and is_binary(notification_id) do
    case Repo.one(
           from(n in Notification,
             where: n.id == ^notification_id and n.recipient_id == ^user_id
           )
         ) do
      nil ->
        {:error, :not_found}

      notification ->
        notification
        |> Ecto.Changeset.change(read: true)
        |> Repo.update()
        |> case do
          {:ok, updated} ->
            invalidate_notifications_cache(user_id)
            {:ok, updated}

          error ->
            error
        end
    end
  end

  @doc "Mark all notifications as read for a user."
  @spec mark_all_notifications_read(user_id()) :: {non_neg_integer(), nil}
  def mark_all_notifications_read(user_id) when is_binary(user_id) do
    result =
      from(n in Notification,
        where: n.recipient_id == ^user_id and n.read == false
      )
      |> Repo.update_all(set: [read: true, updated_at: DateTime.utc_now(:second)])

    invalidate_notifications_cache(user_id)
    result
  end

  @doc "Get a single notification by ID."
  @spec get_notification(Ecto.UUID.t()) :: Notification.t() | nil
  @decorate cacheable(
              key: {:notifications, :get, notification_row_version(), id},
              match: &(&1 != nil),
              opts: [ttl: @notifications_cache_ttl_ms]
            )
  def get_notification(id) do
    Repo.get_uuid(Notification, id)
  end

  @doc "Get a single notification by ID (raises if not found)."
  @spec get_notification!(Ecto.UUID.t()) :: Notification.t()
  def get_notification!(id) do
    case get_notification(id) do
      %Notification{} = notification -> notification
      nil -> raise Ecto.NoResultsError, queryable: Notification
    end
  end

  # ---------------------------------------------------------------------------
  # Admin queries (all notifications, with optional filters)
  # ---------------------------------------------------------------------------

  @doc """
  List all notifications (admin), with optional filters.

  ## Filters (map with string keys)

  - `"recipient_id"` / `"user_id"` – filter by recipient user ID
  - `"sender_id"` – filter by sender user ID
  - `"title"` – partial (LIKE) match on title

  ## Options

  - `:page` – page number (default 1)
  - `:page_size` – results per page (default 25)
  """
  @spec list_all_notifications(map(), keyword()) :: [Notification.t()]
  def list_all_notifications(filters \\ %{}, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 25)
    offset = (page - 1) * page_size

    Notification
    |> apply_admin_filters(filters)
    |> order_by([n], desc: n.inserted_at, desc: n.id)
    |> limit(^page_size)
    |> offset(^offset)
    |> preload([:sender, :recipient])
    |> Repo.all()
  end

  @doc "Count all notifications matching the given filters (admin)."
  @spec count_all_notifications(map()) :: non_neg_integer()
  def count_all_notifications(filters \\ %{}) do
    Notification
    |> apply_admin_filters(filters)
    |> select([n], count(n.id))
    |> Repo.one() || 0
  end

  defp apply_admin_filters(query, filters) when is_map(filters) do
    query
    |> maybe_filter_recipient(filters)
    |> maybe_filter_sender(filters)
    |> maybe_filter_title(filters)
  end

  defp maybe_filter_recipient(query, filters) do
    recipient_id =
      Map.get(filters, "recipient_id") || Map.get(filters, "user_id")

    case GameServer.UUIDv7.cast_or_nil(recipient_id) do
      nil -> query
      id -> where(query, [n], n.recipient_id == ^id)
    end
  end

  defp maybe_filter_sender(query, filters) do
    case GameServer.UUIDv7.cast_or_nil(Map.get(filters, "sender_id")) do
      nil -> query
      id -> where(query, [n], n.sender_id == ^id)
    end
  end

  defp maybe_filter_title(query, filters) do
    case Map.get(filters, "title") do
      nil ->
        query

      "" ->
        query

      title ->
        pattern = "%#{Repo.escape_like(title)}%"
        where(query, [n], fragment("? LIKE ? ESCAPE '\\'", n.title, ^pattern))
    end
  end

  @doc """
  Admin: create a notification from any sender to any recipient (no friendship check).
  """
  @spec admin_create_notification(user_id(), user_id(), map()) ::
          {:ok, Notification.t()} | {:error, Ecto.Changeset.t() | atom()}
  def admin_create_notification(sender_id, recipient_id, attrs)
      when is_binary(sender_id) and is_binary(recipient_id) do
    upsert_notification(sender_id, recipient_id, attrs)
  end

  @doc "Admin: delete a single notification by ID (no ownership check)."
  @spec admin_delete_notification(Ecto.UUID.t()) :: {:ok, Notification.t()} | {:error, term()}
  def admin_delete_notification(id) when is_binary(id) do
    case get_notification(id) do
      nil ->
        {:error, :not_found}

      notification ->
        case Repo.delete(notification) do
          {:ok, deleted} ->
            invalidate_notifications_cache(deleted.recipient_id)
            {:ok, deleted}

          error ->
            error
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Commands
  # ---------------------------------------------------------------------------

  @doc """
  Send a notification to a friend.

  `sender_id` is the authenticated user. `attrs` must include:
  - `"user_id"` or `"recipient_id"` – the target friend's user ID
  - `"title"` – required
  - `"content"` – optional
  - `"metadata"` – optional map

  Returns `{:error, :not_friends}` when the target is not an accepted friend.
  """
  @spec send_notification(user_id(), map()) ::
          {:ok, Notification.t()} | {:error, Ecto.Changeset.t() | atom()}
  def send_notification(sender_id, attrs) when is_binary(sender_id) and is_map(attrs) do
    recipient_id = get_recipient_id(attrs)

    cond do
      is_nil(recipient_id) ->
        {:error, :missing_recipient}

      recipient_id == sender_id ->
        {:error, :cannot_notify_self}

      not friends?(sender_id, recipient_id) ->
        {:error, :not_friends}

      true ->
        max = GameServer.Limits.get(:max_notifications_per_user)

        if count_notifications(recipient_id) >= max do
          {:error, :too_many_notifications}
        else
          upsert_notification(sender_id, recipient_id, attrs)
        end
    end
  end

  @doc """
  Delete notifications by IDs, scoped to the recipient (owner).

  Only notifications belonging to `user_id` will be deleted.
  Returns `{deleted_count, nil}`.
  """
  @spec delete_notifications(user_id(), [Ecto.UUID.t()]) :: {non_neg_integer(), nil}
  def delete_notifications(user_id, ids)
      when is_binary(user_id) and is_list(ids) do
    result =
      from(n in Notification,
        where: n.recipient_id == ^user_id and n.id in ^ids
      )
      |> Repo.delete_all()

    invalidate_notifications_cache(user_id)
    result
  end

  @doc """
  Delete all notifications from `sender_id` to `recipient_id` with the given `title`.
  Used internally to retract system-generated notifications (e.g. friend request cancelled).
  """
  @spec delete_notification_by(user_id(), user_id(), String.t()) :: {non_neg_integer(), nil}
  def delete_notification_by(sender_id, recipient_id, title)
      when is_binary(sender_id) and is_binary(recipient_id) and is_binary(title) do
    result =
      from(n in Notification,
        where:
          n.sender_id == ^sender_id and n.recipient_id == ^recipient_id and
            n.title == ^title
      )
      |> Repo.delete_all()

    invalidate_notifications_cache(recipient_id)
    invalidate_notifications_cache(sender_id)
    result
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Upsert a notification: on conflict (same sender, recipient, title),
  # replace content, metadata, and read flag so the user sees the latest.
  defp upsert_notification(sender_id, recipient_id, attrs) do
    content = Map.get(attrs, "content") || Map.get(attrs, :content, "")
    metadata = Map.get(attrs, "metadata") || Map.get(attrs, :metadata, %{})
    icon_url = Map.get(attrs, "icon_url") || Map.get(attrs, :icon_url)

    %Notification{}
    |> Notification.changeset(attrs)
    |> Ecto.Changeset.put_change(:sender_id, sender_id)
    |> Ecto.Changeset.put_change(:recipient_id, recipient_id)
    |> Repo.insert(
      on_conflict: [
        set: [
          content: content,
          icon_url: icon_url,
          metadata: metadata,
          read: false,
          updated_at: DateTime.utc_now(:second)
        ]
      ],
      conflict_target: {:unsafe_fragment, "(sender_id, recipient_id, title)"},
      returning: true
    )
    |> case do
      {:ok, notification} ->
        invalidate_notifications_cache(recipient_id)
        invalidate_notifications_cache(sender_id)
        broadcast_user(recipient_id, {:notification_created, notification})
        push_notification(notification)
        {:ok, notification}

      error ->
        error
    end
  end

  # Best-effort bridge to push so an offline recipient still gets pinged:
  # runs after the row is committed and broadcast, and its outcome never
  # affects the notification (delivery itself is queued jobs). The cached
  # has-live-tokens check keeps the common no-device case free.
  defp push_notification(%Notification{} = notification) do
    if GameServer.Push.user_has_live_tokens?(notification.recipient_id) do
      alias GameServer.Push.Message

      # Byte-safe truncation: notification titles/content allow more than the
      # push byte caps (and titles are personalized, so multibyte names can
      # exceed the cap even at equal char limits) — a push must degrade to a
      # shorter preview, never be dropped by validation.
      _ =
        GameServer.Push.send_to_user(notification.recipient_id, %{
          "title" => Message.truncate(notification.title, GameServer.Limits.get(:max_push_title)),
          "body" =>
            Message.truncate(notification.content || "", GameServer.Limits.get(:max_push_body)),
          "data" => push_data(notification),
          # One collapse id per notification row, so the re-upserted rows
          # (chat previews) replace their earlier push instead of stacking.
          "collapse_key" => "notif-#{notification.id}"
        })
    end

    :ok
  end

  defp push_data(%Notification{} = notification) do
    case notification.metadata do
      %{"type" => type} -> %{"type" => type, "notification_id" => notification.id}
      _ -> %{"notification_id" => notification.id}
    end
  end

  @doc """
  Create a chat notification for a recipient.

  Unlike `send_notification/2`, this does not require friendship — it is
  intended for system-generated notifications triggered by new chat messages.

  Uses upsert semantics: if a notification with the same
  `(sender_id, recipient_id, title)` already exists, its content and metadata
  are updated (so the user sees the latest message preview).
  """
  @spec create_chat_notification(user_id(), user_id(), map()) ::
          {:ok, Notification.t()} | {:error, term()}
  def create_chat_notification(sender_id, recipient_id, attrs)
      when is_binary(sender_id) and is_binary(recipient_id) do
    # Build the initial metadata with message_count = 1
    base_metadata = Map.get(attrs, "metadata", %{})
    metadata_with_count = Map.put(base_metadata, "message_count", 1)
    attrs_with_count = Map.put(attrs, "metadata", metadata_with_count)

    changeset =
      %Notification{}
      |> Notification.changeset(attrs_with_count)
      |> Ecto.Changeset.put_change(:sender_id, sender_id)
      |> Ecto.Changeset.put_change(:recipient_id, recipient_id)

    content = Map.get(attrs, "content", "")
    now = DateTime.utc_now(:second)

    on_conflict_query = chat_notification_on_conflict(content, now)

    changeset
    |> Repo.insert(
      on_conflict: on_conflict_query,
      conflict_target: {:unsafe_fragment, "(sender_id, recipient_id, title)"}
    )
    |> case do
      {:ok, notification} ->
        invalidate_notifications_cache(recipient_id)
        invalidate_notifications_cache(sender_id)
        broadcast_user(recipient_id, {:notification_created, notification})
        push_notification(notification)
        {:ok, notification}

      error ->
        error
    end
  end

  # Build the ON CONFLICT update query for chat notifications.
  # Uses adapter-specific JSON functions: Postgres uses jsonb_set / ->>
  # while SQLite uses json_set / json_extract.
  defp chat_notification_on_conflict(content, now) do
    if AdvisoryLock.postgres?() do
      from(n in Notification,
        update: [
          set: [
            content: ^content,
            metadata:
              fragment(
                "jsonb_set(COALESCE(?, '{}'::jsonb), '{message_count}', to_jsonb(COALESCE((?->>'message_count')::integer, 0) + 1))",
                n.metadata,
                n.metadata
              ),
            read: false,
            updated_at: ^now
          ]
        ]
      )
    else
      from(n in Notification,
        update: [
          set: [
            content: ^content,
            metadata:
              fragment(
                "json_set(?, '$.message_count', COALESCE(json_extract(?, '$.message_count'), 0) + 1)",
                n.metadata,
                n.metadata
              ),
            read: false,
            updated_at: ^now
          ]
        ]
      )
    end
  end

  defp get_recipient_id(attrs) do
    raw =
      Map.get(attrs, "user_id") ||
        Map.get(attrs, :user_id) ||
        Map.get(attrs, "recipient_id") ||
        Map.get(attrs, :recipient_id)

    case raw do
      nil -> nil
      id when is_binary(id) -> id
      _ -> nil
    end
  end

  defp friends?(a, b) when is_binary(a) and is_binary(b) do
    Friends.friends?(a, b)
  end
end
