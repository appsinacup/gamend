defmodule GamendWeb.AdminLive.KV do
  use GamendWeb, :live_view

  alias Gamend.KV
  alias GamendWeb.LiveHelpers

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-6">
        <.link navigate={~p"/admin"} class="btn btn-surface mb-4">
          ← Back to Admin
        </.link>

        <div class="card bg-base-200">
          <div class="card-body">
            <div class="flex flex-wrap items-center justify-between gap-4">
              <h2 class="card-title">KV Entries ({@count})</h2>
              <div class="flex flex-wrap items-center gap-2">
                <button
                  id="admin-kv-new-entry"
                  type="button"
                  phx-click="new_entry"
                  class="btn btn-sm btn-primary"
                >
                  + New Entry
                </button>
                <button
                  type="button"
                  phx-click="bulk_delete"
                  data-confirm={
                    ngettext(
                      "Delete %{count} selected KV entry?",
                      "Delete %{count} selected KV entries?",
                      MapSet.size(@selected_ids)
                    )
                  }
                  class="btn btn-sm btn-outline btn-error"
                  disabled={MapSet.size(@selected_ids) == 0}
                >
                  Delete selected ({MapSet.size(@selected_ids)})
                </button>
              </div>
            </div>

            <div class="mt-6">
              <h3 class="font-semibold text-sm mb-2">Filters</h3>

              <.form
                for={@filter_form}
                id="admin-kv-filters"
                phx-change="filters_change"
                class="space-y-3"
              >
                <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
                  <.input
                    field={@filter_form[:key]}
                    type="text"
                    label="Key contains"
                    phx-debounce="300"
                  />
                  <.input
                    field={@filter_form[:user_id]}
                    type="text"
                    label="User ID"
                  />
                  <.input
                    field={@filter_form[:lobby_id]}
                    type="text"
                    label="Lobby ID"
                  />
                  <.input
                    field={@filter_form[:global_only]}
                    type="checkbox"
                    label="Global only"
                  />
                </div>

                <div class="flex gap-2">
                  <button type="button" phx-click="filters_clear" class="btn btn-sm btn-ghost">
                    Clear
                  </button>
                </div>
              </.form>
            </div>

            <div class="overflow-x-auto mt-4">
              <table id="admin-kv-table" class="table table-zebra w-full table-fixed min-w-[56rem]">
                <colgroup>
                  <col class="w-10" />
                  <col class="w-16" />
                  <col class="w-[35%]" />
                  <col class="w-20" />
                  <col class="w-20" />
                  <col class="w-40" />
                  <col class="w-[20%]" />
                  <col class="w-[20%]" />
                  <col class="w-32" />
                </colgroup>
                <thead>
                  <tr>
                    <th class="w-10">
                      <input
                        type="checkbox"
                        class="checkbox checkbox-sm"
                        phx-click="toggle_select_all"
                        checked={@entries != [] && MapSet.size(@selected_ids) == length(@entries)}
                      />
                    </th>
                    <th class="w-16">ID</th>
                    <th class="font-mono text-sm break-all">Key</th>
                    <th class="w-20">User</th>
                    <th class="w-20">Lobby</th>
                    <th class="w-40">Updated</th>
                    <th>Value</th>
                    <th>Metadata</th>
                    <th class="w-32">Actions</th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    :for={e <- @entries}
                    id={"admin-kv-" <> to_string(e.id)}
                    class={clickable_row()}
                    phx-click="edit_entry"
                    phx-value-id={e.id}
                  >
                    <td class="w-10">
                      <input
                        type="checkbox"
                        class="checkbox checkbox-sm"
                        phx-click="toggle_select"
                        phx-value-id={e.id}
                        checked={MapSet.member?(@selected_ids, e.id)}
                      />
                    </td>
                    <td class="font-mono text-sm w-16">{e.id}</td>
                    <td class="font-mono text-sm break-all">
                      <button
                        type="button"
                        phx-click="edit_entry"
                        phx-value-id={e.id}
                        class="link link-hover text-left"
                      >
                        {e.key}
                      </button>
                    </td>
                    <td class="font-mono text-sm w-20">{e.user_id || ""}</td>
                    <td class="font-mono text-sm w-20">{e.lobby_id || ""}</td>
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
                    <td class="text-sm whitespace-nowrap w-32">
                      <button
                        type="button"
                        phx-click="delete_entry"
                        phx-value-id={e.id}
                        data-confirm="Delete this KV entry?"
                        class="btn btn-xs btn-outline btn-error"
                      >
                        Delete
                      </button>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>

            <div class="mt-4">
              <.pagination
                page={@page}
                total_pages={@total_pages}
                total_count={@count}
                page_size={@page_size}
                on_prev="kv_prev"
                on_next="kv_next"
                on_page_size="kv_page_size"
              />
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>

    <%= if @show_form_modal do %>
      <div class="modal modal-open">
        <div class="modal-box max-w-4xl">
          <h3 class="font-bold text-lg">
            {if(@editing?, do: "Edit KV entry", else: "New KV entry")}
          </h3>

          <.form for={@form} id="admin-kv-form" phx-submit="save_entry" class="space-y-3 mt-4">
            <input
              type="hidden"
              id={@form[:id].id}
              name={@form[:id].name}
              value={@form[:id].value}
            />

            <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
              <.input field={@form[:key]} type="text" label="Key" required />
              <.input
                field={@form[:user_id]}
                type="text"
                label="User ID (optional)"
              />
              <.input
                field={@form[:lobby_id]}
                type="text"
                label="Lobby ID (optional)"
              />
            </div>

            <div class="grid grid-cols-1 lg:grid-cols-2 gap-3">
              <.input
                field={@form[:value_json]}
                type="textarea"
                label="Value (JSON object)"
                class="w-full textarea font-mono text-xs min-h-32"
                required
              />
              <.input
                field={@form[:metadata_json]}
                type="textarea"
                label="Metadata (JSON object)"
                class="w-full textarea font-mono text-xs min-h-32"
                required
              />
            </div>

            <div class="modal-action">
              <button type="button" phx-click="close_entry_modal" class="btn">
                Cancel
              </button>
              <button id="admin-kv-save" type="submit" class="btn btn-primary">
                {if(@editing?, do: "Save changes", else: "Create")}
              </button>
            </div>
          </.form>
        </div>
      </div>
    <% end %>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    page = 1
    page_size = 50

    {:ok,
     socket
     |> assign(:page, page)
     |> assign(:page_size, page_size)
     |> assign(:filter_key, nil)
     |> assign(:filter_user_id, nil)
     |> assign(:filter_lobby_id, nil)
     |> assign(:filter_global_only, false)
     |> assign(
       :filter_form,
       to_form(%{"key" => "", "user_id" => "", "lobby_id" => "", "global_only" => "false"},
         as: :filters
       )
     )
     |> assign(:selected_ids, MapSet.new())
     |> assign(:show_form_modal, false)
     |> assign_form_new()
     |> reload_entries()}
  end

  # Deep-link from the user admin page: `?user_id=` pre-filters entries to one user.
  @impl true
  def handle_params(%{"user_id" => user_id}, _uri, socket) when is_binary(user_id) do
    trimmed = String.trim(user_id)

    if trimmed == "" do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> assign(:filter_user_id, trimmed)
       |> assign(:page, 1)
       |> assign(
         :filter_form,
         to_form(
           %{"key" => "", "user_id" => trimmed, "lobby_id" => "", "global_only" => "false"},
           as: :filters
         )
       )
       |> reload_entries()}
    end
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("kv_prev", _params, socket),
    do: {:noreply, socket |> LiveHelpers.prev_page() |> reload_entries()}

  @impl true
  def handle_event("kv_next", _params, socket),
    do: {:noreply, socket |> LiveHelpers.next_page() |> reload_entries()}

  @impl true
  def handle_event("kv_page_size", %{"size" => size}, socket),
    do: {:noreply, socket |> LiveHelpers.put_page_size(size) |> reload_entries()}

  @impl true
  def handle_event("toggle_select", %{"id" => id}, socket) do
    id = parse_id(id)
    selected = socket.assigns[:selected_ids] || MapSet.new()

    selected =
      if id && MapSet.member?(selected, id) do
        MapSet.delete(selected, id)
      else
        if id, do: MapSet.put(selected, id), else: selected
      end

    {:noreply,
     socket
     |> assign(:selected_ids, selected)
     |> sync_selected_ids(entry_ids(socket.assigns.entries))}
  end

  @impl true
  def handle_event("toggle_select_all", _params, socket) do
    entries = socket.assigns.entries || []
    ids = entry_ids(entries)

    selected = socket.assigns[:selected_ids] || MapSet.new()

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
    ids = socket.assigns[:selected_ids] || MapSet.new()
    ids = MapSet.to_list(ids)

    {deleted, failed} =
      Enum.reduce(ids, {0, 0}, fn id, {d, f} ->
        try do
          :ok = KV.delete_entry(id)
          {d + 1, f}
        rescue
          _ -> {d, f + 1}
        end
      end)

    socket = assign(socket, :selected_ids, MapSet.new())

    socket =
      cond do
        failed == 0 ->
          put_flash(
            socket,
            :info,
            ngettext("Deleted %{count} entry", "Deleted %{count} entries", deleted)
          )

        deleted == 0 ->
          put_flash(socket, :error, "Failed to delete selected entries")

        true ->
          put_flash(
            socket,
            :error,
            ngettext(
              "Deleted %{count} entry; %{failed} failed",
              "Deleted %{count} entries; %{failed} failed",
              deleted,
              failed: failed
            )
          )
      end

    {:noreply, socket |> reload_entries()}
  end

  @impl true
  def handle_event("filters_change", %{"filters" => params}, socket) when is_map(params) do
    socket = assign(socket, :filter_form, to_form(params, as: :filters))

    case filters_from_params(params) do
      {:ok,
       %{
         filter_key: filter_key,
         filter_user_id: filter_user_id,
         filter_lobby_id: filter_lobby_id,
         filter_global_only: filter_global_only
       }} ->
        {:noreply,
         socket
         |> assign(:filter_key, filter_key)
         |> assign(:filter_user_id, filter_user_id)
         |> assign(:filter_lobby_id, filter_lobby_id)
         |> assign(:filter_global_only, filter_global_only)
         |> assign(:page, 1)
         |> reload_entries()}

      {:error, _msg} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("filters_clear", _params, socket) do
    {:noreply,
     socket
     |> assign(:filter_key, nil)
     |> assign(:filter_user_id, nil)
     |> assign(:filter_lobby_id, nil)
     |> assign(:filter_global_only, false)
     |> assign(
       :filter_form,
       to_form(%{"key" => "", "user_id" => "", "lobby_id" => "", "global_only" => "false"},
         as: :filters
       )
     )
     |> assign(:page, 1)
     |> reload_entries()}
  end

  @impl true
  def handle_event("new_entry", _params, socket) do
    {:noreply,
     socket
     |> assign_form_new()
     |> assign(:show_form_modal, true)}
  end

  @impl true
  def handle_event("edit_entry", %{"id" => id}, socket) do
    id = parse_id(id)

    case id && KV.get_entry(id) do
      nil ->
        {:noreply, socket |> put_flash(:error, "Entry not found")}

      entry ->
        {:noreply,
         socket
         |> assign_form_edit(entry)
         |> assign(:show_form_modal, true)}
    end
  end

  @impl true
  def handle_event("close_entry_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_form_modal, false)
     |> assign_form_new()}
  end

  @impl true
  def handle_event("delete_entry", %{"id" => id}, socket) do
    id = parse_id(id)

    if id do
      :ok = KV.delete_entry(id)
    end

    {:noreply, socket |> put_flash(:info, "Entry deleted") |> reload_entries()}
  end

  @impl true
  def handle_event("save_entry", %{"kv" => params}, socket) do
    attrs_result = attrs_from_form_params(params)

    case attrs_result do
      {:error, msg} ->
        {:noreply, socket |> put_flash(:error, msg)}

      {:ok, %{id: nil, attrs: attrs}} ->
        case KV.create_entry(attrs) do
          {:ok, _entry} ->
            {:noreply,
             socket
             |> put_flash(:info, "Entry created")
             |> assign_form_new()
             |> assign(:show_form_modal, false)
             |> reload_entries()}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply,
             socket
             |> put_flash(
               :error,
               "Create failed: #{changeset_error_summary(changeset)}"
             )}
        end

      {:ok, %{id: id, attrs: attrs}} ->
        case KV.update_entry(id, attrs) do
          {:ok, _entry} ->
            {:noreply,
             socket
             |> put_flash(:info, "Entry updated")
             |> assign_form_new()
             |> assign(:show_form_modal, false)
             |> reload_entries()}

          {:error, :not_found} ->
            {:noreply, socket |> put_flash(:error, "Entry not found")}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply,
             socket
             |> put_flash(
               :error,
               "Update failed: #{changeset_error_summary(changeset)}"
             )}
        end
    end
  end

  defp reload_entries(socket) do
    page = socket.assigns.page
    page_size = socket.assigns.page_size

    key = socket.assigns.filter_key
    user_id = socket.assigns.filter_user_id
    lobby_id = socket.assigns.filter_lobby_id
    global_only = socket.assigns.filter_global_only

    entries =
      KV.list_entries(
        page: page,
        page_size: page_size,
        key: key,
        user_id: user_id,
        lobby_id: lobby_id,
        global_only: global_only
      )

    count =
      KV.count_entries(key: key, user_id: user_id, lobby_id: lobby_id, global_only: global_only)

    total_pages = LiveHelpers.total_pages(count, page_size)

    socket
    |> assign(:entries, entries)
    |> assign(:count, count)
    |> assign(:total_pages, total_pages)
    |> clamp_page()
    |> sync_selected_ids(entry_ids(entries))
  end

  defp clamp_page(socket) do
    page = socket.assigns.page
    total_pages = socket.assigns.total_pages

    page =
      cond do
        total_pages == 0 -> 1
        page < 1 -> 1
        page > total_pages -> total_pages
        true -> page
      end

    assign(socket, :page, page)
  end

  defp json_preview(nil), do: ""

  defp json_preview(map) when is_map(map) do
    Jason.encode!(map)
    |> String.slice(0, 2048)
  end

  defp json_preview(_), do: ""

  defp assign_form_new(socket) do
    params = %{
      "id" => "",
      "key" => "",
      "user_id" => "",
      "lobby_id" => "",
      "value_json" => "{}",
      "metadata_json" => "{}"
    }

    socket
    |> assign(:editing?, false)
    |> assign(:form, to_form(params, as: :kv))
  end

  defp assign_form_edit(socket, entry) do
    params = %{
      "id" => to_string(entry.id),
      "key" => entry.key,
      "user_id" => if(entry.user_id, do: to_string(entry.user_id), else: ""),
      "lobby_id" => if(entry.lobby_id, do: to_string(entry.lobby_id), else: ""),
      "value_json" => pretty_json(entry.value),
      "metadata_json" => pretty_json(entry.metadata)
    }

    socket
    |> assign(:editing?, true)
    |> assign(:form, to_form(params, as: :kv))
  end

  defp pretty_json(nil), do: "{}"

  defp pretty_json(%{} = map) when map_size(map) == 0, do: "{}"

  defp pretty_json(map) when is_map(map) do
    case Jason.encode(map, pretty: true) do
      {:ok, json} -> json
      _ -> "{}"
    end
  end

  defp pretty_json(_), do: "{}"

  defp entry_ids(entries) when is_list(entries), do: Enum.map(entries, & &1.id)

  defp sync_selected_ids(socket, ids) when is_list(ids) do
    selected = socket.assigns[:selected_ids] || MapSet.new()
    allowed = MapSet.new(ids)
    assign(socket, :selected_ids, MapSet.intersection(selected, allowed))
  end

  defp attrs_from_form_params(params) when is_map(params) do
    id = parse_id(Map.get(params, "id"))
    key = (Map.get(params, "key") || "") |> String.trim()

    with true <- key != "" || {:error, "Key is required"},
         {:ok, user_id} <- parse_optional_id(Map.get(params, "user_id"), "User ID"),
         {:ok, lobby_id} <- parse_optional_id(Map.get(params, "lobby_id"), "Lobby ID"),
         {:ok, value} <- decode_json_object(Map.get(params, "value_json"), "Value"),
         {:ok, metadata} <- decode_json_object(Map.get(params, "metadata_json"), "Metadata") do
      attrs = %{key: key, user_id: user_id, lobby_id: lobby_id, value: value, metadata: metadata}
      {:ok, %{id: id, attrs: attrs}}
    else
      {:error, msg} -> {:error, msg}
    end
  end

  defp decode_json_object(nil, label), do: {:error, "#{label} must be a JSON object"}

  defp decode_json_object(raw, label) when is_binary(raw) do
    case Jason.decode(raw) do
      {:ok, map} when is_map(map) ->
        {:ok, map}

      {:ok, _other} ->
        {:error, "#{label} must be a JSON object"}

      {:error, _} ->
        {:error, "#{label} is not valid JSON"}
    end
  end

  # `label` names the field: the error used to read "ID must be a valid UUID"
  # with two ID fields on the form.
  defp parse_optional_id(nil, _label), do: {:ok, nil}

  defp parse_optional_id(raw, label) when is_binary(raw) do
    raw = String.trim(raw)

    if raw == "" do
      {:ok, nil}
    else
      case Ecto.UUID.cast(raw) do
        {:ok, uuid} -> {:ok, uuid}
        :error -> {:error, "#{label} must be a valid UUID"}
      end
    end
  end

  defp parse_id(nil), do: nil

  defp parse_id(raw) when is_binary(raw) do
    Gamend.UUIDv7.cast_or_nil(String.trim(raw))
  end

  defp changeset_error_summary(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, val}, acc ->
        String.replace(acc, "%{#{key}}", to_string(val))
      end)
    end)
    |> Enum.map_join("; ", fn {field, msgs} -> "#{field} #{Enum.join(msgs, ", ")}" end)
  end

  defp filters_from_params(params) when is_map(params) do
    key = (Map.get(params, "key") || "") |> String.trim()
    key = if key == "", do: nil, else: key

    global_only = parse_bool(Map.get(params, "global_only"))

    with {:ok, user_id} <- parse_optional_id(Map.get(params, "user_id"), "User ID"),
         {:ok, lobby_id} <- parse_optional_id(Map.get(params, "lobby_id"), "Lobby ID") do
      user_id = if(global_only, do: nil, else: user_id)
      lobby_id = if(global_only, do: nil, else: lobby_id)

      {:ok,
       %{
         filter_key: key,
         filter_user_id: user_id,
         filter_lobby_id: lobby_id,
         filter_global_only: global_only
       }}
    else
      {:error, msg} ->
        {:error, msg}
    end
  end

  defp parse_bool(true), do: true
  defp parse_bool("true"), do: true
  defp parse_bool("on"), do: true
  defp parse_bool(_), do: false
end
