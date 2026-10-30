defmodule GamendWeb.AdminLive.Notifications do
  use GamendWeb, :live_view

  alias Gamend.Notifications
  alias GamendWeb.LiveHelpers
  alias GamendWeb.UserLive.Settings.NotificationsTab

  @impl true
  def mount(_params, _session, socket) do
    user = Gamend.Accounts.Scope.user(socket.assigns.current_scope)

    socket =
      socket
      # The admins' notification groups ("Reports to review"): the admin's
      # own choices, kept off their account settings (`NotificationsTab`).
      |> assign(:user, user)
      |> assign(:admin_notify_groups, NotificationsTab.admin_groups(user))
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
        <.link navigate={~p"/admin"} class="btn btn-surface mb-4">← Back to Admin</.link>

        <div :if={@admin_notify_groups != []} id="admin-notify-settings" class="card bg-base-200">
          <div class="card-body space-y-2">
            <div>
              <h2 class="card-title">Your admin notifications</h2>
              <p class="text-sm text-muted">
                What you are told about the queues admins work through, and where.
              </p>
            </div>
            <NotificationsTab.group_rows user={@user} groups={@admin_notify_groups} />
          </div>
        </div>

        <%!-- Create notification form --%>
        <div class="card bg-base-200">
          <div class="card-body">
            <div class="flex flex-wrap items-center justify-between">
              <h2 class="card-title">Create Notification</h2>
              <button
                type="button"
                phx-click="toggle_create"
                class="btn btn-surface btn-sm"
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
                data-confirm={
                  ngettext(
                    "Delete %{count} selected notification?",
                    "Delete %{count} selected notifications?",
                    MapSet.size(@selected_ids)
                  )
                }
                class="btn btn-sm btn-outline btn-error"
                disabled={MapSet.size(@selected_ids) == 0}
              >
                Delete selected ({MapSet.size(@selected_ids)})
              </button>
            </div>

            <form phx-change="filter" phx-no-unused-field id="notifications-filter-form">
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
                      <th>Sender</th>
                      <th>Recipient</th>
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
  def handle_event("notify_toggle", params, socket),
    do: NotificationsTab.handle_event("notify_toggle", params, socket)

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

    # Text that is not a JSON object is refused rather than sent as %{}.
    metadata = decode_metadata(params["metadata"])

    cond do
      is_nil(sender_id) or is_nil(recipient_id) ->
        {:noreply, put_flash(socket, :error, "Sender ID and Recipient ID are required")}

      metadata == :error ->
        {:noreply, put_flash(socket, :error, "Metadata must be a JSON object")}

      true ->
        create_notification(socket, sender_id, recipient_id, params, metadata)
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
          put_flash(
            socket,
            :info,
            ngettext("Deleted %{count} notification", "Deleted %{count} notifications", deleted)
          )

        deleted == 0 ->
          put_flash(socket, :error, "Failed to delete selected notifications")

        true ->
          put_flash(
            socket,
            :error,
            ngettext(
              "Deleted %{count} notification; %{failed} failed",
              "Deleted %{count} notifications; %{failed} failed",
              deleted,
              failed: failed
            )
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
  def handle_event("admin_notifications_prev", _params, socket),
    do: {:noreply, socket |> LiveHelpers.prev_page() |> reload_notifications()}

  @impl true
  def handle_event("admin_notifications_next", _params, socket),
    do: {:noreply, socket |> LiveHelpers.next_page() |> reload_notifications()}

  @impl true
  def handle_event("admin_notifications_page_size", %{"size" => size}, socket),
    do: {:noreply, socket |> LiveHelpers.put_page_size(size) |> reload_notifications()}

  defp reload_notifications(socket) do
    page = socket.assigns.page
    page_size = socket.assigns.page_size
    filters = socket.assigns.filters

    notifications =
      Notifications.list_all_notifications(filters, page: page, page_size: page_size)

    total_count = Notifications.count_all_notifications(filters)

    total_pages =
      LiveHelpers.total_pages(total_count, page_size)

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

  defp parse_id(v), do: Gamend.UUIDv7.cast_or_nil(v)

  defp changeset_error_summary(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> Enum.map_join("; ", fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
  end

  defp decode_metadata(nil), do: %{}

  defp decode_metadata(json) when is_binary(json) do
    case String.trim(json) do
      "" ->
        %{}

      trimmed ->
        case Jason.decode(trimmed) do
          {:ok, map} when is_map(map) -> map
          _ -> :error
        end
    end
  end

  defp decode_metadata(other), do: other

  defp create_notification(socket, sender_id, recipient_id, params, metadata) do
    attrs = %{
      "title" => params["title"],
      "content" => params["content"],
      "icon_url" => params["icon_url"],
      "metadata" => metadata
    }

    case Notifications.admin_create_notification(sender_id, recipient_id, attrs) do
      {:ok, notification} ->
        {:noreply,
         socket
         |> put_flash(:info, created_message(notification))
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

  # `admin_create_notification/3` upserts on (sender, recipient, title): a
  # second send replaces the first's content, and only `updated_at` moves.
  defp created_message(%{inserted_at: at, updated_at: at}), do: "Notification created"

  defp created_message(_notification),
    do: "Notification updated: one with the same sender, recipient and title already existed"
end
