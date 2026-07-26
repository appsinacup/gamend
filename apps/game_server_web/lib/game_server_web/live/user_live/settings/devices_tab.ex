defmodule GameServerWeb.UserLive.Settings.DevicesTab do
  @moduledoc """
  Devices tab of the user settings page: the devices registered for push
  notifications, with removal. View + remove only — a token row has nothing
  meaningfully editable (token/platform/provider are facts about the device).
  """

  use GameServerWeb, :html
  import Phoenix.LiveView, only: [put_flash: 3]

  alias GameServer.Push

  @page_size 25

  def assign_defaults(socket) do
    socket
    |> assign(:devices_page, 1)
    |> assign(:devices_count, 0)
    |> assign(:devices_total_pages, 0)
    |> reload_devices()
  end

  def tab(assigns) do
    ~H"""
    <div :if={@settings_tab == "devices"}>
      <div class="card bg-base-200 p-4 rounded-lg mt-6">
        <div class="flex items-center justify-between">
          <div>
            <div class="font-semibold text-lg">{gettext("Devices")}</div>
            <div class="text-sm text-base-content/70">
              {gettext("Devices registered for push notifications.")}
            </div>
          </div>
        </div>

        <div :if={@devices == []} class="mt-4 text-sm text-base-content/60">
          {gettext("No devices registered.")}
        </div>

        <div :if={@devices != []} class="overflow-x-auto mt-4">
          <table id="user-devices-table" class="table table-zebra w-full min-w-[36rem]">
            <thead>
              <tr>
                <th>{gettext("Platform")}</th>
                <th>{gettext("Provider")}</th>
                <th>{gettext("Registered")}</th>
                <th>{gettext("Last used")}</th>
                <th>{gettext("Status")}</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={device <- @devices} id={"user-device-" <> device.id}>
                <td class="text-sm">{device.platform}</td>
                <td class="text-sm">{device.provider}</td>
                <td class="text-sm whitespace-nowrap">
                  <.timestamp at={device.inserted_at} />
                </td>
                <td class="text-sm whitespace-nowrap">
                  <.timestamp at={device.last_used_at} />
                </td>
                <td class="text-sm">
                  <span :if={is_nil(device.disabled_at)} class="badge badge-success badge-sm">
                    {gettext("Active")}
                  </span>
                  <span :if={device.disabled_at} class="badge badge-ghost badge-sm">
                    {gettext("Inactive")}
                  </span>
                </td>
                <td class="text-right">
                  <button
                    type="button"
                    phx-click="device_remove"
                    phx-value-id={device.id}
                    data-confirm={gettext("Delete?")}
                    class="btn btn-xs btn-outline btn-error"
                  >
                    {gettext("Remove")}
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div :if={@devices_total_pages > 1} class="mt-4">
          <.pagination
            page={@devices_page}
            total_pages={@devices_total_pages}
            total_count={@devices_count}
            on_prev="devices_prev"
            on_next="devices_next"
          />
        </div>
      </div>
    </div>
    """
  end

  def handle_event("devices_prev", _params, socket) do
    page = max(1, (socket.assigns.devices_page || 1) - 1)
    {:noreply, socket |> assign(:devices_page, page) |> reload_devices()}
  end

  def handle_event("devices_next", _params, socket) do
    page = (socket.assigns.devices_page || 1) + 1
    {:noreply, socket |> assign(:devices_page, page) |> reload_devices()}
  end

  def handle_event("device_remove", %{"id" => id}, socket) do
    user = socket.assigns.user

    case Push.delete_token(user.id, to_string(id)) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Success."))
         |> reload_devices()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Failed"))}
    end
  end

  @doc "Reloads the device list for the current page."
  def reload_devices(socket) do
    page = socket.assigns[:devices_page] || 1
    user = socket.assigns.user

    devices = Push.list_tokens(user.id, page: page, page_size: @page_size)
    count = Push.count_tokens(user.id)
    total_pages = div(count + @page_size - 1, @page_size)

    socket
    |> assign(:devices, devices)
    |> assign(:devices_count, count)
    |> assign(:devices_total_pages, total_pages)
  end
end
