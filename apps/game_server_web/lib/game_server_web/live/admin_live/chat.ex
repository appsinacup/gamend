defmodule GameServerWeb.AdminLive.Chat do
  use GameServerWeb, :live_view

  alias GameServer.Chat

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page, 1)
      |> assign(:page_size, 25)
      |> assign(:filters, %{})
      |> assign(:selected_ids, MapSet.new())
      |> reload_messages()

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-6">
        <.link navigate={~p"/admin"} class="btn btn-outline mb-4">&larr; Back to Admin</.link>

        <div class="card bg-base-200">
          <div class="card-body">
            <div class="flex items-center justify-between gap-3">
              <h2 class="card-title">Chat Messages ({@count})</h2>
              <button
                type="button"
                phx-click="bulk_delete"
                data-confirm={"Delete #{MapSet.size(@selected_ids)} selected messages?"}
                class="btn btn-sm btn-outline btn-error"
                disabled={MapSet.size(@selected_ids) == 0}
              >
                Delete selected ({MapSet.size(@selected_ids)})
              </button>
            </div>

            <form phx-change="filter" id="admin-chat-filter-form">
              <div class="overflow-x-auto mt-4">
                <table class="table table-zebra w-full">
                  <thead>
                    <tr>
                      <th class="w-10">
                        <input
                          type="checkbox"
                          class="checkbox checkbox-sm"
                          phx-click="toggle_select_all"
                          checked={
                            @messages != [] &&
                              MapSet.size(@selected_ids) == length(@messages)
                          }
                        />
                      </th>
                      <th>ID</th>
                      <th>Sender ID</th>
                      <th>Type</th>
                      <th>Ref ID</th>
                      <th>Content</th>
                      <th>Metadata</th>
                      <th>Created</th>
                      <th>Actions</th>
                    </tr>
                    <tr>
                      <th></th>
                      <th></th>
                      <th>
                        <input
                          type="text"
                          name="sender_id"
                          value={@filters["sender_id"]}
                          class="input input-bordered input-xs w-full"
                          placeholder="Sender ID"
                          phx-debounce="300"
                        />
                      </th>
                      <th>
                        <select
                          name="chat_type"
                          class="select select-bordered select-xs w-full"
                        >
                          <option value="">All</option>
                          <option value="lobby" selected={@filters["chat_type"] == "lobby"}>
                            Lobby
                          </option>
                          <option value="group" selected={@filters["chat_type"] == "group"}>
                            Group
                          </option>
                          <option value="friend" selected={@filters["chat_type"] == "friend"}>
                            Friend
                          </option>
                        </select>
                      </th>
                      <th>
                        <input
                          type="text"
                          name="chat_ref_id"
                          value={@filters["chat_ref_id"]}
                          class="input input-bordered input-xs w-full"
                          placeholder="Ref ID"
                          phx-debounce="300"
                        />
                      </th>
                      <th>
                        <input
                          type="text"
                          name="content"
                          value={@filters["content"]}
                          class="input input-bordered input-xs w-full"
                          placeholder="Search content..."
                          phx-debounce="300"
                        />
                      </th>
                      <th></th>
                      <th></th>
                      <th></th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={m <- @messages} id={"admin-chat-msg-" <> to_string(m.id)}>
                      <td class="w-10">
                        <input
                          type="checkbox"
                          class="checkbox checkbox-sm"
                          phx-click="toggle_select"
                          phx-value-id={m.id}
                          checked={MapSet.member?(@selected_ids, m.id)}
                        />
                      </td>
                      <td class="font-mono text-sm">{m.id}</td>
                      <td class="text-sm" title={m.sender_id}>
                        {user_display(m.sender)}
                        <%= if Ecto.assoc_loaded?(m.sender) and m.sender do %>
                          <div class="text-xs text-base-content/60 truncate max-w-[120px]">
                            {m.sender.email}
                          </div>
                        <% end %>
                      </td>
                      <td>
                        <span class={[
                          "badge badge-sm",
                          m.chat_type == "lobby" && "badge-primary",
                          m.chat_type == "group" && "badge-secondary",
                          m.chat_type == "friend" && "badge-accent"
                        ]}>
                          {m.chat_type}
                        </span>
                      </td>
                      <td class="font-mono text-sm">{m.chat_ref_id}</td>
                      <td class="text-sm max-w-xs truncate">{m.content}</td>
                      <td class="text-xs font-mono max-w-xs truncate">
                        {Jason.encode!(m.metadata || %{})}
                      </td>
                      <td class="text-sm whitespace-nowrap">
                        <.timestamp at={m.inserted_at} />
                      </td>
                      <td class="text-sm">
                        <button
                          type="button"
                          phx-click="delete_message"
                          phx-value-id={m.id}
                          data-confirm="Are you sure?"
                          class="btn btn-xs btn-outline btn-error"
                        >
                          Delete
                        </button>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </form>

            <div class="mt-4">
              <.pagination
                page={@page}
                total_pages={@total_pages}
                total_count={@count}
                page_size={@page_size}
                on_prev="admin_chat_prev"
                on_next="admin_chat_next"
                on_page_size="admin_chat_page_size"
              />
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("filter", params, socket) do
    {:noreply,
     socket
     |> assign(:filters, params)
     |> assign(:page, 1)
     |> reload_messages()}
  end

  @impl true
  def handle_event("toggle_select", %{"id" => id}, socket) do
    id = to_string(id)
    selected = socket.assigns.selected_ids

    selected =
      if MapSet.member?(selected, id) do
        MapSet.delete(selected, id)
      else
        MapSet.put(selected, id)
      end

    {:noreply,
     socket
     |> assign(:selected_ids, selected)
     |> sync_selected_ids(message_ids(socket.assigns.messages))}
  end

  @impl true
  def handle_event("toggle_select_all", _params, socket) do
    messages = socket.assigns.messages
    ids = message_ids(messages)
    selected = socket.assigns.selected_ids

    selected =
      if ids != [] and MapSet.size(selected) == length(ids) do
        MapSet.new()
      else
        MapSet.new(ids)
      end

    {:noreply, assign(socket, :selected_ids, selected)}
  end

  @impl true
  def handle_event("bulk_delete", _params, socket) do
    ids = MapSet.to_list(socket.assigns.selected_ids)

    {deleted, failed} =
      Enum.reduce(ids, {0, 0}, fn id, {d, f} ->
        case Chat.admin_delete_message(id) do
          {:ok, _} -> {d + 1, f}
          {:error, _} -> {d, f + 1}
        end
      end)

    socket = assign(socket, :selected_ids, MapSet.new())

    socket =
      cond do
        failed == 0 ->
          put_flash(socket, :info, "Deleted #{deleted} messages")

        deleted == 0 ->
          put_flash(socket, :error, "Failed to delete selected messages")

        true ->
          put_flash(socket, :error, "Deleted #{deleted} messages; failed #{failed}")
      end

    {:noreply, socket |> reload_messages()}
  end

  @impl true
  def handle_event("delete_message", %{"id" => id}, socket) do
    message_id = to_string(id)

    case Chat.admin_delete_message(message_id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Message deleted")
         |> reload_messages()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete message")}
    end
  end

  @impl true
  def handle_event("admin_chat_prev", _params, socket) do
    page = max(1, socket.assigns.page - 1)
    {:noreply, socket |> assign(:page, page) |> reload_messages()}
  end

  @impl true
  def handle_event("admin_chat_next", _params, socket) do
    page = socket.assigns.page + 1
    {:noreply, socket |> assign(:page, page) |> reload_messages()}
  end

  @impl true
  def handle_event("admin_chat_page_size", %{"size" => size}, socket) do
    {:noreply,
     socket
     |> assign(:page_size, String.to_integer(size))
     |> assign(:page, 1)
     |> reload_messages()}
  end

  defp reload_messages(socket) do
    page = socket.assigns.page
    page_size = socket.assigns.page_size
    filters = socket.assigns.filters

    messages = Chat.list_all_messages(filters, page: page, page_size: page_size)
    total_count = Chat.count_all_messages(filters)

    total_pages =
      if page_size > 0,
        do: div(total_count + page_size - 1, page_size),
        else: 0

    socket
    |> assign(:messages, messages)
    |> assign(:count, total_count)
    |> assign(:total_pages, total_pages)
    |> assign(:page, page)
    |> sync_selected_ids(message_ids(messages))
  end

  defp message_ids(messages) when is_list(messages) do
    Enum.map(messages, & &1.id)
  end

  defp sync_selected_ids(socket, ids) when is_list(ids) do
    selected = socket.assigns.selected_ids
    allowed = MapSet.new(ids)
    assign(socket, :selected_ids, MapSet.intersection(selected, allowed))
  end
end
