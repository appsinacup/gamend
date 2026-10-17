defmodule GamendWeb.UserLive.Settings.DataTab do
  @moduledoc """
  Data tab of the user settings page: the user's key-value entries with
  pagination and key filtering.
  """

  use GamendWeb, :html
  import Phoenix.LiveView, only: [stream: 4]

  alias Gamend.KV
  alias GamendWeb.LiveHelpers

  @page_size 50

  def assign_defaults(socket) do
    socket
    |> assign(:kv_page, 1)
    |> assign(:kv_page_size, @page_size)
    |> assign(:kv_key_filter, nil)
    |> assign(:kv_filter_form, to_form(%{"key" => ""}, as: :filters))
    |> assign(:kv_count, 0)
    |> assign(:kv_total_pages, 0)
  end

  def tab(assigns) do
    ~H"""
    <div :if={@settings_tab == "data"}>
      <div class="card bg-base-200 p-4 rounded-lg mt-6">
        <div class="flex items-center justify-between">
          <div>
            <div class="font-semibold text-lg">{gettext("Data")}</div>
          </div>
        </div>

        <div class="mt-4">
          <.form
            for={@kv_filter_form}
            id="kv-filters"
            phx-change="kv_filters_change"
            phx-submit="kv_filters_apply"
          >
            <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
              <.input
                field={@kv_filter_form[:key]}
                type="text"
                label={gettext("Search...")}
                phx-debounce="300"
              />
            </div>
            <div class="flex gap-2 mt-2">
              <button type="submit" class="btn btn-surface btn-sm">{gettext("Apply")}</button>
              <button type="button" phx-click="kv_filters_clear" class="btn btn-sm btn-ghost">
                {gettext("Clear")}
              </button>
            </div>
          </.form>
        </div>

        <div class="overflow-x-auto mt-4">
          <table id="user-kv-table" class="table table-zebra w-full table-fixed min-w-[40rem]">
            <colgroup>
              <col class="w-16" />
              <col class="w-[40%]" />
              <col class="w-40" />
              <col class="w-[20%]" />
              <col class="w-[20%]" />
            </colgroup>
            <thead>
              <tr>
                <th class="w-16">{gettext("ID")}</th>
                <th class="font-mono text-sm break-all">{gettext("Name")}</th>
                <th class="w-40">{gettext("Date")}</th>
                <th>{gettext("Content")}</th>
                <th>{gettext("Metadata")}</th>
              </tr>
            </thead>
            <tbody id="user-kv-rows" phx-update="stream">
              <tr :for={{dom_id, e} <- @streams.kv_entries} id={dom_id}>
                <td class="font-mono text-sm w-16">{e.id}</td>
                <td class="font-mono text-sm break-all">{e.key}</td>
                <td class="text-sm w-40">
                  <span class="font-mono text-xs">
                    {if e.updated_at, do: DateTime.to_iso8601(e.updated_at), else: "-"}
                  </span>
                </td>
                <td class="text-sm">
                  <pre class="text-xs font-mono whitespace-pre-wrap max-h-24 overflow-auto bg-base-100/60 rounded p-2">{json_preview(e.value)}</pre>
                </td>
                <td class="text-sm">
                  <pre class="text-xs font-mono whitespace-pre-wrap max-h-24 overflow-auto bg-base-100/60 rounded p-2">{json_preview(e.metadata)}</pre>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div class="mt-4">
          <.pagination
            page={@kv_page}
            total_pages={@kv_total_pages}
            total_count={@kv_count}
            on_prev="kv_prev"
            on_next="kv_next"
          />
        </div>
      </div>
    </div>

    <%!-- Groups tab --%>
    """
  end

  def handle_event("kv_prev", _params, socket) do
    page = max(1, (socket.assigns.kv_page || 1) - 1)
    {:noreply, socket |> assign(:kv_page, page) |> reload_kv_entries()}
  end

  def handle_event("kv_next", _params, socket) do
    page = (socket.assigns.kv_page || 1) + 1
    {:noreply, socket |> assign(:kv_page, page) |> reload_kv_entries()}
  end

  def handle_event(event, %{"filters" => params}, socket)
      when event in ["kv_filters_change", "kv_filters_apply"] do
    socket = assign(socket, :kv_filter_form, to_form(params, as: :filters))
    key = (Map.get(params, "key") || "") |> String.trim()
    key = if key == "", do: nil, else: String.downcase(key)

    {:noreply,
     socket |> assign(:kv_key_filter, key) |> assign(:kv_page, 1) |> reload_kv_entries()}
  end

  def handle_event("kv_filters_clear", _params, socket) do
    {:noreply,
     socket
     |> assign(:kv_key_filter, nil)
     |> assign(:kv_filter_form, to_form(%{"key" => ""}, as: :filters))
     |> assign(:kv_page, 1)
     |> reload_kv_entries()}
  end

  @doc "Reloads the KV entry list for the current page and filter."
  def reload_kv_entries(socket) do
    page = socket.assigns[:kv_page] || 1
    page_size = socket.assigns[:kv_page_size] || @page_size
    key = socket.assigns[:kv_key_filter]
    user = socket.assigns.user

    entries = KV.list_entries(page: page, page_size: page_size, key: key, user_id: user.id)
    count = KV.count_entries(key: key, user_id: user.id)
    total_pages = LiveHelpers.total_pages(count, page_size)

    socket
    |> stream(:kv_entries, entries, reset: true, dom_id: &"user-kv-#{&1.id}")
    |> assign(:kv_count, count)
    |> assign(:kv_total_pages, total_pages)
    |> clamp_kv_page()
  end

  defp clamp_kv_page(socket) do
    page = socket.assigns.kv_page
    total_pages = socket.assigns.kv_total_pages

    page =
      cond do
        total_pages == 0 -> 1
        page < 1 -> 1
        page > total_pages -> total_pages
        true -> page
      end

    assign(socket, :kv_page, page)
  end

  defp json_preview(nil), do: ""

  defp json_preview(map) when is_map(map) do
    Jason.encode!(map)
    |> String.slice(0, 2048)
  end

  defp json_preview(_), do: ""
end
