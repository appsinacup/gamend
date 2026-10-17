defmodule GamendWeb.UserLive.Settings.FriendsTab do
  @moduledoc """
  Friends tab of the user settings page: friend requests, blocking, user
  search, and the paginated friends/blocked lists.
  """

  use GamendWeb, :html
  import Phoenix.LiveView

  alias Gamend.Accounts
  alias Gamend.Friends
  alias GamendWeb.LiveHelpers
  alias GamendWeb.UserLive.Settings.Shared

  @page_size 25

  def assign_defaults(socket) do
    socket
    |> assign(:incoming_page, 1)
    |> assign(:incoming_page_size, @page_size)
    |> assign(:outgoing_page, 1)
    |> assign(:outgoing_page_size, @page_size)
    |> assign(:friends_page, 1)
    |> assign(:friends_page_size, @page_size)
    |> assign(:blocked_page, 1)
    |> assign(:blocked_page_size, @page_size)
    |> assign(:new_target_id, "")
    |> assign(:search_query, "")
    |> assign(:search_count, 0)
    |> stream(:search_results, [], dom_id: &"search-#{&1.id}")
    |> assign(:search_page, 1)
    |> assign(:search_page_size, @page_size)
    |> assign(:search_total, 0)
    |> assign(:search_total_pages, 0)
  end

  def tab(assigns) do
    ~H"""
    <div :if={@settings_tab == "friends"}>
      <!-- Friends panel (embedded) -->
      <div class="card bg-base-200 p-4 rounded-lg mt-6">
        <div class="flex items-center justify-between">
          <div>
            <div class="font-semibold text-lg">{gettext("Friends")}</div>
          </div>
        </div>

        <div class="mt-4 grid grid-cols-1 md:grid-cols-3 gap-4">
          <div>
            <h4 class="font-semibold">{gettext("Incoming requests")}</h4>
            <div id="incoming-requests" phx-update="stream">
              <div
                :for={{dom_id, req} <- @streams.incoming}
                id={dom_id}
                class="p-2 border rounded mt-2"
              >
                <div class="text-sm">
                  <.player_name name={LiveHelpers.public_user_name(req.requester || req.requester_id)} />
                  <span class="text-xs text-muted ms-2">
                    {LiveHelpers.public_user_handle(req.requester)}
                  </span>
                </div>
                <div class="flex gap-2 mt-2">
                  <button
                    phx-click="accept_friend"
                    phx-value-id={req.id}
                    class="btn btn-sm btn-primary"
                  >
                    {gettext("Accept")}
                  </button>
                  <button phx-click="reject_friend" phx-value-id={req.id} class="btn btn-sm btn-error">
                    {gettext("Reject")}
                  </button>
                  <button
                    phx-click="block_friend"
                    phx-value-id={req.id}
                    class="btn btn-sm btn-outline btn-error"
                  >
                    {gettext("Block")}
                  </button>
                </div>
              </div>
            </div>

            <div :if={@incoming_total_pages > 1} class="mt-2">
              <.pagination
                page={@incoming_page}
                total_pages={@incoming_total_pages}
                total_count={@incoming_total}
                on_prev="incoming_prev"
                on_next="incoming_next"
              />
            </div>
          </div>

          <div>
            <h4 class="font-semibold">{gettext("Sent requests")}</h4>
            <div id="outgoing-requests" phx-update="stream">
              <div
                :for={{dom_id, req} <- @streams.outgoing}
                id={dom_id}
                class="p-2 border rounded mt-2"
              >
                <div class="text-sm">
                  <.player_name name={LiveHelpers.public_user_name(req.target || req.target_id)} />
                  <span class="text-xs text-muted ms-2">
                    {LiveHelpers.public_user_handle(req.target)}
                  </span>
                </div>
                <div class="flex gap-2 mt-2">
                  <button phx-click="cancel_friend" phx-value-id={req.id} class="btn btn-sm btn-error">
                    {gettext("Cancel")}
                  </button>
                </div>
              </div>
            </div>
            <div :if={@outgoing_total_pages > 1} class="mt-2">
              <.pagination
                page={@outgoing_page}
                total_pages={@outgoing_total_pages}
                total_count={@outgoing_total}
                on_prev="outgoing_prev"
                on_next="outgoing_next"
              />
            </div>
          </div>

          <div>
            <h4 class="font-semibold">{gettext("Friends")}</h4>
            <div id="friends-list" phx-update="stream">
              <div
                :for={{dom_id, u} <- @streams.friends}
                id={dom_id}
                class="p-2 border rounded mt-2"
              >
                <div class="flex justify-between items-center gap-2">
                  <div class="text-sm flex items-center gap-2">
                    <span
                      class={[
                        "inline-block w-2 h-2 rounded-full shrink-0",
                        if(u.is_online, do: "bg-green-500", else: "bg-gray-400")
                      ]}
                      title={if(u.is_online, do: gettext("Online"), else: gettext("Offline"))}
                    />
                    <.player_name name={LiveHelpers.public_user_name(u)} />
                    <span class="text-xs text-muted">
                      {LiveHelpers.public_user_handle(u)}
                    </span>
                  </div>
                  <div class="flex gap-1">
                    <button
                      phx-click="remove_friend"
                      phx-value-friend_id={u.id}
                      class="btn btn-sm btn-error btn-outline"
                    >
                      {gettext("Remove")}
                    </button>
                  </div>
                </div>
              </div>
            </div>
            <div :if={@friends_total_pages > 1} class="mt-2">
              <.pagination
                page={@friends_page}
                total_pages={@friends_total_pages}
                total_count={@friends_total}
                on_prev="friends_prev"
                on_next="friends_next"
              />
            </div>
          </div>
        </div>

        <div class="divider mt-4" />

        <div class="mt-2">
          <div :if={@blocked_total > 0} class="mt-4">
            <div class="text-xs text-muted">{gettext("Blocked users")}</div>
            <div id="blocked-list" phx-update="stream">
              <div
                :for={{dom_id, b} <- @streams.blocked}
                id={dom_id}
                class="p-2 border rounded mt-2 flex items-center justify-between"
              >
                <div class="text-sm">
                  <.player_name name={LiveHelpers.public_user_name(b.requester || b.requester_id)} />
                  <span class="text-xs text-muted ms-2">
                    {LiveHelpers.public_user_handle(b.requester)}
                  </span>
                </div>
                <div>
                  <button
                    phx-click="unblock_friend"
                    phx-value-id={b.id}
                    class="btn btn-surface btn-sm"
                  >
                    {gettext("Unblock")}
                  </button>
                </div>
              </div>
            </div>
            <div :if={@blocked_total_pages > 1} class="mt-2">
              <.pagination
                page={@blocked_page}
                total_pages={@blocked_total_pages}
                total_count={@blocked_total}
                on_prev="blocked_prev"
                on_next="blocked_next"
              />
            </div>
          </div>

          <div class="flex items-center gap-2">
            <form
              id="settings-search-users-form"
              phx-change="search_users"
              phx-no-unused-field
              class="w-full"
            >
              <input
                type="text"
                name="q"
                value={@search_query}
                placeholder={gettext("Search...")}
                class="input"
              />
            </form>
          </div>
          <div :if={@search_count > 0} class="mt-3">
            <div class="text-xs text-muted mb-2">
              {gettext("Name")}
            </div>

            <!-- Render search results as a responsive grid so multiple items show side-by-side -->
            <div id="search-results" phx-update="stream" class="grid grid-cols-1 md:grid-cols-3 gap-2">
              <div :for={{dom_id, s} <- @streams.search_results} id={dom_id}>
                <div class="p-2 border rounded bg-base-100 flex items-center justify-between">
                  <div class="text-sm">
                    <.player_name name={LiveHelpers.public_user_name(s)} />
                    <span class="text-xs text-muted ms-2">
                      {LiveHelpers.public_user_handle(s)}
                    </span>
                  </div>
                  <div :if={s.id != @current_scope.user_id}>
                    <button
                      phx-click="send_friend"
                      phx-value-target={s.id}
                      class="btn btn-sm btn-primary"
                    >
                      {gettext("Send")}
                    </button>
                  </div>
                </div>
              </div>
            </div>
            <div :if={@search_total_pages > 1} class="mt-2">
              <.pagination
                page={@search_page}
                total_pages={@search_total_pages}
                total_count={@search_total}
                on_prev="search_prev"
                on_next="search_next"
              />
            </div>
          </div>
        </div>
      </div>
    </div>

    <%!-- Payments tab --%>
    """
  end

  def handle_event("search_users", params, socket) do
    q = params["q"] || ""
    page = socket.assigns.search_page || 1
    page_size = socket.assigns.search_page_size || @page_size
    results = Accounts.search_users(q, page: page, page_size: page_size)
    total = if q == "", do: 0, else: Accounts.count_search_users(q)
    total_pages = LiveHelpers.total_pages(total, page_size)

    {:noreply,
     socket
     |> stream(:search_results, results, reset: true, dom_id: &"search-#{&1.id}")
     |> assign(
       search_query: q,
       search_count: length(results),
       search_total: total,
       search_total_pages: total_pages
     )}
  end

  def handle_event("send_friend", params, socket) do
    user = Shared.current_user(socket)
    target = params["target_id"] || params["target"]
    target_id = to_string(target)

    case Friends.create_request(user.id, target_id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Success."))
         |> refresh_friend_lists(user)}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, LiveHelpers.failure_message(gettext("Failed"), reason))}
    end
  end

  def handle_event("block_friend", %{"id" => id}, socket) do
    user = Shared.current_user(socket)
    id = to_string(id)

    case Friends.block_friend_request(id, user) do
      {:ok, _} ->
        {:noreply, refresh_friend_lists(socket, user)}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, LiveHelpers.failure_message(gettext("Failed"), reason))}
    end
  end

  def handle_event("accept_friend", %{"id" => id}, socket) do
    user = Shared.current_user(socket)
    id = to_string(id)

    case Friends.accept_friend_request(id, user) do
      {:ok, _} ->
        {:noreply, refresh_friend_lists(socket, user)}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, LiveHelpers.failure_message(gettext("Failed"), reason))}
    end
  end

  def handle_event("reject_friend", %{"id" => id}, socket) do
    user = Shared.current_user(socket)
    id = to_string(id)

    case Friends.reject_friend_request(id, user) do
      {:ok, _} ->
        {:noreply, refresh_friend_lists(socket, user)}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, LiveHelpers.failure_message(gettext("Failed"), reason))}
    end
  end

  def handle_event("cancel_friend", %{"id" => id}, socket) do
    user = Shared.current_user(socket)
    id = to_string(id)

    case Friends.cancel_request(id, user) do
      {:ok, _} ->
        {:noreply, refresh_friend_lists(socket, user)}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, LiveHelpers.failure_message(gettext("Failed"), reason))}
    end
  end

  def handle_event("remove_friend", %{"friend_id" => fid}, socket) do
    user = Shared.current_user(socket)
    fid = to_string(fid)

    case Friends.remove_friend(user.id, fid) do
      {:ok, _} ->
        {:noreply, refresh_friend_lists(socket, user)}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, LiveHelpers.failure_message(gettext("Failed"), reason))}
    end
  end

  def handle_event("unblock_friend", %{"id" => id}, socket) do
    user = Shared.current_user(socket)
    id = to_string(id)

    case Friends.unblock_friendship(id, user) do
      {:ok, :unblocked} ->
        {:noreply, refresh_friend_lists(socket, user)}

      {:error, reason} ->
        {:noreply,
         put_flash(socket, :error, LiveHelpers.failure_message(gettext("Failed"), reason))}
    end
  end

  def handle_event("search_prev", _params, socket) do
    page = max(1, (socket.assigns.search_page || 1) - 1)
    {:noreply, search_page(socket, page)}
  end

  def handle_event("search_next", _params, socket) do
    page = (socket.assigns.search_page || 1) + 1
    {:noreply, search_page(socket, page)}
  end

  def handle_event(event, _params, socket)
      when event in ~w(incoming_prev incoming_next outgoing_prev outgoing_next friends_prev friends_next blocked_prev blocked_next) do
    [list, direction] = String.split(event, "_")
    page_key = String.to_existing_atom("#{list}_page")
    current = socket.assigns[page_key] || 1
    page = if direction == "prev", do: max(1, current - 1), else: current + 1

    {:noreply,
     socket
     |> assign(page_key, page)
     |> refresh_friend_lists(Shared.current_user(socket))}
  end

  defp search_page(socket, page) do
    q = socket.assigns.search_query || ""
    page_size = socket.assigns.search_page_size || @page_size
    results = Accounts.search_users(q, page: page, page_size: page_size)
    total = if q == "", do: 0, else: Accounts.count_search_users(q)
    total_pages = LiveHelpers.total_pages(total, page_size)

    socket
    |> stream(:search_results, results, reset: true, dom_id: &"search-#{&1.id}")
    |> assign(
      search_page: page,
      search_count: length(results),
      search_total: total,
      search_total_pages: total_pages
    )
  end

  @doc """
  Reloads all four friend lists (incoming, outgoing, friends, blocked) plus
  their totals for the currently assigned pages.
  """
  def refresh_friend_lists(socket, user) do
    incoming_page = socket.assigns[:incoming_page] || 1
    incoming_page_size = socket.assigns[:incoming_page_size] || @page_size
    outgoing_page = socket.assigns[:outgoing_page] || 1
    outgoing_page_size = socket.assigns[:outgoing_page_size] || @page_size
    friends_page = socket.assigns[:friends_page] || 1
    friends_page_size = socket.assigns[:friends_page_size] || @page_size
    blocked_page = socket.assigns[:blocked_page] || 1
    blocked_page_size = socket.assigns[:blocked_page_size] || @page_size

    incoming =
      Friends.list_incoming_requests(user.id, page: incoming_page, page_size: incoming_page_size)

    outgoing =
      Friends.list_outgoing_requests(user.id, page: outgoing_page, page_size: outgoing_page_size)

    friends =
      Friends.list_friends_for_user(user.id, page: friends_page, page_size: friends_page_size)

    blocked =
      Friends.list_blocked_for_user(user.id, page: blocked_page, page_size: blocked_page_size)

    incoming_total = Friends.count_incoming_requests(user.id)
    outgoing_total = Friends.count_outgoing_requests(user.id)
    friends_total = Friends.count_friends_for_user(user.id)
    blocked_total = Friends.count_blocked_for_user(user.id)

    socket
    |> stream(:incoming, incoming, reset: true, dom_id: &"request-#{&1.id}")
    |> stream(:outgoing, outgoing, reset: true, dom_id: &"outgoing-#{&1.id}")
    |> stream(:friends, friends, reset: true, dom_id: &"friend-#{&1.id}")
    |> stream(:blocked, blocked, reset: true, dom_id: &"blocked-#{&1.id}")
    |> assign(
      incoming_total: incoming_total,
      outgoing_total: outgoing_total,
      friends_total: friends_total,
      blocked_total: blocked_total,
      incoming_total_pages: LiveHelpers.total_pages(incoming_total, incoming_page_size),
      outgoing_total_pages: LiveHelpers.total_pages(outgoing_total, outgoing_page_size),
      friends_total_pages: LiveHelpers.total_pages(friends_total, friends_page_size),
      blocked_total_pages: LiveHelpers.total_pages(blocked_total, blocked_page_size),
      friend_unread_counts: %{}
    )
  end
end
