defmodule Gamend.Chat do
  @moduledoc ~S"""
  Context for chat messaging across lobbies, groups, and friend DMs.

  ## Chat types

    * `"lobby"` — messages within a lobby. `chat_ref_id` is the lobby id.
    * `"group"` — messages within a group. `chat_ref_id` is the group id.
    * `"friend"` — direct messages between two friends. `chat_ref_id` is the
      other user's id (each user stores the *other* user's id so queries work
      symmetrically).

  ## PubSub topics

    * `"chat:lobby:<id>"` — lobby chat events
    * `"chat:group:<id>"` — group chat events
    * `"chat:friend:<low>:<high>"` — friend DM events (sorted pair of user ids)

  ## Hooks

    * `before_chat_message/2` — pipeline hook `(user, attrs)` → `{:ok, attrs}` | `{:error, reason}`
    * `after_chat_message/1` — fire-and-forget after a message is persisted


  **Note:** This is an SDK stub. Calling these functions will raise an error.
  The actual implementation runs on the Gamend.
  """

  @doc ~S"""
    Admin: delete a single message by id.
  """
  @spec admin_delete_message(Ecto.UUID.t()) :: {:ok, Gamend.Chat.Message.t()} | {:error, term()}
  def admin_delete_message(_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Chat.admin_delete_message/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Returns `:ok` when user can access the chat conversation.
  """
  @spec authorize_access(Ecto.UUID.t(), String.t(), Ecto.UUID.t()) :: :ok | {:error, atom()}
  def authorize_access(_user_id, _chat_type, _chat_ref_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Chat.authorize_access/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Delete all chat data (messages + read cursors) for a given conversation.
  """
  @spec cleanup_chat(String.t(), Ecto.UUID.t()) :: :ok
  def cleanup_chat(_chat_type, _chat_ref_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Chat.cleanup_chat/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Delete all friend DM messages and read cursors between two users.
    
    Friend messages are stored bidirectionally (each user's messages use
    the other's id as chat_ref_id), so both directions must be cleaned up.
    
  """
  @spec cleanup_friend_chat(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok
  def cleanup_friend_chat(_user_a_id, _user_b_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Chat.cleanup_friend_chat/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count all messages matching filters (admin).
  """
  @spec count_all_messages(map()) :: non_neg_integer()
  def count_all_messages(_filters \\ %{}) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Chat.count_all_messages/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count total friend DM messages between two users.
  """
  @spec count_friend_messages(String.t(), String.t()) :: non_neg_integer()
  def count_friend_messages(_user_a_id, _user_b_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Chat.count_friend_messages/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count total messages in a chat conversation.
  """
  @spec count_messages(String.t(), Ecto.UUID.t()) :: non_neg_integer()
  def count_messages(_chat_type, _chat_ref_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Chat.count_messages/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count messages grouped by chat_type.
    
    Returns a map like `%{"lobby" => 10, "group" => 5, "friend" => 3}`.
    
  """
  @spec count_messages_by_type() :: map()
  def count_messages_by_type() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        %{}

      _ ->
        raise "Gamend.Chat.count_messages_by_type/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count mutes matching `filters`.
  """
  @spec count_mutes(map()) :: non_neg_integer()
  def count_mutes(_filters \\ %{}) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Chat.count_mutes/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count reports matching `filters`.
  """
  @spec count_reports(map()) :: non_neg_integer()
  def count_reports(_filters \\ %{}) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Chat.count_reports/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count distinct users who have sent at least one chat message.
  """
  @spec count_unique_senders() :: non_neg_integer()
  def count_unique_senders() do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Chat.count_unique_senders/0 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count unread messages for a user in a specific chat conversation.
    
    Returns 0 if the user has read all messages or has no cursor (all are unread
    in which case `count_messages/2` should be used instead).
    
  """
  @spec count_unread(Ecto.UUID.t(), String.t(), Ecto.UUID.t()) :: non_neg_integer()
  def count_unread(_user_id, _chat_type, _chat_ref_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Chat.count_unread/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count unread friend DMs between two users for a specific user.
    
  """
  @spec count_unread_friend(Ecto.UUID.t(), Ecto.UUID.t()) :: non_neg_integer()
  def count_unread_friend(_user_id, _friend_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Chat.count_unread_friend/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count unread friend DMs for a user across all friends.
    
    Returns a map of `%{friend_id => unread_count}` for friends that have
    at least one unread message.
    
  """
  @spec count_unread_friends_batch(Ecto.UUID.t(), [Ecto.UUID.t()]) :: %{
          required(Ecto.UUID.t()) => non_neg_integer()
        }
  def count_unread_friends_batch(_user_id, _friend_ids) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Chat.count_unread_friends_batch/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Count unread messages for a user in multiple group chats.
    
    Returns a map of `%{group_id => unread_count}`.
    
  """
  @spec count_unread_groups_batch(Ecto.UUID.t(), [Ecto.UUID.t()]) :: %{
          required(Ecto.UUID.t()) => non_neg_integer()
        }
  def count_unread_groups_batch(_user_id, _group_ids) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Chat.count_unread_groups_batch/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Delete all messages for a given chat conversation.
  """
  @spec delete_messages(String.t(), Ecto.UUID.t()) :: {non_neg_integer(), nil}
  def delete_messages(_chat_type, _chat_ref_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Chat.delete_messages/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Delete a chat message owned by the given user.
    
    Returns `{:error, :not_found}` if the message does not exist or
    `{:error, :forbidden}` if the caller is not the sender.
    
  """
  @spec delete_own_message(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, Gamend.Chat.Message.t()} | {:error, term()}
  def delete_own_message(_user_id, _message_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Chat.delete_own_message/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Delete all read cursors for a given chat conversation.
  """
  @spec delete_read_cursors(String.t(), Ecto.UUID.t()) :: {non_neg_integer(), nil}
  def delete_read_cursors(_chat_type, _chat_ref_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        0

      _ ->
        raise "Gamend.Chat.delete_read_cursors/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Every blocklist entry matching `content`, as `[{word, severity, match_mode}]`.
    
    Exposed for the admin "test a phrase" box so it reports exactly what the
    runtime path would do.
    
  """
  @spec filter_hits(String.t()) :: [{String.t(), String.t(), String.t()}]
  def filter_hits(_content) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Chat.filter_hits/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Get a single message by id.
  """
  @spec get_message(Ecto.UUID.t()) :: Gamend.Chat.Message.t() | nil
  def get_message(_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Chat.get_message/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Get the read cursor for a user in a chat conversation.
    
    Returns `nil` if the user has never opened this conversation.
    
  """
  @spec get_read_cursor(Ecto.UUID.t(), String.t(), Ecto.UUID.t()) ::
          Gamend.Chat.ReadCursor.t() | nil
  def get_read_cursor(_user_id, _chat_type, _chat_ref_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        nil

      _ ->
        raise "Gamend.Chat.get_read_cursor/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    List all messages (admin). Supports filters: sender_id, chat_type, chat_ref_id, content.
  """
  @spec list_all_messages(
          map(),
          keyword()
        ) :: [Gamend.Chat.Message.t()]
  def list_all_messages(_filters \\ %{}, _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Chat.list_all_messages/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    List friend DM messages between two users.
    
    Convenience wrapper that queries messages in both directions.
    
    ## Options
    
      * `:page` — page number (default 1)
      * `:page_size` — items per page (default 25)
    
  """
  @spec list_friend_messages(String.t(), String.t(), keyword()) :: [Gamend.Chat.Message.t()]
  def list_friend_messages(_user_a_id, _user_b_id, _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Chat.list_friend_messages/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    List messages for a chat conversation.
    
    ## Options
    
      * `:page` — page number (default 1)
      * `:page_size` — items per page (default 25)
    
    Returns a list of `%Message{}` structs ordered by `inserted_at` descending
    (newest first).
    
  """
  @spec list_messages(String.t(), Ecto.UUID.t(), keyword()) :: [Gamend.Chat.Message.t()]
  def list_messages(_chat_type, _chat_ref_id, _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Chat.list_messages/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    List mutes. Filters: `:user_id`, `:scope`, `:scope_ref_id`, `:active` (when
    true, only unexpired mutes).
    
  """
  @spec list_mutes(
          map(),
          keyword()
        ) :: [Gamend.Chat.Mute.t()]
  def list_mutes(_filters \\ %{}, _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Chat.list_mutes/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    List reports, newest first. Filters: `:status`, `:reported_user_id`,
    `:reporter_id`.
    
  """
  @spec list_reports(
          map(),
          keyword()
        ) :: [Gamend.Chat.Report.t()]
  def list_reports(_filters \\ %{}, _opts \\ []) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        []

      _ ->
        raise "Gamend.Chat.list_reports/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Mark a chat conversation as read up to a given message id.
    
    Uses an upsert to create or update the read cursor.
    
  """
  @spec mark_read(Ecto.UUID.t(), String.t(), Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, Gamend.Chat.ReadCursor.t()} | {:error, term()}
  def mark_read(_user_id, _chat_type, _chat_ref_id, _message_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Chat.mark_read/4 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Mute `user_id`.
    
    `scope` is `"global"` (every chat, `scope_ref_id` nil) or one of `"lobby"`,
    `"group"`, `"party"` with the room id as `scope_ref_id`. `attrs` may carry
    `expires_at` (nil means permanent), `reason` and `muted_by`.
    
    Re-muting an already-muted user replaces the existing mute, so a moderator
    can extend or shorten one without unmuting first.
    
  """
  @spec mute_user(Ecto.UUID.t(), String.t(), Ecto.UUID.t() | nil, map()) ::
          {:ok, Gamend.Chat.Mute.t()} | {:error, term()}
  def mute_user(_user_id, _scope, _scope_ref_id, _attrs \\ %{}) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Chat.Mute{
           id: "",
           user_id: "",
           scope: "global",
           scope_ref_id: nil,
           expires_at: nil,
           reason: nil,
           muted_by: nil,
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Chat.mute_user/4 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Whether `user_id` is currently muted for the given chat (ETS read).
    
  """
  @spec muted?(Ecto.UUID.t(), String.t(), Ecto.UUID.t() | nil) :: boolean()
  def muted?(_user_id, _chat_type, _chat_ref_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :erlang.phash2(make_ref(), 2) == 0

      _ ->
        raise "Gamend.Chat.muted?/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    File a report about `message_id` on behalf of `reporter_id`.
    
    Returns `{:error, :not_found}` for an unknown message, `{:error, :own_message}`
    when a player reports themselves, `{:error, :already_reported}` when they have
    already reported that message, and `{:error, :report_daily_limit}` once they
    are over `max_chat_reports_per_user_per_day`.
    
    The daily cap is enforced here rather than only at the HTTP edge so that a
    plugin calling this directly is bounded too. The edge keeps its own rate-limit
    check: that one is a cheap in-memory gate, while this counts committed rows,
    so it survives a restart and is shared by every instance. Either can reject.
    
  """
  @spec report_message(Ecto.UUID.t(), Ecto.UUID.t(), String.t() | nil) ::
          {:ok, Gamend.Chat.Report.t()} | {:error, term()}
  def report_message(_reporter_id, _message_id, _reason \\ nil) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Chat.Report{
           id: "",
           reporter_id: nil,
           message_id: nil,
           reported_user_id: "",
           content_snapshot: nil,
           reason: nil,
           status: "open",
           resolved_by: nil,
           resolution_note: nil,
           resolved_at: nil,
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Chat.report_message/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Resolve a report: set its status, note who resolved it and when.
    
    `status` is one of `Gamend.Chat.Report.statuses/0` other than `"open"`.
    
  """
  @spec resolve_report(Gamend.Chat.Report.t() | Ecto.UUID.t(), String.t(), map()) ::
          {:ok, Gamend.Chat.Report.t()} | {:error, term()}
  def resolve_report(_report, _status, _attrs \\ %{}) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Chat.Report{
           id: "",
           reporter_id: nil,
           message_id: nil,
           reported_user_id: "",
           content_snapshot: nil,
           reason: nil,
           status: "open",
           resolved_by: nil,
           resolution_note: nil,
           resolved_at: nil,
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Chat.resolve_report/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Claim a report for review (`"open"` → `"reviewing"`).
    
    Purely a signal to other moderators that someone has picked this one up; it
    sets no resolution, so the report stays in the queue until it is dismissed or
    actioned.
    
  """
  @spec review_report(Gamend.Chat.Report.t() | Ecto.UUID.t()) ::
          {:ok, Gamend.Chat.Report.t()} | {:error, term()}
  def review_report(_report) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok,
         %Gamend.Chat.Report{
           id: "",
           reporter_id: nil,
           message_id: nil,
           reported_user_id: "",
           content_snapshot: nil,
           reason: nil,
           status: "open",
           resolved_by: nil,
           resolution_note: nil,
           resolved_at: nil,
           inserted_at: ~U[1970-01-01 00:00:00Z],
           updated_at: ~U[1970-01-01 00:00:00Z]
         }}

      _ ->
        raise "Gamend.Chat.review_report/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Send a chat message.
    
    ## Parameters
    
      * `scope` — `%{user: %User{}}` (current_scope)
      * `attrs` — map with `"chat_type"`, `"chat_ref_id"`, `"content"`, optional `"metadata"`
    
    ## Returns
    
      * `{:ok, %Message{}}` on success
      * `{:error, reason}` on failure
    
    Moderation runs before the `before_chat_message` hook: a muted sender is
    rejected with `{:error, :muted}` and a blocked word with
    `{:error, :blocked_content}`, so a plugin never sees a message core already
    refused. The hook can then modify attrs or reject the message itself. The
    `after_chat_message` hook fires asynchronously after the message is persisted.
    
  """
  @spec send_message(map(), map()) :: {:ok, Gamend.Chat.Message.t()} | {:error, term()}
  def send_message(_map, _attrs) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Chat.send_message/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Subscribe to chat events for a friend DM conversation.
  """
  @spec subscribe_friend_chat(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok | {:error, term()}
  def subscribe_friend_chat(_user_a_id, _user_b_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Chat.subscribe_friend_chat/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Subscribe to chat events for a group.
  """
  @spec subscribe_group_chat(Ecto.UUID.t()) :: :ok | {:error, term()}
  def subscribe_group_chat(_group_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Chat.subscribe_group_chat/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Subscribe to chat events for a lobby.
  """
  @spec subscribe_lobby_chat(Ecto.UUID.t()) :: :ok | {:error, term()}
  def subscribe_lobby_chat(_lobby_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Chat.subscribe_lobby_chat/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Subscribe to chat events for a party.
  """
  @spec subscribe_party_chat(Ecto.UUID.t()) :: :ok | {:error, term()}
  def subscribe_party_chat(_party_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Chat.subscribe_party_chat/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Remove a mute. Returns `{:ok, count}` — 0 when the user was not muted.
  """
  @spec unmute_user(Ecto.UUID.t(), String.t(), Ecto.UUID.t() | nil) :: {:ok, non_neg_integer()}
  def unmute_user(_user_id, _scope, _scope_ref_id \\ nil) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Chat.unmute_user/3 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Unsubscribe from friend DM chat events.
  """
  @spec unsubscribe_friend_chat(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok
  def unsubscribe_friend_chat(_user_a_id, _user_b_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Chat.unsubscribe_friend_chat/2 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Unsubscribe from group chat events.
  """
  @spec unsubscribe_group_chat(Ecto.UUID.t()) :: :ok
  def unsubscribe_group_chat(_group_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Chat.unsubscribe_group_chat/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Unsubscribe from lobby chat events.
  """
  @spec unsubscribe_lobby_chat(Ecto.UUID.t()) :: :ok
  def unsubscribe_lobby_chat(_lobby_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Chat.unsubscribe_lobby_chat/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Unsubscribe from party chat events.
  """
  @spec unsubscribe_party_chat(Ecto.UUID.t()) :: :ok
  def unsubscribe_party_chat(_party_id) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        :ok

      _ ->
        raise "Gamend.Chat.unsubscribe_party_chat/1 is a stub - only available at runtime on Gamend"
    end
  end

  @doc ~S"""
    Update a chat message owned by the given user.
    
    Only the `content` and `metadata` fields can be changed. Returns
    `{:error, :not_found}` if the message does not exist or
    `{:error, :forbidden}` if the caller is not the sender.
    
  """
  @spec update_message(Ecto.UUID.t(), Ecto.UUID.t(), map()) ::
          {:ok, Gamend.Chat.Message.t()} | {:error, term()}
  def update_message(_user_id, _message_id, _attrs) do
    case Application.get_env(:gamend_sdk, :stub_mode, :raise) do
      :placeholder ->
        {:ok, nil}

      _ ->
        raise "Gamend.Chat.update_message/3 is a stub - only available at runtime on Gamend"
    end
  end
end
