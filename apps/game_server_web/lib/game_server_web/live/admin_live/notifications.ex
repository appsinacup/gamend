defmodule GameServerWeb.AdminLive.Notifications do
  use GameServerWeb, :live_view

  alias GameServer.Notifications

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page, 1)
      |> assign(:page_size, 25)
      |> assign(:filters, %{})
      |> assign(:selected_ids, MapSet.new())
      |> assign(:show_create, false)
      |> assign(
        :create_form,
        to_form(
          %{
            "sender_id" => "",
            "recipient_id" => "",
            "title" => "",
            "content" => "",
            "icon_url" => "",
            "metadata" => ""
          },
          as: :notification
        )
      )
      |> reload_notifications()

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-6">
        <.link navigate={~p"/admin"} class="btn btn-outline mb-4">← Back to Admin</.link>

        <%!-- Create notification form --%>
        <div class="card bg-base-200">
          <div class="card-body">
            <div class="flex flex-wrap items-center justify-between">
              <h2 class="card-title">Create Notification</h2>
              <button
                type="button"
                phx-click="toggle_create"
                class="btn btn-sm btn-outline"
              >
                {if @show_create, do: "Hide", else: "Show"}
              </button>
            </div>

            <%= if @show_create do %>
              <.form
                for={@create_form}
                id="admin-create-notification-form"
                phx-submit="create_notification"
                class="mt-4 space-y-3"
              >
                <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
                  <.input field={@create_form[:sender_id]} type="text" label="Sender ID" />
                  <.input field={@create_form[:recipient_id]} type="text" label="Recipient ID" />
                </div>
                <.input field={@create_form[:title]} type="text" label="Title" />
                <.input field={@create_form[:content]} type="text" label="Content (optional)" />
                <.input field={@create_form[:icon_url]} type="text" label="Icon URL (optional)" />
                <div class="form-control">
                  <label class="label">Metadata (JSON, optional)</label>
                  <textarea
                    name="notification[metadata]"
                    class="textarea textarea-bordered"
                    rows="3"
                  >{Phoenix.HTML.Form.input_value(@create_form, :metadata)}</textarea>
                </div>
                <button type="submit" class="btn btn-primary btn-sm">Send Notification</button>
              </.form>
            <% end %>
          </div>
        </div>

        <div class="card bg-base-200">
          <div class="card-body">
            <div class="flex flex-wrap items-center justify-between gap-3">
              <h2 class="card-title">Notifications ({@count})</h2>
              <button
                type="button"
                phx-click="bulk_delete"
                data-confirm={"Delete #{MapSet.size(@selected_ids)} selected notifications?"}
                class="btn btn-sm btn-outline btn-error"
                disabled={MapSet.size(@selected_ids) == 0}
              >
                Delete selected ({MapSet.size(@selected_ids)})
              </button>
            </div>

            <form phx-change="filter" id="notifications-filter-form">
              <div class="overflow-x-auto mt-4">
                <table class="table table-zebra w-full min-w-[48rem]">
                  <thead>
                    <tr>
                      <th class="w-10">
                        <input
                          type="checkbox"
                          class="checkbox checkbox-sm"
                          phx-click="toggle_select_all"
                          checked={
                            @notifications != [] &&
                              MapSet.size(@selected_ids) == length(@notifications)
                          }
                        />
                      </th>
                      <th>ID</th>
                      <th>Sender ID</th>
                      <th>Recipient ID</th>
                      <th>Title</th>
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
                        <input
                          type="text"
                          name="user_id"
                          value={@filters["user_id"]}
                          class="input input-bordered input-xs w-full"
                          placeholder="Recipient ID"
                          phx-debounce="300"
                        />
                      </th>
                      <th>
                        <input
                          type="text"
                          name="title"
                          value={@filters["title"]}
                          class="input input-bordered input-xs w-full"
                          placeholder="Filter title..."
                          phx-debounce="300"
                        />
                      </th>
                      <th></th>
                      <th></th>
                      <th></th>
                      <th></th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr
                      :for={n <- @notifications}
                      id={"admin-notification-" <> to_string(n.id)}
                    >
                      <td class="w-10">
                        <input
                          type="checkbox"
                          class="checkbox checkbox-sm"
                          phx-click="toggle_select"
                          phx-value-id={n.id}
                          checked={MapSet.member?(@selected_ids, n.id)}
                        />
                      </td>
                      <td class="font-mono text-sm">{n.id}</td>
                      <td class="text-sm" title={n.sender_id}>{user_display(n.sender)}</td>
                      <td class="text-sm" title={n.recipient_id}>{user_display(n.recipient)}</td>
                      <td class="text-sm max-w-xs truncate">{n.title}</td>
                      <td class="text-sm max-w-xs truncate">{n.content || "-"}</td>
                      <td class="text-xs font-mono max-w-xs truncate">
                        {Jason.encode!(n.metadata || %{})}
                      </td>
                      <td class="text-sm whitespace-nowrap">
                        <.timestamp at={n.inserted_at} />
                      </td>
                      <td class="text-sm">
                        <button
                          type="button"
                          phx-click="delete_notification"
                          phx-value-id={n.id}
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
                on_prev="admin_notifications_prev"
                on_next="admin_notifications_next"
                on_page_size="admin_notifications_page_size"
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
     |> reload_notifications()}
  end

  @impl true
  def handle_event("toggle_create", _params, socket) do
    {:noreply, assign(socket, :show_create, !socket.assigns.show_create)}
  end

  @impl true
  def handle_event("create_notification", %{"notification" => params}, socket) do
    sender_id = parse_id(params["sender_id"])
    recipient_id = parse_id(params["recipient_id"])

    if is_nil(sender_id) or is_nil(recipient_id) do
      {:noreply, put_flash(socket, :error, "Sender ID and Recipient ID are required")}
    else
      metadata =
        case params["metadata"] do
          nil ->
            %{}

          "" ->
            %{}

          s when is_binary(s) ->
            case Jason.decode(s) do
              {:ok, map} when is_map(map) -> map
              _ -> %{}
            end

          other ->
            other
        end

      attrs = %{
        "title" => params["title"],
        "content" => params["content"],
        "icon_url" => params["icon_url"],
        "metadata" => metadata
      }

      case Notifications.admin_create_notification(sender_id, recipient_id, attrs) do
        {:ok, _notification} ->
          {:noreply,
           socket
           |> put_flash(:info, "Notification created")
           |> assign(
             :create_form,
             to_form(
               %{
                 "sender_id" => "",
                 "recipient_id" => "",
                 "title" => "",
                 "content" => "",
                 "icon_url" => "",
                 "metadata" => ""
               },
               as: :notification
             )
           )
           |> reload_notifications()}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply,
           put_flash(socket, :error, "Validation failed: #{changeset_error_summary(changeset)}")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed: #{inspect(reason)}")}
      end
    end
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
     |> sync_selected_ids(notification_ids(socket.assigns.notifications))}
  end

  @impl true
  def handle_event("toggle_select_all", _params, socket) do
    notifications = socket.assigns.notifications
    ids = notification_ids(notifications)
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
        case Notifications.admin_delete_notification(id) do
          {:ok, _} -> {d + 1, f}
          {:error, _} -> {d, f + 1}
        end
      end)

    socket = assign(socket, :selected_ids, MapSet.new())

    socket =
      cond do
        failed == 0 ->
          put_flash(socket, :info, "Deleted #{deleted} notifications")

        deleted == 0 ->
          put_flash(socket, :error, "Failed to delete selected notifications")

        true ->
          put_flash(
            socket,
            :error,
            "Deleted #{deleted} notifications; failed #{failed}"
          )
      end

    {:noreply, reload_notifications(socket)}
  end

  @impl true
  def handle_event("delete_notification", %{"id" => id}, socket) do
    notification_id = to_string(id)

    case Notifications.admin_delete_notification(notification_id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Notification deleted")
         |> reload_notifications()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete notification")}
    end
  end

  @impl true
  def handle_event("admin_notifications_prev", _params, socket) do
    page = max(1, socket.assigns.page - 1)
    {:noreply, socket |> assign(:page, page) |> reload_notifications()}
  end

  @impl true
  def handle_event("admin_notifications_next", _params, socket) do
    page = socket.assigns.page + 1
    {:noreply, socket |> assign(:page, page) |> reload_notifications()}
  end

  @impl true
  def handle_event("admin_notifications_page_size", %{"size" => size}, socket) do
    {:noreply,
     socket
     |> assign(:page_size, String.to_integer(size))
     |> assign(:page, 1)
     |> reload_notifications()}
  end

  defp reload_notifications(socket) do
    page = socket.assigns.page
    page_size = socket.assigns.page_size
    filters = socket.assigns.filters

    notifications =
      Notifications.list_all_notifications(filters, page: page, page_size: page_size)

    total_count = Notifications.count_all_notifications(filters)

    total_pages =
      if page_size > 0,
        do: div(total_count + page_size - 1, page_size),
        else: 0

    socket
    |> assign(:notifications, notifications)
    |> assign(:count, total_count)
    |> assign(:total_pages, total_pages)
    |> assign(:page, page)
    |> sync_selected_ids(notification_ids(notifications))
  end

  defp notification_ids(notifications) when is_list(notifications) do
    Enum.map(notifications, & &1.id)
  end

  defp sync_selected_ids(socket, ids) when is_list(ids) do
    selected = socket.assigns.selected_ids
    allowed = MapSet.new(ids)
    assign(socket, :selected_ids, MapSet.intersection(selected, allowed))
  end

  defp parse_id(v), do: GameServer.UUIDv7.cast_or_nil(v)

  defp changeset_error_summary(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> Enum.map_join("; ", fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
  end
end
