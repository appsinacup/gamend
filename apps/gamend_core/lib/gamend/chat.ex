defmodule Gamend.Chat do
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

  use Nebulex.Caching, cache: Gamend.Cache

  alias Gamend.Accounts
  alias Gamend.Accounts.User
  alias Gamend.Chat.Message
  alias Gamend.Chat.Moderation
  alias Gamend.Chat.ReadCursor
  alias Gamend.Chat.Reports
  alias Gamend.Repo

  require Logger

  # ---------------------------------------------------------------------------
  # Cache helpers
  # ---------------------------------------------------------------------------

  defp chat_version(chat_type, chat_ref_id) do
    Gamend.Cache.get!({:chat, :version, chat_type, chat_ref_id}) || 1
  end

  # Global row-version for get_message/1 (no chat_type/ref available at read time).
  defp message_row_version, do: Gamend.Cache.get!({:chat, :message_version}) || 1
  defp bump_message_row, do: Gamend.Cache.bump_version({:chat, :message_version})

  defp invalidate_chat_cache(chat_type, chat_ref_id) do
    Gamend.Async.run(fn ->
      _ = Gamend.Cache.bump_version({:chat, :version, chat_type, chat_ref_id})
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
    do: Phoenix.PubSub.subscribe(Gamend.PubSub, "chat:lobby:#{lobby_id}")

  @doc "Unsubscribe from lobby chat events."
  @spec unsubscribe_lobby_chat(Ecto.UUID.t()) :: :ok
  def unsubscribe_lobby_chat(lobby_id),
    do: Phoenix.PubSub.unsubscribe(Gamend.PubSub, "chat:lobby:#{lobby_id}")

  @doc "Subscribe to chat events for a group."
  @spec subscribe_group_chat(Ecto.UUID.t()) :: :ok | {:error, term()}
  def subscribe_group_chat(group_id),
    do: Phoenix.PubSub.subscribe(Gamend.PubSub, "chat:group:#{group_id}")

  @doc "Unsubscribe from group chat events."
  @spec unsubscribe_group_chat(Ecto.UUID.t()) :: :ok
  def unsubscribe_group_chat(group_id),
    do: Phoenix.PubSub.unsubscribe(Gamend.PubSub, "chat:group:#{group_id}")

  @doc "Subscribe to chat events for a friend DM conversation."
  @spec subscribe_friend_chat(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok | {:error, term()}
  def subscribe_friend_chat(user_a_id, user_b_id) do
    {low, high} = friend_pair(user_a_id, user_b_id)
    Phoenix.PubSub.subscribe(Gamend.PubSub, "chat:friend:#{low}:#{high}")
  end

  @doc "Unsubscribe from friend DM chat events."
  @spec unsubscribe_friend_chat(Ecto.UUID.t(), Ecto.UUID.t()) :: :ok
  def unsubscribe_friend_chat(user_a_id, user_b_id) do
    {low, high} = friend_pair(user_a_id, user_b_id)
    Phoenix.PubSub.unsubscribe(Gamend.PubSub, "chat:friend:#{low}:#{high}")
  end

  @doc "Subscribe to chat events for a party."
  @spec subscribe_party_chat(Ecto.UUID.t()) :: :ok | {:error, term()}
  def subscribe_party_chat(party_id),
    do: Phoenix.PubSub.subscribe(Gamend.PubSub, "chat:party:#{party_id}")

  @doc "Unsubscribe from party chat events."
  @spec unsubscribe_party_chat(Ecto.UUID.t()) :: :ok
  def unsubscribe_party_chat(party_id),
    do: Phoenix.PubSub.unsubscribe(Gamend.PubSub, "chat:party:#{party_id}")

  defp broadcast_chat(chat_type, chat_ref_id, sender_id, event) do
    topic = chat_topic(chat_type, chat_ref_id, sender_id)
    Gamend.Broadcast.publish(topic, event)

    # For friend DMs, also broadcast to the recipient's user topic so the
    # UserChannel can forward the message without subscribing to every pair.
    if chat_type == "friend" do
      Gamend.Broadcast.publish("user:#{chat_ref_id}", event)
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

  Moderation runs before the `before_chat_message` hook: a muted sender is
  rejected with `{:error, :muted}` and a blocked word with
  `{:error, :blocked_content}`, so a plugin never sees a message core already
  refused. The hook can then modify attrs or reject the message itself. The
  `after_chat_message` hook fires asynchronously after the message is persisted.
  """
  @spec send_message(map(), map()) ::
          {:ok, Message.t()} | {:error, term()}
  def send_message(%{user: %User{id: sender_id}}, attrs) when is_map(attrs) do
    with :ok <- validate_chat_access(sender_id, attrs),
         :ok <- check_slowdown(sender_id, attrs),
         :ok <- check_mute(sender_id, attrs),
         {:ok, attrs, flagged} <- apply_word_filter(attrs),
         {:ok, attrs} <- run_before_hook(sender_id, attrs) do
      do_send_message(sender_id, attrs, flagged)
    end
  end

  # ---------------------------------------------------------------------------
  # Moderation enforcement
  # ---------------------------------------------------------------------------

  defp check_mute(sender_id, attrs) do
    if Moderation.muted?(sender_id, attr(attrs, "chat_type"), attr(attrs, "chat_ref_id")) do
      {:error, :muted}
    else
      :ok
    end
  end

  defp apply_word_filter(attrs) do
    original = attr(attrs, "content")

    case Moderation.check_content(original) do
      # Pinned so a masked message still takes the branch that writes it back.
      {:ok, ^original, []} ->
        {:ok, attrs, []}

      {:ok, content, flagged} ->
        {:ok, attrs |> put_attr("content", content) |> mark_flagged(flagged), flagged}

      {:error, :blocked_content} ->
        {:error, :blocked_content}
    end
  end

  defp mark_flagged(attrs, []), do: attrs

  defp mark_flagged(attrs, _flagged) do
    metadata = attr(attrs, "metadata") || %{}
    put_attr(attrs, "metadata", Map.put(metadata, "flagged", true))
  end

  # Callers pass string keys over HTTP and atom keys from plugins.
  @attr_atoms %{
    "chat_type" => :chat_type,
    "chat_ref_id" => :chat_ref_id,
    "content" => :content,
    "metadata" => :metadata
  }

  defp attr(attrs, key) do
    Map.get(attrs, key) || Map.get(attrs, Map.fetch!(@attr_atoms, key))
  end

  defp put_attr(attrs, key, value) do
    atom_key = Map.fetch!(@attr_atoms, key)

    if Map.has_key?(attrs, atom_key) do
      Map.put(attrs, atom_key, value)
    else
      Map.put(attrs, key, value)
    end
  end

  defp run_before_hook(sender_id, attrs) do
    case Accounts.get_user(sender_id) do
      nil ->
        {:error, :user_not_found}

      user ->
        case Gamend.Hooks.internal_call(:before_chat_message, [user, attrs]) do
          {:ok, attrs} -> {:ok, attrs}
          {:error, reason} -> {:error, {:hook_rejected, reason}}
        end
    end
  end

  defp do_send_message(sender_id, attrs, flagged) do
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

        Gamend.Async.run(fn ->
          Gamend.Hooks.internal_call(:after_chat_message, [message])
          Gamend.Quests.report_event(sender_id, "chat_message")
          send_chat_notifications(message)
          # The filter runs before the insert, so a flagged message only has an
          # id to report against once it is committed.
          if flagged != [], do: Reports.report_flagged_message(message, flagged)
        end)

        {:ok, message}

      {:error, _changeset} = err ->
        err
    end
  end

  # Titles double as the consolidation key.
  #
  # `create_chat_notification/3` upserts on `(sender_id, recipient_id, title)`
  # and these set sender == recipient, so the title alone decides which
  # notifications merge. That made a *user-chosen name* the key: a group or
  # lobby named "friends" produced "New messages from friends" — the same slot
  # as the friend-DM notification — and the two merged, accumulating each
  # other's `message_count` and overwriting each other's routing metadata, so
  # tapping the notification opened the wrong conversation. Two lobbies sharing
  # a title collided the same way.
  #
  # Each chat type now has its own phrasing, so no name can reach another type's
  # slot. Group titles are unique, so a group name is safe to keep. Lobby and
  # party titles are not unique — but a user is in at most one lobby and one
  # party at a time (`users.lobby_id`, `users.party_id`), so those consolidate
  # by type and carry the id in metadata.
  defp send_chat_notifications(message) do
    case message.chat_type do
      "friend" ->
        # Consolidated: one notification per recipient for ALL friend DMs
        # Use recipient_id as sender_id so upsert groups all friend messages together
        recipient_id = message.chat_ref_id

        notify_chat(recipient_id, %{
          "title" => "New messages from friends",
          "content" => "",
          "metadata" => %{"type" => "chat_friend", "chat_type" => "friend"}
        })

      "group" ->
        group = Gamend.Groups.get_group(message.chat_ref_id)
        group_name = (group && group.title) || "Group #{message.chat_ref_id}"

        # Ids only. This used `get_group_members/1`, which preloads every
        # member's full user row — for a group at the default 10,000-member cap
        # that is 10,000 rows loaded to read one column from each, before the
        # per-recipient loop below even starts.
        member_ids = Gamend.Groups.group_member_ids(message.chat_ref_id)

        for member_id <- member_ids, member_id != message.sender_id do
          # Consolidated: one notification per recipient per group
          # Use recipient's own ID as sender_id so upsert groups all group messages together
          notify_chat(member_id, %{
            "title" => "New messages in group #{group_name}",
            "content" => "",
            "metadata" => %{
              "type" => "chat_group",
              "chat_type" => "group",
              "group_id" => message.chat_ref_id
            }
          })
        end

      "lobby" ->
        lobby_users = Gamend.Lobbies.get_lobby_members(message.chat_ref_id)

        for user <- lobby_users, user.id != message.sender_id do
          # Consolidated: one notification per recipient per lobby
          notify_chat(user.id, %{
            "title" => "New messages in your lobby",
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
    alias Gamend.Parties

    members = Parties.get_party_members(message.chat_ref_id)

    for member <- members, member.id != message.sender_id do
      notify_chat(member.id, %{
        "title" => "New messages in your party",
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

  # Runs in a background task, so a rejected write has no caller to return to.
  # Log it: an unregistered `metadata["type"]` once dropped every chat
  # notification without a trace.
  defp notify_chat(recipient_id, attrs) do
    case Gamend.Notifications.create_chat_notification(recipient_id, recipient_id, attrs) do
      {:ok, _notification} ->
        :ok

      {:error, reason} ->
        Logger.warning("chat notification not delivered to #{recipient_id}: #{inspect(reason)}")
        :ok
    end
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
    case Gamend.Groups.get_membership(group_id, sender_id) do
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
      Gamend.Friends.blocked?(sender_id, friend_id) ->
        {:error, :blocked}

      Gamend.Friends.friends?(sender_id, friend_id) ->
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

    case Gamend.Groups.get_group(group_id) do
      nil -> :ok
      group -> enforce_slowdown(sender_id, "group", group_id, group.slowdown)
    end
  end

  defp check_slowdown(sender_id, %{"chat_type" => "lobby", "chat_ref_id" => ref_id}) do
    lobby_id = ref_id

    case Gamend.Lobbies.get_lobby(lobby_id) do
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
    # Clamped here rather than in the query: `page` and `page_size` are part of
    # the cache key below, so an unclamped caller would mint an unbounded
    # number of distinct entries as well as reading an unbounded number of rows.
    page = Gamend.Limits.clamp_page(Keyword.get(opts, :page))
    page_size = Gamend.Limits.clamp_page_size(Keyword.get(opts, :page_size))
    offset = (page - 1) * page_size

    do_list_messages(chat_type, chat_ref_id, page, page_size, offset)
  end

  @decorate cacheable(
              key:
                {:chat, :list, chat_version(chat_type, chat_ref_id), chat_type, chat_ref_id, page,
                 page_size},
              opts: [ttl: Gamend.Cache.ttl()]
            )
  defp do_list_messages(chat_type, chat_ref_id, page, page_size, _offset) do
    base_query(chat_type, chat_ref_id)
    |> order_by([m], desc: m.inserted_at, desc: m.id)
    |> Gamend.Query.page(page: page, page_size: page_size)
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
        # Only ever forward. The cursor used to be set unconditionally, so two
        # marks racing (or arriving out of order from different tabs) could
        # leave it on an older message — and `count_unread/3` then counts
        # everything after that one, so the badge climbs back up with no way for
        # the reader to clear it. Ids are UUIDv7, so lexicographic order is
        # chronological, which is what `count_unread/3`'s `m.id > ^last_id`
        # already relies on.
        on_conflict:
          from(c in ReadCursor,
            update: [
              set: [last_read_message_id: ^message_id, updated_at: ^DateTime.utc_now(:second)]
            ],
            where: fragment("EXCLUDED.last_read_message_id > ?", c.last_read_message_id)
          ),
        conflict_target: {:unsafe_fragment, "(user_id, chat_type, chat_ref_id)"},
        # A mark that is not ahead of the cursor updates no row, which Ecto
        # reports as stale and raises on. That is the forward-only rule doing
        # its job — the chat page marks on its dead render and again on
        # connect, and the second raised through the mount.
        allow_stale: true
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
              opts: [ttl: Gamend.Cache.ttl()]
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
    sort_by = Keyword.get(opts, :sort_by, nil)

    base_admin_query(filters)
    |> admin_sort(sort_by)
    |> Gamend.Query.page(opts)
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

  # ---------------------------------------------------------------------------
  # Moderation (see Gamend.Chat.Moderation and Gamend.Chat.Reports)
  # ---------------------------------------------------------------------------
  #
  # Re-exported here because `Gamend.Chat` is the module the plugin SDK is
  # generated from (`@sdk_modules` in `mix gen.sdk`) — a plugin can only call
  # what lives on the context.

  @doc """
  Mute `user_id` in `scope` (`"global"`, `"lobby"`, `"group"` or `"party"`).

  `scope_ref_id` is the room id, or `nil` for a global mute. `attrs` may carry
  `expires_at` (nil means permanent), `reason` and `muted_by`.
  """
  @spec mute_user(Ecto.UUID.t(), String.t(), Ecto.UUID.t() | nil, map()) ::
          {:ok, Gamend.Chat.Mute.t()} | {:error, term()}
  defdelegate mute_user(user_id, scope, scope_ref_id, attrs \\ %{}), to: Moderation

  @doc "Lift a mute. Returns `{:ok, count}` — 0 when the user was not muted."
  @spec unmute_user(Ecto.UUID.t(), String.t(), Ecto.UUID.t() | nil) :: {:ok, non_neg_integer()}
  defdelegate unmute_user(user_id, scope, scope_ref_id \\ nil), to: Moderation

  @doc "Whether `user_id` is currently muted for the given chat."
  @spec muted?(Ecto.UUID.t(), String.t(), Ecto.UUID.t() | nil) :: boolean()
  defdelegate muted?(user_id, chat_type, chat_ref_id), to: Moderation

  @doc "List mutes. Filters: `:user_id`, `:scope`, `:scope_ref_id`, `:active`."
  @spec list_mutes(map(), keyword()) :: [Gamend.Chat.Mute.t()]
  defdelegate list_mutes(filters \\ %{}, opts \\ []), to: Moderation

  @doc "Count mutes matching `filters`."
  @spec count_mutes(map()) :: non_neg_integer()
  defdelegate count_mutes(filters \\ %{}), to: Moderation

  @doc "File a report about a message on behalf of `reporter_id`."
  @spec report_message(Ecto.UUID.t(), Ecto.UUID.t(), String.t() | nil) ::
          {:ok, Gamend.Chat.Report.t()} | {:error, term()}
  defdelegate report_message(reporter_id, message_id, reason \\ nil), to: Reports

  @doc "List reports. Filters: `:status`, `:reported_user_id`, `:reporter_id`."
  @spec list_reports(map(), keyword()) :: [Gamend.Chat.Report.t()]
  defdelegate list_reports(filters \\ %{}, opts \\ []), to: Reports

  @doc "Count reports matching `filters`."
  @spec count_reports(map()) :: non_neg_integer()
  defdelegate count_reports(filters \\ %{}), to: Reports

  @doc "Claim a report for review, moving it from open to reviewing."
  @spec review_report(Gamend.Chat.Report.t() | Ecto.UUID.t()) ::
          {:ok, Gamend.Chat.Report.t()} | {:error, term()}
  defdelegate review_report(report), to: Reports

  @doc "Resolve a report: set its status, with an optional note and resolver."
  @spec resolve_report(Gamend.Chat.Report.t() | Ecto.UUID.t(), String.t(), map()) ::
          {:ok, Gamend.Chat.Report.t()} | {:error, term()}
  defdelegate resolve_report(report, status, attrs \\ %{}), to: Reports

  @doc """
  Every blocklist entry matching `content`, as `[{word, severity, match_mode}]`.
  """
  @spec filter_hits(String.t()) :: [{String.t(), String.t(), String.t()}]
  defdelegate filter_hits(content), to: Moderation, as: :hits
end
