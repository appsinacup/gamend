defmodule GameServerWeb.ChatLive do
  use GameServerWeb, :live_view

  alias GameServer.Accounts
  alias GameServer.Accounts.Scope
  alias GameServer.Chat
  alias GameServer.Friends
  alias GameServer.Groups
  alias GameServerWeb.LiveHelpers

  @page_size 25

  @impl true
  def mount(_params, _session, socket) do
    user = Scope.user(socket.assigns.current_scope)

    friends = Friends.list_friends_for_user(user.id)
    my_groups = Groups.list_user_groups_with_role(user.id)

    friend_ids = Enum.map(friends, & &1.id)
    group_ids = Enum.map(my_groups, fn {g, _role} -> g.id end)

    # Compute unread counts
    friend_unread = Chat.count_unread_friends_batch(user.id, friend_ids)
    group_unread = Chat.count_unread_groups_batch(user.id, group_ids)

    # Subscribe to all chat topics so we can track incoming messages
    if connected?(socket) do
      for fid <- friend_ids, do: Chat.subscribe_friend_chat(user.id, fid)
      for gid <- group_ids, do: Chat.subscribe_group_chat(gid)
    end

    {:ok,
     socket
     |> assign(:user_id, user.id)
     |> assign(:friends, friends)
     |> assign(:my_groups, my_groups)
     |> assign(:friend_unread, friend_unread)
     |> assign(:group_unread, group_unread)
     # active conversation
     |> assign(:chat_type, nil)
     |> assign(:chat_target, nil)
     |> assign(:chat_target_name, nil)
     |> assign(:chat_target_user, nil)
     |> assign(:chat_target_icon, nil)
     # messages
     |> assign(:messages, [])
     |> assign(:page, 1)
     |> assign(:page_size, @page_size)
     |> assign(:has_more, false)
     # editing
     |> assign(:editing_message_id, nil)
     |> assign(:editing_message_content, "")}
  end

  @impl true
  def handle_params(%{"type" => "group", "id" => id_str}, _uri, socket) do
    if connected?(socket) do
      gid = parse_id(id_str)
      group = Groups.get_group(gid)

      if group do
        user = Scope.user(socket.assigns.current_scope)
        mark_group_chat_read(user.id, gid)

        {:noreply,
         socket
         |> assign(:chat_type, "group")
         |> assign(:chat_target, gid)
         |> assign(:chat_target_name, group.title || group.name)
         |> assign(:chat_target_user, nil)
         |> assign(:chat_target_icon, group.icon_url)
         |> assign(:page, 1)
         |> assign(:editing_message_id, nil)
         |> assign(:editing_message_content, "")
         |> update(:group_unread, &Map.delete(&1, gid))
         |> reload_messages()}
      else
        {:noreply, put_flash(socket, :error, gettext("Not found"))}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_params(%{"type" => "friend", "id" => id_str}, _uri, socket) do
    if connected?(socket) do
      fid = parse_id(id_str)
      target = Accounts.get_user(fid)

      if target do
        user = Scope.user(socket.assigns.current_scope)
        mark_friend_chat_read(user.id, fid)

        {:noreply,
         socket
         |> assign(:chat_type, "friend")
         |> assign(:chat_target, fid)
         |> assign(:chat_target_name, LiveHelpers.public_user_name(target))
         |> assign(:chat_target_user, target)
         |> assign(:chat_target_icon, nil)
         |> assign(:page, 1)
         |> assign(:editing_message_id, nil)
         |> assign(:editing_message_content, "")
         |> update(:friend_unread, &Map.delete(&1, fid))
         |> reload_messages()}
      else
        {:noreply, put_flash(socket, :error, gettext("Not found"))}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div>
        <h1 class="text-3xl font-bold mb-4">{gettext("Chat")}</h1>
      </div>
      <div class="flex gap-4 h-[calc(100vh-12rem)]">
        <%!-- Sidebar: contacts list --%>
        <div class={[
          "w-full md:w-64 flex-shrink-0 overflow-y-auto md:border-r border-base-300 md:pr-4",
          if(@chat_type, do: "hidden md:block", else: "block")
        ]}>
          <h3 class="font-semibold text-sm text-base-content/60 uppercase tracking-wide mb-2">
            {gettext("Friends")}
          </h3>
          <%= if @friends == [] do %>
            <p class="text-sm text-base-content/40 pl-2">{gettext("No results.")}</p>
          <% end %>
          <ul class="space-y-1">
            <li :for={f <- @friends}>
              <button
                phx-click="open_friend"
                phx-value-id={f.id}
                class={[
                  "btn btn-sm w-full justify-start gap-2 text-left",
                  if(@chat_type == "friend" && @chat_target == f.id,
                    do: "btn-primary",
                    else: "btn-ghost"
                  )
                ]}
              >
                <.user_avatar user={f} class="w-6 h-6 shrink-0" />
                <span class="truncate flex-1">{LiveHelpers.public_user_name(f)}</span>
                <%= if (count = Map.get(@friend_unread, f.id, 0)) > 0 do %>
                  <span class="badge badge-sm badge-info">{count}</span>
                <% end %>
              </button>
            </li>
          </ul>

          <div class="divider my-2"></div>

          <h3 class="font-semibold text-sm text-base-content/60 uppercase tracking-wide mb-2">
            {gettext("Groups")}
          </h3>
          <%= if @my_groups == [] do %>
            <p class="text-sm text-base-content/40 pl-2">{gettext("No results.")}</p>
          <% end %>
          <ul class="space-y-1">
            <li :for={{group, _role} <- @my_groups}>
              <button
                phx-click="open_group"
                phx-value-id={group.id}
                class={[
                  "btn btn-sm w-full justify-start gap-2 text-left",
                  if(@chat_type == "group" && @chat_target == group.id,
                    do: "btn-primary",
                    else: "btn-ghost"
                  )
                ]}
              >
                <.entity_icon icon_url={group.icon_url} type={:group} class="w-6 h-6 shrink-0" />
                <span class="truncate flex-1">{group.title || group.name}</span>
                <%= if (count = Map.get(@group_unread, group.id, 0)) > 0 do %>
                  <span class="badge badge-sm badge-info">{count}</span>
                <% end %>
              </button>
            </li>
          </ul>
        </div>

        <%!-- Main conversation area --%>
        <div class={[
          "flex-1 flex flex-col min-w-0",
          if(@chat_type, do: "flex", else: "hidden md:flex")
        ]}>
          <%= if @chat_type do %>
            <%!-- Header --%>
            <div class="flex items-center gap-2 pb-3 border-b border-base-300 mb-3">
              <button phx-click="close_chat" class="btn btn-xs btn-ghost md:hidden">
                ←
              </button>
              <.user_avatar :if={@chat_type == "friend"} user={@chat_target_user} class="w-7 h-7" />
              <.entity_icon
                :if={@chat_type == "group"}
                icon_url={@chat_target_icon}
                type={:group}
                class="w-7 h-7 text-base-content/60"
              />
              <h2 class="font-semibold text-lg truncate">{@chat_target_name}</h2>
            </div>

            <%!-- Messages --%>
            <div
              id="chat-messages"
              phx-hook="ScrollToBottom"
              class="flex-1 overflow-y-auto pr-2"
            >
              <div :if={@has_more} class="text-center py-2">
                <button phx-click="load_more" class="btn btn-xs btn-ghost">
                  {gettext("Older")}
                </button>
              </div>

              <%= if @messages == [] do %>
                <div class="text-sm text-base-content/50 text-center py-8">
                  {gettext("No results.")}
                </div>
              <% end %>

              <div
                :for={{show_header, msg} <- group_messages(@messages)}
                id={"msg-" <> to_string(msg.id)}
                class={[
                  "flex flex-col gap-0.5",
                  if(msg.sender_id == @user_id, do: "items-end", else: "items-start"),
                  if(show_header, do: "mt-3", else: "mt-0.5")
                ]}
              >
                <div :if={show_header} class="text-xs text-base-content/50">
                  <%= if msg.sender_id == @user_id do %>
                    {gettext("You")}
                  <% else %>
                    {sender_name(msg)}
                  <% end %>
                  <span class="ml-1"><.timestamp at={msg.inserted_at} format="time" /></span>
                  <%= if msg.updated_at && msg.updated_at != msg.inserted_at do %>
                    <span class="ml-1 italic">{gettext("(edited)")}</span>
                  <% end %>
                </div>

                <%= if @editing_message_id == msg.id do %>
                  <form
                    phx-submit="chat_edit_save"
                    id={"edit-" <> to_string(msg.id)}
                    class="flex gap-1 w-full max-w-[80%]"
                  >
                    <input type="hidden" name="message_id" value={msg.id} />
                    <input
                      type="text"
                      name="content"
                      value={@editing_message_content}
                      class="input input-bordered input-xs flex-1"
                      autocomplete="off"
                      phx-mounted={JS.dispatch("focus")}
                    />
                    <button type="submit" class="btn btn-xs btn-primary">
                      {gettext("Save")}
                    </button>
                    <button type="button" phx-click="chat_edit_cancel" class="btn btn-xs btn-ghost">
                      {gettext("Cancel")}
                    </button>
                  </form>
                <% else %>
                  <div class={[
                    "group flex items-end gap-1 w-full",
                    if(msg.sender_id == @user_id, do: "justify-end", else: "justify-start")
                  ]}>
                    <div
                      :if={msg.sender_id == @user_id}
                      class="flex-shrink-0 flex gap-0.5 lg:opacity-0 lg:group-hover:opacity-100 transition-opacity"
                    >
                      <button
                        phx-click="chat_edit_start"
                        phx-value-id={msg.id}
                        phx-value-content={msg.content}
                        class="btn btn-xs btn-ghost min-h-[2rem] min-w-[2rem] px-2 lg:px-1"
                        title={gettext("Edit")}
                      >
                        {gettext("Edit")}
                      </button>
                      <button
                        phx-click="chat_delete"
                        phx-value-id={msg.id}
                        data-confirm={gettext("Delete?")}
                        class="btn btn-xs btn-ghost min-h-[2rem] min-w-[2rem] px-2 lg:px-1 text-error"
                        title={gettext("Delete")}
                      >
                        {gettext("Delete")}
                      </button>
                    </div>
                    <div class={[
                      "px-3 py-1.5 rounded-lg text-sm max-w-[80%] break-words",
                      if(msg.sender_id == @user_id,
                        do: "bg-primary text-primary-content",
                        else: "bg-base-200"
                      )
                    ]}>
                      {msg.content}
                    </div>
                  </div>
                <% end %>
              </div>
            </div>

            <%!-- Send form --%>
            <form
              phx-submit="send_message"
              id="chat-send-form"
              class="flex gap-2 mt-3 pt-3 border-t border-base-300"
            >
              <input
                type="text"
                name="content"
                value=""
                placeholder={gettext("Send")}
                class="input input-bordered input-sm flex-1"
                autocomplete="off"
              />
              <button type="submit" class="btn btn-sm btn-primary">
                {gettext("Send")}
              </button>
            </form>
          <% else %>
            <div class="flex-1 flex items-center justify-center text-base-content/40">
              <div class="text-center">
                <p class="text-lg">{gettext("Select a conversation")}</p>
                <p class="text-sm mt-1">{gettext("Select a conversation")}</p>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # ---------------------------------------------------------------------------
  # Events
  # ---------------------------------------------------------------------------

  @impl true
  # Selection happens in handle_params, so the click only updates the URL —
  # that keeps the chosen conversation in the address bar and restores it on
  # refresh (previously the URL stayed /chat and a reload reset to no chat).
  def handle_event("open_friend", %{"id" => id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/chat?#{[type: "friend", id: id]}")}
  end

  def handle_event("open_group", %{"id" => id}, socket) do
    {:noreply, push_patch(socket, to: ~p"/chat?#{[type: "group", id: id]}")}
  end

  @impl true
  def handle_event("send_message", %{"content" => content}, socket) do
    content = String.trim(content)
    user = Scope.user(socket.assigns.current_scope)
    chat_type = socket.assigns.chat_type
    chat_target = socket.assigns.chat_target

    if chat_type && content != "" do
      attrs = %{
        "chat_type" => chat_type,
        "chat_ref_id" => chat_target,
        "content" => content
      }

      with :ok <- GameServerWeb.RateLimit.check_chat_daily(user.id),
           {:ok, _msg} <- Chat.send_message(%{user: user}, attrs) do
        {:noreply, reload_messages(socket)}
      else
        {:error, :chat_daily_limit} ->
          {:noreply, put_flash(socket, :error, gettext("Failed"))}

        {:error, :slowdown} ->
          {:noreply, put_flash(socket, :error, gettext("Failed"))}

        {:error, reason} ->
          {:noreply, put_failure_flash(socket, reason)}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("close_chat", _params, socket) do
    socket =
      socket
      |> assign(:chat_type, nil)
      |> assign(:chat_target, nil)
      |> assign(:chat_target_name, nil)
      |> assign(:chat_target_user, nil)
      |> assign(:chat_target_icon, nil)
      |> assign(:messages, [])
      |> assign(:page, 1)
      |> assign(:has_more, false)
      |> assign(:editing_message_id, nil)
      |> assign(:editing_message_content, "")

    {:noreply, socket}
  end

  @impl true
  def handle_event("load_more", _params, socket) do
    page = socket.assigns.page + 1
    {:noreply, socket |> assign(:page, page) |> reload_messages()}
  end

  @impl true
  def handle_event("chat_edit_start", %{"id" => id, "content" => content}, socket) do
    {:noreply,
     socket
     |> assign(:editing_message_id, parse_id(id))
     |> assign(:editing_message_content, content)}
  end

  @impl true
  def handle_event("chat_edit_cancel", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_message_id, nil)
     |> assign(:editing_message_content, "")}
  end

  @impl true
  def handle_event("chat_edit_save", %{"message_id" => id, "content" => content}, socket) do
    content = String.trim(content)

    if content != "" do
      case Chat.update_message(socket.assigns.current_scope.user_id, parse_id(id), %{
             "content" => content
           }) do
        {:ok, _msg} ->
          {:noreply,
           socket
           |> assign(:editing_message_id, nil)
           |> assign(:editing_message_content, "")
           |> reload_messages()}

        {:error, reason} ->
          {:noreply, put_failure_flash(socket, reason)}
      end
    else
      {:noreply, put_flash(socket, :error, gettext("Cannot be empty."))}
    end
  end

  @impl true
  def handle_event("chat_delete", %{"id" => id}, socket) do
    case Chat.delete_own_message(socket.assigns.current_scope.user_id, parse_id(id)) do
      {:ok, _msg} ->
        {:noreply,
         socket
         |> assign(:editing_message_id, nil)
         |> assign(:editing_message_content, "")
         |> reload_messages()}

      {:error, reason} ->
        {:noreply, put_failure_flash(socket, reason)}
    end
  end

  # ---------------------------------------------------------------------------
  # PubSub handlers
  # ---------------------------------------------------------------------------

  defp put_failure_flash(socket, reason) do
    LiveHelpers.put_failure(socket, LiveHelpers.failure_message(gettext("Failed"), reason))
  end

  @impl true
  def handle_info({:chat_message_created, msg}, socket) do
    user = Scope.user(socket.assigns.current_scope)

    if matches_current_chat?(socket, msg) do
      # Active chat — reload messages and mark read
      mark_current_chat_read(socket)
      {:noreply, reload_messages(socket)}
    else
      # Not the active chat — bump unread count in the sidebar
      socket = increment_unread(socket, msg, user.id)
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({event, msg}, socket)
      when event in [:chat_message_updated, :chat_message_deleted] do
    if matches_current_chat?(socket, msg) do
      {:noreply, reload_messages(socket)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp reload_messages(socket) do
    chat_type = socket.assigns.chat_type
    chat_target = socket.assigns.chat_target
    user = Scope.user(socket.assigns.current_scope)

    if chat_type && chat_target do
      page_size = socket.assigns.page_size
      page = socket.assigns.page
      total = min(page * page_size, 500)

      messages =
        case chat_type do
          "friend" ->
            Chat.list_friend_messages(user.id, chat_target, page: 1, page_size: total)

          "group" ->
            Chat.list_messages("group", chat_target, page: 1, page_size: total)
        end
        |> Enum.reverse()

      has_more = length(messages) >= total

      socket
      |> assign(:messages, messages)
      |> assign(:has_more, has_more)
    else
      socket
    end
  end

  defp mark_current_chat_read(socket) do
    user = Scope.user(socket.assigns.current_scope)

    case {socket.assigns.chat_type, socket.assigns.chat_target} do
      {"friend", fid} when is_integer(fid) -> mark_friend_chat_read(user.id, fid)
      {"group", gid} when is_integer(gid) -> mark_group_chat_read(user.id, gid)
      _ -> :ok
    end
  end

  defp increment_unread(socket, msg, user_id) do
    # Don't count our own messages as unread
    if msg.sender_id == user_id do
      socket
    else
      case msg.chat_type do
        "friend" ->
          fid = msg.sender_id
          update(socket, :friend_unread, fn m -> Map.update(m, fid, 1, &(&1 + 1)) end)

        "group" ->
          gid = msg.chat_ref_id
          update(socket, :group_unread, fn m -> Map.update(m, gid, 1, &(&1 + 1)) end)

        _ ->
          socket
      end
    end
  end

  defp matches_current_chat?(socket, msg) do
    chat_type = socket.assigns.chat_type
    chat_target = socket.assigns.chat_target

    cond do
      chat_type == "group" && msg.chat_type == "group" && msg.chat_ref_id == chat_target ->
        true

      chat_type == "friend" && msg.chat_type == "friend" &&
          (msg.sender_id == chat_target || msg.chat_ref_id == chat_target) ->
        true

      true ->
        false
    end
  end

  defp mark_friend_chat_read(user_id, friend_id) do
    case Chat.list_friend_messages(user_id, friend_id, page: 1, page_size: 1) do
      [latest | _] -> Chat.mark_read(user_id, "friend", friend_id, latest.id)
      _ -> :ok
    end
  end

  defp mark_group_chat_read(user_id, group_id) do
    case Chat.list_messages("group", group_id, page: 1, page_size: 1) do
      [latest | _] -> Chat.mark_read(user_id, "group", group_id, latest.id)
      _ -> :ok
    end
  end

  defp sender_name(msg) do
    if Ecto.assoc_loaded?(msg.sender) && msg.sender do
      LiveHelpers.public_user_name(msg.sender)
    else
      "User #{msg.sender_id}"
    end
  end

  defp group_messages(messages) do
    {result, _} =
      Enum.reduce(messages, {[], nil}, fn msg, {acc, prev} ->
        show_header =
          is_nil(prev) or
            prev.sender_id != msg.sender_id or
            different_minute?(prev.inserted_at, msg.inserted_at)

        {[{show_header, msg} | acc], msg}
      end)

    Enum.reverse(result)
  end

  defp different_minute?(t1, t2) do
    Calendar.strftime(t1, "%Y-%m-%d %H:%M") != Calendar.strftime(t2, "%Y-%m-%d %H:%M")
  end

  defp parse_id(id) when is_binary(id), do: id
end
