defmodule GameServer.Chat do
  @moduledoc """
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
  """

  import Ecto.Query

  use Nebulex.Caching, cache: GameServer.Cache

  alias GameServer.Accounts
  alias GameServer.Accounts.User
  alias GameServer.Chat.Message
  alias GameServer.Chat.ReadCursor
  alias GameServer.Repo

  require Logger

  # ---------------------------------------------------------------------------
  # Cache helpers
  # ---------------------------------------------------------------------------

  @chat_cache_ttl_ms 60_000

  defp chat_version(chat_type, chat_ref_id) do
    GameServer.Cache.get!({:chat, :version, chat_type, chat_ref_id}) || 1
  end

  # Global row-version for get_message/1 (no chat_type/ref available at read time).
  defp message_row_version, do: GameServer.Cache.get!({:chat, :message_version}) || 1
  defp bump_message_row, do: GameServer.Cache.bump_version({:chat, :message_version})

  defp invalidate_chat_cache(chat_type, chat_ref_id) do
    GameServer.Async.run(fn ->
      _ = GameServer.Cache.bump_version({:chat, :version, chat_type, chat_ref_id})
      _ = bump_message_row()
      :ok
    end)

    :ok
  end

  # ---------------------------------------------------------------------------
  # PubSub
  # ---------------------------------------------------------------------------

  @doc "Subscribe to chat events for a lobby."
  @spec subscribe_lobby_chat(Ecto.UUID.t()) :: :ok | {:error, term()}
  def subscribe_lobby_chat(lobby_id),
    do: Phoenix.PubSub.subscribe(GameServer.PubSub, "chat:lobby:#{lobby_id}")

  @doc "Unsubscribe from lobby chat events."
  @spec unsubscribe_lobby_chat(Ecto.UUID.t()) :: :ok
  def unsubscribe_lobby_chat(lobby_id),
    do: Phoenix.PubSub.unsubscribe(GameServer.PubSub, "chat:lobby:#{lobby_id}")

  @doc "Subscribe to chat events for a group."
  @spec subscribe_group_chat(Ecto.UUID.t()) :: :ok | {:error, term()}
  def subscribe_group_chat(group_id),
    do: Phoenix.PubSub.subscribe(GameServer.PubSub, "chat:group:#{group_id}")

  @doc "Unsubscribe from group chat events."
  @spec unsubscribe_group_chat(Ecto.UUID.t()) :: :ok
  def unsubscribe_group_chat(group_id),
    do: Phoenix.PubSub.unsubscribe(GameServer.PubSub, "chat:group:#{group_id}")

  @doc "Subscribe to chat events for a friend DM conversation."
  @spec subscribe_friend_chat(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok | {:error, term()}
  def subscribe_friend_chat(user_a_id, user_b_id) do
    {low, high} = friend_pair(user_a_id, user_b_id)
    Phoenix.PubSub.subscribe(GameServer.PubSub, "chat:friend:#{low}:#{high}")
  end

  @doc "Unsubscribe from friend DM chat events."
  @spec unsubscribe_friend_chat(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok
  def unsubscribe_friend_chat(user_a_id, user_b_id) do
    {low, high} = friend_pair(user_a_id, user_b_id)
    Phoenix.PubSub.unsubscribe(GameServer.PubSub, "chat:friend:#{low}:#{high}")
  end

  @doc "Subscribe to chat events for a party."
  @spec subscribe_party_chat(Ecto.UUID.t()) :: :ok | {:error, term()}
  def subscribe_party_chat(party_id),
    do: Phoenix.PubSub.subscribe(GameServer.PubSub, "chat:party:#{party_id}")

  @doc "Unsubscribe from party chat events."
  @spec unsubscribe_party_chat(Ecto.UUID.t()) :: :ok
  def unsubscribe_party_chat(party_id),
    do: Phoenix.PubSub.unsubscribe(GameServer.PubSub, "chat:party:#{party_id}")

  defp broadcast_chat(chat_type, chat_ref_id, sender_id, event) do
    topic = chat_topic(chat_type, chat_ref_id, sender_id)
    Phoenix.PubSub.broadcast(GameServer.PubSub, topic, event)

    # For friend DMs, also broadcast to the recipient's user topic so the
    # UserChannel can forward the message without subscribing to every pair.
    if chat_type == "friend" do
      Phoenix.PubSub.broadcast(GameServer.PubSub, "user:#{chat_ref_id}", event)
    end
  end

  defp chat_topic("lobby", lobby_id, _sender_id), do: "chat:lobby:#{lobby_id}"
  defp chat_topic("group", group_id, _sender_id), do: "chat:group:#{group_id}"
  defp chat_topic("party", party_id, _sender_id), do: "chat:party:#{party_id}"

  defp chat_topic("friend", friend_id, sender_id) do
    {low, high} = friend_pair(sender_id, friend_id)
    "chat:friend:#{low}:#{high}"
  end

  defp friend_pair(a, b) when a < b, do: {a, b}
  defp friend_pair(a, b), do: {b, a}

  # ---------------------------------------------------------------------------
  # Send message
  # ---------------------------------------------------------------------------

  @doc """
  Send a chat message.

  ## Parameters

    * `scope` — `%{user: %User{}}` (current_scope)
    * `attrs` — map with `"chat_type"`, `"chat_ref_id"`, `"content"`, optional `"metadata"`

  ## Returns

    * `{:ok, %Message{}}` on success
    * `{:error, reason}` on failure

  The `before_chat_message` hook is called before persistence and can modify
  attrs or reject the message. The `after_chat_message` hook fires asynchronously
  after the message is persisted.
  """
  @spec send_message(map(), map()) ::
          {:ok, Message.t()} | {:error, term()}
  def send_message(%{user: %User{id: sender_id}}, attrs) when is_map(attrs) do
    with :ok <- validate_chat_access(sender_id, attrs),
         :ok <- check_slowdown(sender_id, attrs),
         {:ok, attrs} <- run_before_hook(sender_id, attrs) do
      do_send_message(sender_id, attrs)
    end
  end

  defp run_before_hook(sender_id, attrs) do
    case Accounts.get_user(sender_id) do
      nil ->
        {:error, :user_not_found}

      user ->
        case GameServer.Hooks.internal_call(:before_chat_message, [user, attrs]) do
          {:ok, attrs} -> {:ok, attrs}
          {:error, reason} -> {:error, {:hook_rejected, reason}}
        end
    end
  end

  defp do_send_message(sender_id, attrs) do
    changeset =
      %Message{sender_id: sender_id}
      |> Message.changeset(attrs)

    case Repo.insert(changeset) do
      {:ok, message} ->
        message = Repo.preload(message, :sender)
        chat_type = message.chat_type
        chat_ref_id = message.chat_ref_id

        invalidate_chat_cache(chat_type, chat_ref_id)
        broadcast_chat(chat_type, chat_ref_id, sender_id, {:chat_message_created, message})

        GameServer.Async.run(fn ->
          GameServer.Hooks.internal_call(:after_chat_message, [message])
          GameServer.Quests.report_event(sender_id, "chat_message")
          send_chat_notifications(message)
        end)

        {:ok, message}

      {:error, _changeset} = err ->
        err
    end
  end

  defp send_chat_notifications(message) do
    alias GameServer.Notifications

    case message.chat_type do
      "friend" ->
        # Consolidated: one notification per recipient for ALL friend DMs
        # Use recipient_id as sender_id so upsert groups all friend messages together
        recipient_id = message.chat_ref_id

        Notifications.create_chat_notification(recipient_id, recipient_id, %{
          "title" => "New messages from friends",
          "content" => "",
          "metadata" => %{"type" => "chat_friend", "chat_type" => "friend"}
        })

      "group" ->
        group = GameServer.Groups.get_group(message.chat_ref_id)
        group_name = (group && group.title) || "Group #{message.chat_ref_id}"

        members = GameServer.Groups.get_group_members(message.chat_ref_id)

        for member <- members, member.user_id != message.sender_id do
          # Consolidated: one notification per recipient per group
          # Use recipient's own ID as sender_id so upsert groups all group messages together
          Notifications.create_chat_notification(member.user_id, member.user_id, %{
            "title" => "New messages from #{group_name}",
            "content" => "",
            "metadata" => %{
              "type" => "chat_group",
              "chat_type" => "group",
              "group_id" => message.chat_ref_id
            }
          })
        end

      "lobby" ->
        lobby = GameServer.Lobbies.get_lobby(message.chat_ref_id)
        lobby_name = (lobby && lobby.title) || "Lobby #{message.chat_ref_id}"

        lobby_users = GameServer.Lobbies.get_lobby_members(message.chat_ref_id)

        for user <- lobby_users, user.id != message.sender_id do
          # Consolidated: one notification per recipient per lobby
          Notifications.create_chat_notification(user.id, user.id, %{
            "title" => "New messages from #{lobby_name}",
            "content" => "",
            "metadata" => %{
              "type" => "chat_lobby",
              "chat_type" => "lobby",
              "lobby_id" => message.chat_ref_id
            }
          })
        end

      "party" ->
        send_party_chat_notifications(message)

      _ ->
        :ok
    end
  rescue
    error ->
      Logger.warning("Chat notification failed: #{inspect(error)}")
      :ok
  end

  defp send_party_chat_notifications(message) do
    alias GameServer.{Notifications, Parties}

    members = Parties.get_party_members(message.chat_ref_id)

    for member <- members, member.id != message.sender_id do
      Notifications.create_chat_notification(member.id, member.id, %{
        "title" => "New message in party",
        "content" => "",
        "metadata" => %{
          "type" => "chat_party",
          "chat_type" => "party",
          "party_id" => message.chat_ref_id
        }
      })
    end
  rescue
    error ->
      Logger.warning("Party chat notification failed: #{inspect(error)}")
      :ok
  end

  # ---------------------------------------------------------------------------
  # Access validation
  # ---------------------------------------------------------------------------

  @doc "Returns `:ok` when user can access the chat conversation."
  @spec authorize_access(Ecto.UUID.t(), String.t(), Ecto.UUID.t()) :: :ok | {:error, atom()}
  def authorize_access(user_id, chat_type, chat_ref_id)
      when is_binary(user_id) and is_binary(chat_type) and is_binary(chat_ref_id) do
    validate_chat_access(user_id, %{chat_type: chat_type, chat_ref_id: chat_ref_id})
  end

  def authorize_access(_user_id, _chat_type, _chat_ref_id), do: {:error, :invalid_chat_ref}

  defp validate_chat_access(sender_id, %{"chat_type" => "lobby", "chat_ref_id" => lobby_id}) do
    validate_chat_access(sender_id, %{chat_type: "lobby", chat_ref_id: lobby_id})
  end

  defp validate_chat_access(sender_id, %{chat_type: "lobby", chat_ref_id: lobby_id}) do
    case Accounts.get_user(sender_id) do
      %User{lobby_id: ^lobby_id} when lobby_id != nil -> :ok
      _ -> {:error, :not_in_lobby}
    end
  end

  defp validate_chat_access(sender_id, %{"chat_type" => "group", "chat_ref_id" => group_id}) do
    validate_chat_access(sender_id, %{chat_type: "group", chat_ref_id: group_id})
  end

  defp validate_chat_access(sender_id, %{chat_type: "group", chat_ref_id: group_id}) do
    case GameServer.Groups.get_membership(group_id, sender_id) do
      nil -> {:error, :not_in_group}
      _member -> :ok
    end
  end

  defp validate_chat_access(sender_id, %{
         "chat_type" => "friend",
         "chat_ref_id" => friend_id
       }) do
    validate_chat_access(sender_id, %{chat_type: "friend", chat_ref_id: friend_id})
  end

  defp validate_chat_access(sender_id, %{chat_type: "friend", chat_ref_id: friend_id}) do
    cond do
      GameServer.Friends.blocked?(sender_id, friend_id) ->
        {:error, :blocked}

      GameServer.Friends.friends?(sender_id, friend_id) ->
        :ok

      true ->
        {:error, :not_friends}
    end
  end

  defp validate_chat_access(sender_id, %{"chat_type" => "party", "chat_ref_id" => party_id}) do
    validate_chat_access(sender_id, %{chat_type: "party", chat_ref_id: party_id})
  end

  defp validate_chat_access(sender_id, %{chat_type: "party", chat_ref_id: party_id}) do
    case Accounts.get_user(sender_id) do
      %User{party_id: ^party_id} when party_id != nil -> :ok
      _ -> {:error, :not_in_party}
    end
  end

  defp validate_chat_access(_sender_id, _attrs), do: {:error, :invalid_chat_type}

  # ---------------------------------------------------------------------------
  # Slowdown enforcement
  # ---------------------------------------------------------------------------

  defp check_slowdown(sender_id, %{"chat_type" => "group", "chat_ref_id" => ref_id}) do
    group_id = ref_id

    case GameServer.Groups.get_group(group_id) do
      nil -> :ok
      group -> enforce_slowdown(sender_id, "group", group_id, group.slowdown)
    end
  end

  defp check_slowdown(sender_id, %{"chat_type" => "lobby", "chat_ref_id" => ref_id}) do
    lobby_id = ref_id

    case GameServer.Lobbies.get_lobby(lobby_id) do
      nil -> :ok
      lobby -> enforce_slowdown(sender_id, "lobby", lobby_id, lobby.slowdown)
    end
  end

  defp check_slowdown(_sender_id, _attrs), do: :ok

  defp enforce_slowdown(_sender_id, _chat_type, _ref_id, slowdown)
       when is_nil(slowdown) or slowdown <= 0,
       do: :ok

  defp enforce_slowdown(sender_id, chat_type, ref_id, slowdown) do
    cutoff = DateTime.add(DateTime.utc_now(), -slowdown, :second)

    last_msg =
      from(m in Message,
        where:
          m.sender_id == ^sender_id and
            m.chat_type == ^chat_type and
            m.chat_ref_id == ^ref_id and
            m.inserted_at > ^cutoff,
        select: m.id,
        limit: 1
      )
      |> Repo.one()

    if last_msg do
      {:error, :slowdown}
    else
      :ok
    end
  end

  # ---------------------------------------------------------------------------
  # List messages (paginated, cached)
  # ---------------------------------------------------------------------------

  @doc """
  List messages for a chat conversation.

  ## Options

    * `:page` — page number (default 1)
    * `:page_size` — items per page (default 25)

  Returns a list of `%Message{}` structs ordered by `inserted_at` descending
  (newest first).
  """
  @spec list_messages(String.t(), Ecto.UUID.t(), keyword()) :: [Message.t()]
  def list_messages(chat_type, chat_ref_id, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 25)
    offset = (page - 1) * page_size

    do_list_messages(chat_type, chat_ref_id, page, page_size, offset)
  end

  @decorate cacheable(
              key:
                {:chat, :list, chat_version(chat_type, chat_ref_id), chat_type, chat_ref_id, page,
                 page_size},
              opts: [ttl: @chat_cache_ttl_ms]
            )
  defp do_list_messages(chat_type, chat_ref_id, page, page_size, offset) do
    _ = page

    base_query(chat_type, chat_ref_id)
    |> order_by([m], desc: m.inserted_at, desc: m.id)
    |> limit(^page_size)
    |> offset(^offset)
    |> preload(:sender)
    |> Repo.all()
  end

  @doc """
  List friend DM messages between two users.

  Convenience wrapper that queries messages in both directions.

  ## Options

    * `:page` — page number (default 1)
    * `:page_size` — items per page (default 25)
  """
  @spec list_friend_messages(String.t(), String.t(), keyword()) :: [Message.t()]
  def list_friend_messages(user_a_id, user_b_id, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 25)
    offset = (page - 1) * page_size

    from(m in Message,
      where:
        (m.chat_type == "friend" and m.sender_id == ^user_a_id and m.chat_ref_id == ^user_b_id) or
          (m.chat_type == "friend" and m.sender_id == ^user_b_id and m.chat_ref_id == ^user_a_id),
      order_by: [desc: m.inserted_at, desc: m.id],
      limit: ^page_size,
      offset: ^offset,
      preload: [:sender]
    )
    |> Repo.all()
  end

  # ---------------------------------------------------------------------------
  # Count helpers
  # ---------------------------------------------------------------------------

  @doc "Count total messages in a chat conversation."
  @spec count_messages(String.t(), Ecto.UUID.t()) :: non_neg_integer()
  def count_messages(chat_type, chat_ref_id) do
    base_query(chat_type, chat_ref_id)
    |> Repo.aggregate(:count, :id)
  end

  @doc "Count total friend DM messages between two users."
  @spec count_friend_messages(String.t(), String.t()) :: non_neg_integer()
  def count_friend_messages(user_a_id, user_b_id) do
    from(m in Message,
      where:
        (m.chat_type == "friend" and m.sender_id == ^user_a_id and m.chat_ref_id == ^user_b_id) or
          (m.chat_type == "friend" and m.sender_id == ^user_b_id and m.chat_ref_id == ^user_a_id)
    )
    |> Repo.aggregate(:count, :id)
  end

  defp base_query("friend", _chat_ref_id) do
    # For friend chats, callers should use list_friend_messages/3 instead
    from(m in Message, where: false)
  end

  defp base_query(chat_type, chat_ref_id) do
    from(m in Message,
      where: m.chat_type == ^chat_type and m.chat_ref_id == ^chat_ref_id
    )
  end

  # ---------------------------------------------------------------------------
  # Read cursors
  # ---------------------------------------------------------------------------

  @doc """
  Mark a chat conversation as read up to a given message id.

  Uses an upsert to create or update the read cursor.
  """
  @spec mark_read(Ecto.UUID.t(), String.t(), Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, ReadCursor.t()} | {:error, term()}
  def mark_read(user_id, chat_type, chat_ref_id, message_id) do
    with :ok <- authorize_access(user_id, chat_type, chat_ref_id),
         :ok <- validate_read_message(user_id, chat_type, chat_ref_id, message_id) do
      attrs = %{
        chat_type: chat_type,
        chat_ref_id: chat_ref_id,
        last_read_message_id: message_id
      }

      %ReadCursor{user_id: user_id}
      |> ReadCursor.changeset(attrs)
      |> Repo.insert(
        on_conflict: [
          set: [last_read_message_id: message_id, updated_at: DateTime.utc_now(:second)]
        ],
        conflict_target: {:unsafe_fragment, "(user_id, chat_type, chat_ref_id)"}
      )
    end
  end

  defp validate_read_message(_user_id, _chat_type, _chat_ref_id, message_id)
       when not is_binary(message_id),
       do: {:error, :invalid_message}

  defp validate_read_message(user_id, "friend", friend_id, message_id) do
    case Repo.get(Message, message_id) do
      %Message{chat_type: "friend", sender_id: ^user_id, chat_ref_id: ^friend_id} ->
        :ok

      %Message{chat_type: "friend", sender_id: ^friend_id, chat_ref_id: ^user_id} ->
        :ok

      nil ->
        {:error, :message_not_found}

      _message ->
        {:error, :message_not_in_chat}
    end
  end

  defp validate_read_message(_user_id, chat_type, chat_ref_id, message_id) do
    case Repo.get(Message, message_id) do
      %Message{chat_type: ^chat_type, chat_ref_id: ^chat_ref_id} -> :ok
      nil -> {:error, :message_not_found}
      _message -> {:error, :message_not_in_chat}
    end
  end

  @doc """
  Get the read cursor for a user in a chat conversation.

  Returns `nil` if the user has never opened this conversation.
  """
  @spec get_read_cursor(Ecto.UUID.t(), String.t(), Ecto.UUID.t()) :: ReadCursor.t() | nil
  def get_read_cursor(user_id, chat_type, chat_ref_id) do
    from(c in ReadCursor,
      where: c.user_id == ^user_id and c.chat_type == ^chat_type and c.chat_ref_id == ^chat_ref_id
    )
    |> Repo.one()
  end

  @doc """
  Count unread messages for a user in a specific chat conversation.

  Returns 0 if the user has read all messages or has no cursor (all are unread
  in which case `count_messages/2` should be used instead).
  """
  @spec count_unread(Ecto.UUID.t(), String.t(), Ecto.UUID.t()) :: non_neg_integer()
  def count_unread(user_id, chat_type, chat_ref_id) do
    case get_read_cursor(user_id, chat_type, chat_ref_id) do
      nil ->
        # Never read — all messages are unread
        count_messages(chat_type, chat_ref_id)

      %ReadCursor{last_read_message_id: nil} ->
        count_messages(chat_type, chat_ref_id)

      %ReadCursor{last_read_message_id: last_id} ->
        from(m in Message,
          where:
            m.chat_type == ^chat_type and m.chat_ref_id == ^chat_ref_id and
              m.id > ^last_id
        )
        |> Repo.aggregate(:count, :id)
    end
  end

  @doc """
  Count unread friend DMs between two users for a specific user.
  """
  @spec count_unread_friend(Ecto.UUID.t(), Ecto.UUID.t()) :: non_neg_integer()
  def count_unread_friend(user_id, friend_id) do
    cursor = get_read_cursor(user_id, "friend", friend_id)

    query =
      from(m in Message,
        where: m.chat_type == "friend" and m.sender_id == ^friend_id and m.chat_ref_id == ^user_id
      )

    case cursor do
      nil ->
        Repo.aggregate(query, :count, :id)

      %ReadCursor{last_read_message_id: nil} ->
        Repo.aggregate(query, :count, :id)

      %ReadCursor{last_read_message_id: last_id} ->
        from(m in query, where: m.id > ^last_id)
        |> Repo.aggregate(:count, :id)
    end
  end

  @doc """
  Count unread friend DMs for a user across all friends.

  Returns a map of `%{friend_id => unread_count}` for friends that have
  at least one unread message.
  """
  @spec count_unread_friends_batch(Ecto.UUID.t(), [Ecto.UUID.t()]) :: %{
          Ecto.UUID.t() => non_neg_integer()
        }
  def count_unread_friends_batch(_user_id, []), do: %{}

  def count_unread_friends_batch(user_id, friend_ids) do
    from(m in Message,
      left_join: c in ReadCursor,
      on:
        c.user_id == ^user_id and c.chat_type == "friend" and
          c.chat_ref_id == m.sender_id,
      where:
        m.chat_type == "friend" and m.sender_id in ^friend_ids and
          m.chat_ref_id == ^user_id,
      where: is_nil(c.last_read_message_id) or m.id > c.last_read_message_id,
      group_by: m.sender_id,
      select: {m.sender_id, count(m.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Count unread messages for a user in multiple group chats.

  Returns a map of `%{group_id => unread_count}`.
  """
  @spec count_unread_groups_batch(Ecto.UUID.t(), [Ecto.UUID.t()]) :: %{
          Ecto.UUID.t() => non_neg_integer()
        }
  def count_unread_groups_batch(_user_id, []), do: %{}

  def count_unread_groups_batch(user_id, group_ids) do
    from(m in Message,
      left_join: c in ReadCursor,
      on:
        c.user_id == ^user_id and c.chat_type == "group" and
          c.chat_ref_id == m.chat_ref_id,
      where: m.chat_type == "group" and m.chat_ref_id in ^group_ids,
      where: is_nil(c.last_read_message_id) or m.id > c.last_read_message_id,
      group_by: m.chat_ref_id,
      select: {m.chat_ref_id, count(m.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  # ---------------------------------------------------------------------------
  # Delete helpers (for cleanup / admin)
  # ---------------------------------------------------------------------------

  @doc "Delete all messages for a given chat conversation."
  @spec delete_messages(String.t(), Ecto.UUID.t()) :: {non_neg_integer(), nil}
  def delete_messages(chat_type, chat_ref_id) do
    result =
      from(m in Message,
        where: m.chat_type == ^chat_type and m.chat_ref_id == ^chat_ref_id
      )
      |> Repo.delete_all()

    invalidate_chat_cache(chat_type, chat_ref_id)
    result
  end

  @doc "Delete all read cursors for a given chat conversation."
  @spec delete_read_cursors(String.t(), Ecto.UUID.t()) :: {non_neg_integer(), nil}
  def delete_read_cursors(chat_type, chat_ref_id) do
    from(c in ReadCursor,
      where: c.chat_type == ^chat_type and c.chat_ref_id == ^chat_ref_id
    )
    |> Repo.delete_all()
  end

  @doc "Delete all chat data (messages + read cursors) for a given conversation."
  @spec cleanup_chat(String.t(), Ecto.UUID.t()) :: :ok
  def cleanup_chat(chat_type, chat_ref_id) do
    delete_messages(chat_type, chat_ref_id)
    delete_read_cursors(chat_type, chat_ref_id)
    :ok
  end

  @doc """
  Delete all friend DM messages and read cursors between two users.

  Friend messages are stored bidirectionally (each user's messages use
  the other's id as chat_ref_id), so both directions must be cleaned up.
  """
  @spec cleanup_friend_chat(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok
  def cleanup_friend_chat(user_a_id, user_b_id) do
    # Delete messages in both directions
    from(m in Message,
      where:
        (m.chat_type == "friend" and m.sender_id == ^user_a_id and m.chat_ref_id == ^user_b_id) or
          (m.chat_type == "friend" and m.sender_id == ^user_b_id and m.chat_ref_id == ^user_a_id)
    )
    |> Repo.delete_all()

    # Delete read cursors for both users
    from(c in ReadCursor,
      where:
        (c.chat_type == "friend" and c.user_id == ^user_a_id and c.chat_ref_id == ^user_b_id) or
          (c.chat_type == "friend" and c.user_id == ^user_b_id and c.chat_ref_id == ^user_a_id)
    )
    |> Repo.delete_all()

    invalidate_chat_cache("friend", user_a_id)
    invalidate_chat_cache("friend", user_b_id)
    :ok
  end

  @doc "Get a single message by id."
  @spec get_message(Ecto.UUID.t()) :: Message.t() | nil
  @decorate cacheable(
              key: {:chat, :message, message_row_version(), id},
              match: &(&1 != nil),
              opts: [ttl: @chat_cache_ttl_ms]
            )
  def get_message(id) do
    Repo.get(Message, id)
  end

  # ---------------------------------------------------------------------------
  # Update / Delete own messages
  # ---------------------------------------------------------------------------

  @doc """
  Update a chat message owned by the given user.

  Only the `content` and `metadata` fields can be changed. Returns
  `{:error, :not_found}` if the message does not exist or
  `{:error, :forbidden}` if the caller is not the sender.
  """
  @spec update_message(Ecto.UUID.t(), Ecto.UUID.t(), map()) ::
          {:ok, Message.t()} | {:error, term()}
  def update_message(user_id, message_id, attrs) do
    case Repo.get(Message, message_id) do
      nil ->
        {:error, :not_found}

      %Message{sender_id: ^user_id} = message ->
        message
        |> Message.update_changeset(attrs)
        |> Repo.update()
        |> case do
          {:ok, updated} ->
            updated = Repo.preload(updated, :sender)
            invalidate_chat_cache(updated.chat_type, updated.chat_ref_id)

            broadcast_chat(
              updated.chat_type,
              updated.chat_ref_id,
              updated.sender_id,
              {:chat_message_updated, updated}
            )

            {:ok, updated}

          {:error, _cs} = err ->
            err
        end

      %Message{} ->
        {:error, :forbidden}
    end
  end

  @doc """
  Delete a chat message owned by the given user.

  Returns `{:error, :not_found}` if the message does not exist or
  `{:error, :forbidden}` if the caller is not the sender.
  """
  @spec delete_own_message(Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, Message.t()} | {:error, term()}
  def delete_own_message(user_id, message_id) do
    case Repo.get(Message, message_id) do
      nil ->
        {:error, :not_found}

      %Message{sender_id: ^user_id} = message ->
        case Repo.delete(message) do
          {:ok, deleted} ->
            invalidate_chat_cache(deleted.chat_type, deleted.chat_ref_id)

            broadcast_chat(
              deleted.chat_type,
              deleted.chat_ref_id,
              deleted.sender_id,
              {:chat_message_deleted, deleted}
            )

            {:ok, deleted}

          {:error, _cs} = err ->
            err
        end

      %Message{} ->
        {:error, :forbidden}
    end
  end

  # ---------------------------------------------------------------------------
  # Admin helpers
  # ---------------------------------------------------------------------------

  @doc "List all messages (admin). Supports filters: sender_id, chat_type, chat_ref_id, content."
  @spec list_all_messages(map(), keyword()) :: [Message.t()]
  def list_all_messages(filters \\ %{}, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 25)
    sort_by = Keyword.get(opts, :sort_by, nil)
    offset = (page - 1) * page_size

    base_admin_query(filters)
    |> admin_sort(sort_by)
    |> limit(^page_size)
    |> offset(^offset)
    |> preload(:sender)
    |> Repo.all()
  end

  @doc "Count all messages matching filters (admin)."
  @spec count_all_messages(map()) :: non_neg_integer()
  def count_all_messages(filters \\ %{}) do
    base_admin_query(filters) |> Repo.aggregate(:count, :id)
  end

  @doc "Count distinct users who have sent at least one chat message."
  @spec count_unique_senders() :: non_neg_integer()
  def count_unique_senders do
    from(m in Message, select: count(m.sender_id, :distinct))
    |> Repo.one()
  end

  @doc ~S"""
  Count messages grouped by chat_type.

  Returns a map like `%{"lobby" => 10, "group" => 5, "friend" => 3}`.
  """
  @spec count_messages_by_type() :: map()
  def count_messages_by_type do
    from(m in Message, group_by: m.chat_type, select: {m.chat_type, count(m.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc "Admin: delete a single message by id."
  @spec admin_delete_message(Ecto.UUID.t()) :: {:ok, Message.t()} | {:error, term()}
  def admin_delete_message(id) do
    case Repo.get(Message, id) do
      nil ->
        {:error, :not_found}

      message ->
        result = Repo.delete(message)
        invalidate_chat_cache(message.chat_type, message.chat_ref_id)
        result
    end
  end

  defp base_admin_query(filters) do
    query = from(m in Message)

    query =
      case Map.get(filters, :sender_id) || Map.get(filters, "sender_id") do
        nil -> query
        "" -> query
        v -> where(query, [m], m.sender_id == ^to_string(v))
      end

    query =
      case Map.get(filters, :chat_type) || Map.get(filters, "chat_type") do
        nil -> query
        "" -> query
        v -> where(query, [m], m.chat_type == ^v)
      end

    query =
      case Map.get(filters, :chat_ref_id) || Map.get(filters, "chat_ref_id") do
        nil -> query
        "" -> query
        v -> where(query, [m], m.chat_ref_id == ^to_string(v))
      end

    query =
      case Map.get(filters, :content) || Map.get(filters, "content") do
        nil ->
          query

        "" ->
          query

        v ->
          pattern = "%#{Repo.escape_like(v)}%"
          where(query, [m], fragment("? LIKE ? ESCAPE '\\'", m.content, ^pattern))
      end

    query
  end

  defp admin_sort(query, "inserted_at_asc"), do: order_by(query, [m], asc: m.inserted_at)
  defp admin_sort(query, "inserted_at"), do: order_by(query, [m], desc: m.inserted_at)
  defp admin_sort(query, _), do: order_by(query, [m], desc: m.inserted_at)
end
