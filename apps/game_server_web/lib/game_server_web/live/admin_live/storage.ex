defmodule GameServerWeb.AdminLive.Storage do
  @moduledoc """
  Admin view over object storage: usage summary, a paginated object list with
  preview and delete, and a direct upload. Backend-agnostic — works the same
  whether storage is local disk or S3/R2.
  """
  use GameServerWeb, :live_view

  alias GameServer.Storage

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Admin · Storage")
      |> assign(:page, 1)
      |> assign(:page_size, 25)
      |> assign(:prefix, "")
      |> assign(:upload_path, "")
      |> assign(:adapter, adapter_label())
      # Admin has full control: any file type, at any path, up to the configured
      # upload limit (LIMIT_MAX_UPLOAD_BYTES).
      |> allow_upload(:object,
        accept: :any,
        max_entries: 1,
        max_file_size: GameServer.Limits.get(:max_upload_bytes)
      )
      |> reload()

    {:ok, socket}
  end

  @impl true
  def handle_event("filter", params, socket) do
    {:noreply,
     socket
     |> assign(:prefix, String.trim(Map.get(params, "prefix", "")))
     |> assign(:page, 1)
     |> reload()}
  end

  def handle_event("prev_page", _params, socket) do
    {:noreply, socket |> assign(:page, max(socket.assigns.page - 1, 1)) |> reload_objects()}
  end

  def handle_event("next_page", _params, socket) do
    page = min(socket.assigns.page + 1, max(socket.assigns.total_pages, 1))
    {:noreply, socket |> assign(:page, page) |> reload_objects()}
  end

  def handle_event("page_size", %{"size" => size}, socket) do
    {:noreply,
     socket
     |> assign(:page_size, String.to_integer(size))
     |> assign(:page, 1)
     |> reload()}
  end

  def handle_event("refresh", _params, socket), do: {:noreply, reload(socket)}

  def handle_event("cancel_upload_entry", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :object, ref)}
  end

  def handle_event("validate_upload", params, socket) do
    {:noreply, assign(socket, :upload_path, Map.get(params, "path", socket.assigns.upload_path))}
  end

  def handle_event("delete", %{"key" => key}, socket) do
    socket =
      case Storage.delete(key) do
        :ok -> put_flash(socket, :info, "Object deleted")
        {:error, _} -> put_flash(socket, :error, "Delete failed")
      end

    {:noreply, reload(socket)}
  end

  def handle_event("upload", params, socket) do
    path = String.trim(Map.get(params, "path", ""))

    keys =
      consume_uploaded_entries(socket, :object, fn %{path: tmp}, entry ->
        key = target_key(path, entry.client_name)

        case Storage.put(key, File.read!(tmp), content_type: entry.client_type) do
          {:ok, ^key} -> {:ok, key}
          _ -> {:postpone, :error}
        end
      end)

    socket =
      if keys == [],
        do: put_flash(socket, :error, "No file uploaded"),
        else: put_flash(socket, :info, "Uploaded to #{Enum.join(keys, ", ")}")

    {:noreply, socket |> assign(:upload_path, "") |> reload()}
  end

  # Blank path → auto-generate under uploads/admin/. A trailing slash means
  # "this folder" (append the file name); otherwise the path is the full key.
  defp target_key("", filename), do: Storage.build_key("uploads", "admin", filename)

  defp target_key(path, filename) do
    path = String.trim_leading(path, "/")
    if String.ends_with?(path, "/"), do: path <> filename, else: path
  end

  # ── data ──────────────────────────────────────────────────────────────────

  defp reload(socket), do: socket |> reload_usage() |> reload_objects()

  defp reload_usage(socket) do
    usage = Storage.usage(prefix: presence(socket.assigns.prefix))

    socket
    |> assign(:count, usage.count)
    |> assign(:bytes, usage.bytes)
    |> assign(:total_pages, ceil_div(usage.count, socket.assigns.page_size))
  end

  defp reload_objects(socket) do
    offset = (socket.assigns.page - 1) * socket.assigns.page_size

    objects =
      Storage.list_objects(
        prefix: presence(socket.assigns.prefix),
        offset: offset,
        limit: socket.assigns.page_size
      )

    assign(socket, :objects, objects)
  end

  defp presence(""), do: nil
  defp presence(value), do: value

  defp ceil_div(_num, 0), do: 0
  defp ceil_div(num, den), do: div(num + den - 1, den)

  defp adapter_label do
    case Storage.adapter() do
      GameServer.Storage.S3 -> "S3"
      _ -> "Local disk"
    end
  end

  defp format_bytes(bytes) when bytes >= 1_073_741_824,
    do: "#{Float.round(bytes / 1_073_741_824, 1)} GB"

  defp format_bytes(bytes) when bytes >= 1_048_576, do: "#{Float.round(bytes / 1_048_576, 1)} MB"
  defp format_bytes(bytes) when bytes >= 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{bytes} B"

  defp image?(key),
    do: (key |> Path.extname() |> String.downcase()) in ~w(.png .jpg .jpeg .webp .gif)

  defp upload_error(:too_large), do: "file too large"
  defp upload_error(:too_many_files), do: "too many files"
  defp upload_error(:not_accepted), do: "file type not accepted"
  defp upload_error(err), do: to_string(err)

  # ── render ────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <.link navigate={~p"/admin"} class="btn btn-outline mb-4">← Back to Admin</.link>

      <div class="card bg-base-200 mb-4">
        <div class="card-body">
          <div class="flex flex-wrap items-center justify-between gap-2">
            <h2 class="card-title">Storage</h2>
            <button phx-click="refresh" class="btn btn-ghost btn-sm">Refresh</button>
          </div>
          <div class="flex flex-wrap gap-6 text-sm">
            <div><span class="text-base-content/60">Backend:</span> <b>{@adapter}</b></div>
            <div><span class="text-base-content/60">Objects:</span> <b>{@count}</b></div>
            <div>
              <span class="text-base-content/60">Total size:</span> <b>{format_bytes(@bytes)}</b>
            </div>
          </div>

          <form
            id="storage-upload-form"
            phx-change="validate_upload"
            phx-submit="upload"
            class="flex flex-wrap items-center gap-2 mt-3"
          >
            <input
              type="text"
              name="path"
              value={@upload_path}
              placeholder="Upload path (blank = uploads/admin/; trailing / = folder)"
              phx-debounce="200"
              class="input input-sm input-bordered w-96 font-mono"
            />
            <.live_file_input
              upload={@uploads.object}
              class="file-input file-input-sm file-input-bordered"
            />
            <button
              type="submit"
              class="btn btn-primary btn-sm"
              disabled={@uploads.object.entries == []}
            >
              Upload
            </button>
            <%!-- The native file input clears its label on re-render, so show
                  the picked file here instead. --%>
            <span
              :for={entry <- @uploads.object.entries}
              class="flex items-center gap-2 text-xs"
            >
              <span class="font-mono truncate max-w-[14rem]">{entry.client_name}</span>
              <span class="text-base-content/60">{entry.progress}%</span>
              <button
                type="button"
                phx-click="cancel_upload_entry"
                phx-value-ref={entry.ref}
                class="btn btn-ghost btn-xs"
                aria-label="Remove selected file"
              >
                <.icon name="hero-x-mark-solid" class="w-3 h-3" />
              </button>
              <span :for={err <- upload_errors(@uploads.object, entry)} class="text-error">
                {upload_error(err)}
              </span>
            </span>
            <span :for={err <- upload_errors(@uploads.object)} class="text-error text-xs">
              {upload_error(err)}
            </span>
          </form>
        </div>
      </div>

      <div class="card bg-base-200">
        <div class="card-body">
          <form phx-change="filter" id="storage-filter-form" class="flex flex-wrap gap-2 mb-2">
            <input
              type="text"
              name="prefix"
              value={@prefix}
              placeholder="Filter by key prefix (e.g. avatars/)"
              phx-debounce="300"
              class="input input-sm w-96 font-mono"
            />
          </form>

          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th></th>
                  <th>Key</th>
                  <th>Size</th>
                  <th>Modified</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={obj <- @objects} id={"object-#{Base.url_encode64(obj.key, padding: false)}"}>
                  <td>
                    <img
                      :if={image?(obj.key)}
                      src={Storage.url(obj.key)}
                      alt=""
                      class="w-10 h-10 object-cover rounded"
                      loading="lazy"
                    />
                    <span :if={!image?(obj.key)} class="text-base-content/40 text-xs">file</span>
                  </td>
                  <td class="font-mono text-xs break-all">{obj.key}</td>
                  <td class="text-xs whitespace-nowrap">{format_bytes(obj.size)}</td>
                  <td class="text-xs whitespace-nowrap">
                    <.timestamp at={obj.last_modified} format="full" empty="—" />
                  </td>
                  <td class="text-right whitespace-nowrap">
                    <a href={Storage.url(obj.key)} download class="btn btn-outline btn-xs">
                      Download
                    </a>
                    <button
                      phx-click="delete"
                      phx-value-key={obj.key}
                      data-confirm={"Delete #{obj.key}?"}
                      class="btn btn-outline btn-error btn-xs"
                    >
                      Delete
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <div :if={@objects == []} class="text-center py-8 text-base-content/60">
            No objects.
          </div>

          <div class="mt-4 flex justify-center">
            <.pagination
              page={@page}
              total_pages={@total_pages}
              total_count={@count}
              page_size={@page_size}
              on_prev="prev_page"
              on_next="next_page"
              on_page_size="page_size"
            />
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
