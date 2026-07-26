defmodule GameServerWeb.AdminLive.Push do
  use GameServerWeb, :live_view

  alias GameServer.Push

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page, 1)
      |> assign(:page_size, 25)
      |> assign(:filters, %{})
      |> assign(:show_send, false)
      |> assign(:send_form, blank_send_form())
      |> assign(:stats, Push.token_stats())
      |> reload_tokens()

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-6">
        <.link navigate={~p"/admin"} class="btn btn-outline mb-4">← Back to Admin</.link>

        <div class="stats shadow bg-base-200 w-full">
          <div class="stat">
            <div class="stat-title">Live devices</div>
            <div class="stat-value">{@stats.live}</div>
          </div>
          <div class="stat">
            <div class="stat-title">Disabled</div>
            <div class="stat-value">{@stats.disabled}</div>
          </div>
          <div class="stat">
            <div class="stat-title">By platform</div>
            <div class="stat-desc text-sm mt-2">
              <span :for={{platform, count} <- Enum.sort(@stats.by_platform)} class="mr-3">
                {platform}: {count}
              </span>
              <span :if={@stats.by_platform == %{}}>-</span>
            </div>
          </div>
          <div class="stat">
            <div class="stat-title">By provider</div>
            <div class="stat-desc text-sm mt-2">
              <span :for={{provider, count} <- Enum.sort(@stats.by_provider)} class="mr-3">
                {provider}: {count}
              </span>
              <span :if={@stats.by_provider == %{}}>-</span>
            </div>
          </div>
        </div>

        <%!-- Send test push form --%>
        <div class="card bg-base-200">
          <div class="card-body">
            <div class="flex flex-wrap items-center justify-between">
              <h2 class="card-title">Send Test Push</h2>
              <button type="button" phx-click="toggle_send" class="btn btn-sm btn-outline">
                {if @show_send, do: "Hide", else: "Show"}
              </button>
            </div>

            <%= if @show_send do %>
              <.form
                for={@send_form}
                id="admin-send-push-form"
                phx-submit="send_push"
                class="mt-4 space-y-3"
              >
                <.input field={@send_form[:user_id]} type="text" label="User ID" />
                <.input field={@send_form[:title]} type="text" label="Title" />
                <.input field={@send_form[:body]} type="text" label="Body (optional)" />
                <button type="submit" class="btn btn-primary btn-sm">Send Push</button>
              </.form>
              <p class="text-sm text-base-content/70 mt-2">
                Queued to every live device of that user; with no provider configured the
                delivery lands in the server log (Log provider).
              </p>
            <% end %>
          </div>
        </div>

        <div class="card bg-base-200">
          <div class="card-body">
            <h2 class="card-title">Registered Devices ({@count})</h2>

            <form phx-change="filter" id="push-tokens-filter-form">
              <div class="overflow-x-auto mt-4">
                <table class="table table-zebra w-full min-w-[48rem]">
                  <thead>
                    <tr>
                      <th>User</th>
                      <th>Platform</th>
                      <th>Provider</th>
                      <th>Device ID</th>
                      <th>Status</th>
                      <th>Last used</th>
                      <th>Registered</th>
                      <th>Actions</th>
                    </tr>
                    <tr>
                      <th>
                        <input
                          type="text"
                          name="user_id"
                          value={@filters["user_id"]}
                          class="input input-bordered input-xs w-full"
                          placeholder="User ID"
                          phx-debounce="300"
                        />
                      </th>
                      <th>
                        <select name="platform" class="select select-bordered select-xs w-full">
                          <option value="">All</option>
                          <option
                            :for={platform <- GameServer.Push.PushToken.platforms()}
                            value={platform}
                            selected={@filters["platform"] == platform}
                          >
                            {platform}
                          </option>
                        </select>
                      </th>
                      <th>
                        <select name="provider" class="select select-bordered select-xs w-full">
                          <option value="">All</option>
                          <option
                            :for={provider <- GameServer.Push.PushToken.providers()}
                            value={provider}
                            selected={@filters["provider"] == provider}
                          >
                            {provider}
                          </option>
                        </select>
                      </th>
                      <th></th>
                      <th>
                        <select name="status" class="select select-bordered select-xs w-full">
                          <option value="">All</option>
                          <option value="live" selected={@filters["status"] == "live"}>live</option>
                          <option value="disabled" selected={@filters["status"] == "disabled"}>
                            disabled
                          </option>
                        </select>
                      </th>
                      <th></th>
                      <th></th>
                      <th></th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={t <- @tokens} id={"admin-push-token-" <> to_string(t.id)}>
                      <td class="text-sm" title={t.user_id}>{user_display(t.user)}</td>
                      <td class="text-sm">{t.platform}</td>
                      <td class="text-sm">{t.provider}</td>
                      <td class="text-sm font-mono max-w-xs truncate" title={t.device_id}>
                        {t.device_id || "-"}
                      </td>
                      <td class="text-sm">
                        <span :if={is_nil(t.disabled_at)} class="badge badge-success badge-sm">
                          live
                        </span>
                        <span :if={t.disabled_at} class="badge badge-ghost badge-sm">disabled</span>
                      </td>
                      <td class="text-sm whitespace-nowrap">
                        <.timestamp at={t.last_used_at} />
                      </td>
                      <td class="text-sm whitespace-nowrap">
                        <.timestamp at={t.inserted_at} />
                      </td>
                      <td class="text-sm">
                        <button
                          type="button"
                          phx-click="delete_token"
                          phx-value-id={t.id}
                          data-confirm="Delete this device token?"
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
                on_prev="admin_push_prev"
                on_next="admin_push_next"
                on_page_size="admin_push_page_size"
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
     |> reload_tokens()}
  end

  @impl true
  def handle_event("toggle_send", _params, socket) do
    {:noreply, assign(socket, :show_send, !socket.assigns.show_send)}
  end

  @impl true
  def handle_event("send_push", %{"push" => params}, socket) do
    user_id = GameServer.UUIDv7.cast_or_nil(params["user_id"])

    cond do
      is_nil(user_id) ->
        {:noreply, put_flash(socket, :error, "User ID is required")}

      not Push.user_has_live_tokens?(user_id) ->
        {:noreply, put_flash(socket, :error, "That user has no live devices")}

      true ->
        case Push.send_to_user(user_id, %{
               "title" => params["title"],
               "body" => params["body"]
             }) do
          :ok ->
            {:noreply,
             socket
             |> put_flash(:info, "Push queued for delivery")
             |> assign(:send_form, blank_send_form())}

          {:error, errors} ->
            {:noreply, put_flash(socket, :error, "Invalid message: #{inspect(errors)}")}
        end
    end
  end

  @impl true
  def handle_event("delete_token", %{"id" => id}, socket) do
    case Push.admin_delete_token(to_string(id)) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Device token deleted")
         |> assign(:stats, Push.token_stats())
         |> reload_tokens()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete token")}
    end
  end

  @impl true
  def handle_event("admin_push_prev", _params, socket) do
    page = max(1, socket.assigns.page - 1)
    {:noreply, socket |> assign(:page, page) |> reload_tokens()}
  end

  @impl true
  def handle_event("admin_push_next", _params, socket) do
    page = socket.assigns.page + 1
    {:noreply, socket |> assign(:page, page) |> reload_tokens()}
  end

  @impl true
  def handle_event("admin_push_page_size", %{"size" => size}, socket) do
    {:noreply,
     socket
     |> assign(:page_size, String.to_integer(size))
     |> assign(:page, 1)
     |> reload_tokens()}
  end

  defp reload_tokens(socket) do
    page = socket.assigns.page
    page_size = socket.assigns.page_size
    filters = socket.assigns.filters

    tokens = Push.list_all_tokens(filters, page: page, page_size: page_size)
    total_count = Push.count_all_tokens(filters)

    total_pages =
      if page_size > 0,
        do: div(total_count + page_size - 1, page_size),
        else: 0

    socket
    |> assign(:tokens, tokens)
    |> assign(:count, total_count)
    |> assign(:total_pages, total_pages)
  end

  defp blank_send_form do
    to_form(%{"user_id" => "", "title" => "", "body" => ""}, as: :push)
  end
end
