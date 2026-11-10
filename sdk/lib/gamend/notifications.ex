defmodule Gamend.Notifications do
  @moduledoc ~S"""
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


  **Note:** This is an SDK stub. Calling these functions will raise an error.
  The actual implementation runs on the Gamend.
  """

  @type user_id() :: Ecto.UUID.t()

  @doc ~S"""
    Admin: create a notification from any sender to any recipient (no friendship check).
    
  """
  @spec admin_create_notification(user_id(), user_id(), map()) ::
          {:ok, Gamend.Notifications.Notification.t()} | {:error, Ecto.Changeset.t()}
  def admin_create_notification(_sender_id, _recipient_id, _attrs) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if reason = Application.get_env(:gamend_sdk, :stub_error),
          do: {:error, reason},
          else: {:ok, nil}

      _ ->
        raise "Gamend.Notifications.admin_create_notification/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Admin: delete a single notification by ID (no ownership check).
  """
  @spec admin_delete_notification(Ecto.UUID.t()) ::
          {:ok, Gamend.Notifications.Notification.t()} | {:error, :not_found | Ecto.Changeset.t()}
  def admin_delete_notification(_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if reason = Application.get_env(:gamend_sdk, :stub_error),
          do: {:error, reason},
          else: {:ok, nil}

      _ ->
        raise "Gamend.Notifications.admin_delete_notification/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count all notifications matching the given filters (admin).
  """
  @spec count_all_notifications(map()) :: non_neg_integer()
  def count_all_notifications(_filters \\ %{}) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Notifications.count_all_notifications/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count total notifications for a user.
  """
  @spec count_notifications(user_id()) :: non_neg_integer()
  def count_notifications(_user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Notifications.count_notifications/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count unread notifications for a user.
  """
  @spec count_unread_notifications(user_id()) :: non_neg_integer()
  def count_unread_notifications(_user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Notifications.count_unread_notifications/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Create a chat notification for a recipient.
    
    Unlike `send_notification/2`, this does not require friendship — it is
    intended for system-generated notifications triggered by new chat messages.
    
    Uses upsert semantics: if a notification with the same
    `(sender_id, recipient_id, title)` already exists, its content and metadata
    are updated (so the user sees the latest message preview).
    
  """
  @spec create_chat_notification(user_id(), user_id(), map()) ::
          {:ok, Gamend.Notifications.Notification.t()} | {:error, term()}
  def create_chat_notification(_sender_id, _recipient_id, _attrs) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if reason = Application.get_env(:gamend_sdk, :stub_error),
          do: {:error, reason},
          else: {:ok, nil}

      _ ->
        raise "Gamend.Notifications.create_chat_notification/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Delete all notifications from `sender_id` to `recipient_id` with the given `title`.
    Used internally to retract system-generated notifications (e.g. friend request cancelled).
    
  """
  @spec delete_notification_by(user_id(), user_id(), String.t()) :: {non_neg_integer(), nil}
  def delete_notification_by(_sender_id, _recipient_id, _title) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Notifications.delete_notification_by/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Delete notifications by IDs, scoped to the recipient (owner).
    
    Only notifications belonging to `user_id` will be deleted.
    Returns `{deleted_count, nil}`.
    
  """
  @spec delete_notifications(user_id(), [Ecto.UUID.t()]) :: {non_neg_integer(), nil}
  def delete_notifications(_user_id, _ids) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Notifications.delete_notifications/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Get a single notification by ID.
  """
  @spec get_notification(Ecto.UUID.t()) :: Gamend.Notifications.Notification.t() | nil
  def get_notification(_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Notifications.get_notification/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Get a single notification by ID (raises if not found).
  """
  @spec get_notification!(Ecto.UUID.t()) :: Gamend.Notifications.Notification.t()
  def get_notification!(_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Notifications.get_notification!/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    The notification group (`Gamend.Notifications.Preferences`) a notification
    belongs to: the one `notify/3` named, else its type's. nil for one in no group.
    
  """
  @spec group_of(Gamend.Notifications.Notification.t()) :: String.t() | nil
  def group_of(_map) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Notifications.group_of/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    List all notifications (admin), with optional filters.
    
    ## Filters (map with string keys)
    
    - `"recipient_id"` / `"user_id"` – filter by recipient user ID
    - `"sender_id"` – filter by sender user ID
    - `"title"` – partial (LIKE) match on title
    
    ## Options
    
    - `:page` – page number (default 1)
    - `:page_size` – results per page (default 25)
    
  """
  @spec list_all_notifications(
          map(),
          keyword()
        ) :: [Gamend.Notifications.Notification.t()]
  def list_all_notifications(_filters \\ %{}, _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Notifications.list_all_notifications/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    List all notifications for a user, ordered oldest-first so the client
    receives them in chronological order.
    
    Supports pagination via `:page` and `:page_size` options.
    
  """
  @spec list_notifications(
          user_id(),
          keyword()
        ) :: [Gamend.Notifications.Notification.t()]
  def list_notifications(_user_id, _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Notifications.list_notifications/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    List notifications for a user filtered by title (e.g. `"party_invite"`, `"group_invite"`).
    
    Results are ordered newest-first and cached with the same version-based TTL
    as `list_notifications/2`.
    
  """
  @spec list_notifications_by_title(user_id(), String.t()) :: [
          Gamend.Notifications.Notification.t()
        ]
  def list_notifications_by_title(_user_id, _title) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Notifications.list_notifications_by_title/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Returns the `limit` most recent notifications, ordered oldest-first (so they
    can be replayed in chronological order on connect without loading the user's
    entire history).
    
  """
  @spec list_recent_notifications(Ecto.UUID.t(), pos_integer()) :: [
          Gamend.Notifications.Notification.t()
        ]
  def list_recent_notifications(_user_id, _limit) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Notifications.list_recent_notifications/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    List notifications sent by a user filtered by title.
    
    Useful for a leader to see which invites they have sent that are still pending.
    Results are ordered newest-first and cached with the same version-based TTL.
    
  """
  @spec list_sent_notifications_by_title(user_id(), String.t()) :: [
          Gamend.Notifications.Notification.t()
        ]
  def list_sent_notifications_by_title(_user_id, _title) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Notifications.list_sent_notifications_by_title/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Mark all notifications as read for a user.
  """
  @spec mark_all_notifications_read(user_id()) :: {non_neg_integer(), nil}
  def mark_all_notifications_read(_user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Notifications.mark_all_notifications_read/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Mark a single notification as read. Only the recipient can mark it.
  """
  @spec mark_notification_read(user_id(), Ecto.UUID.t()) ::
          {:ok, Gamend.Notifications.Notification.t()} | {:error, atom()}
  def mark_notification_read(_user_id, _notification_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if reason = Application.get_env(:gamend_sdk, :stub_error),
          do: {:error, reason},
          else: {:ok, nil}

      _ ->
        raise "Gamend.Notifications.mark_notification_read/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Tell a user something the SERVER has to say (a streak about to end, a class
    result), through the channels they chose for `group`
    (`Gamend.Notifications.Preferences`): the in-app row, a push to their
    devices, an email. A channel they turned off is skipped.
    
    `attrs`: `"title"` (required), `"content"`, `"type"` (a declared code,
    `Gamend.Notifications.Types`), `"url"` (a path on this site the
    notification leads to), and for the email `"subject"` and `"text"`
    (default: the title and the content). `"email_now" => true` sends the email
    at once in a group that sends digests (`Gamend.Notifications.Digest`).
    `"site_only" => true` writes the row and sends nothing else: no push and no
    email, for what the reader only likes to know (a build done).
    
    The in-app row is the user's own (sender = recipient), so repeating a title
    refreshes the one row rather than stacking. Returns the channels it went
    out on.
    
  """
  @spec notify(user_id(), String.t(), map()) :: {:ok, [String.t()]} | {:error, :not_found}
  def notify(_user_id, _group, _attrs) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if reason = Application.get_env(:gamend_sdk, :stub_error),
          do: {:error, reason},
          else: {:ok, nil}

      _ ->
        raise "Gamend.Notifications.notify/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Send a notification to a friend.
    
    `sender_id` is the authenticated user. `attrs` must include:
    - `"user_id"` or `"recipient_id"` – the target friend's user ID
    - `"title"` – required
    - `"content"` – optional
    - `"metadata"` – optional map
    
    Returns `{:error, :not_friends}` when the target is not an accepted friend,
    `:missing_recipient` without a target, `:cannot_notify_self` for the sender
    themselves, `:too_many_notifications` when the recipient's inbox is at
    `max_notifications_per_user`, or the changeset.
    
  """
  @spec send_notification(user_id(), map()) ::
          {:ok, Gamend.Notifications.Notification.t()}
          | {:error,
             :missing_recipient
             | :cannot_notify_self
             | :not_friends
             | :too_many_notifications
             | Ecto.Changeset.t()}
  def send_notification(_sender_id, _attrs) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if reason = Application.get_env(:gamend_sdk, :stub_error),
          do: {:error, reason},
          else: {:ok, nil}

      _ ->
        raise "Gamend.Notifications.send_notification/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Subscribe to notification events for a specific user.
  """
  @spec subscribe(user_id()) :: :ok | {:error, term()}
  def subscribe(_user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        if reason = Application.get_env(:gamend_sdk, :stub_error), do: {:error, reason}, else: :ok

      _ ->
        raise "Gamend.Notifications.subscribe/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Unsubscribe from notification events for a specific user.
  """
  @spec unsubscribe(user_id()) :: :ok
  def unsubscribe(_user_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Notifications.unsubscribe/1 is a stub - only available at runtime on Gamend"
    end
  end
end
