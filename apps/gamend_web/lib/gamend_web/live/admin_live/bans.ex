defmodule GamendWeb.AdminLive.Bans do
  @moduledoc """
  `/admin/bans`: every ban (`Gamend.Bans`), IP addresses, accounts and chat
  mutes, active and ended, with a form to place one and a button to lift it.

  An account ban lets the player sign in, read and delete their account, and
  nothing else; an IP ban refuses every request from the address; a chat ban
  silences the player everywhere or in one lobby, group or party. A ban that
  ends stays as a row, which is the target's history.
  """
  use GamendWeb, :live_view

  alias Gamend.Accounts.Scope
  alias Gamend.Bans
  alias Gamend.Bans.Cache
  alias GamendWeb.AdminLive.BanForm
  alias GamendWeb.LiveHelpers

  use GamendWeb.UrlState,
    reload: :reload,
    drop: ~w(user_id),
    keys: [
      :page,
      :page_size,
      kind_filter: [param: "kind", in: ["", "ip", "account", "chat"]],
      target_filter: [param: "target"],
      active_only: [param: "active"]
    ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Admin · Bans")
     |> assign(:page, 1)
     |> assign(:page_size, 25)
     |> assign(:kind_filter, "")
     |> assign(:target_filter, "")
     |> assign(:active_only, true)
     |> assign(:form, new_form())
     |> assign(:form_error, nil)
     |> reload()}
  end

  # `?user_id=` (the Users page's link): that account's history, ended bans
  # included, and the form filled with it.
  @impl true
  def handle_params(%{"user_id" => user_id}, _uri, socket) when is_binary(user_id) do
    user_id = String.trim(user_id)
    form = Map.merge(socket.assigns.form, %{"kind" => "account", "target" => user_id})

    {:noreply,
     socket
     |> assign(form: form, target_filter: user_id, active_only: false, page: 1)
     |> reload()}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("form_change", params, socket) do
    {:noreply, assign(socket, :form, Map.take(params, Map.keys(new_form())))}
  end

  def handle_event("ban", params, socket) do
    form = Map.take(params, Map.keys(new_form()))
    target = String.trim(form["target"] || "")
    kind = Map.get(%{"ip" => :ip, "chat" => :chat}, form["kind"], :account)

    socket =
      if target == "" do
        assign(socket, form: form, form_error: "Enter the user id or the IP address to ban.")
      else
        case BanForm.place(kind, target, form, Scope.user_id(socket.assigns.current_scope)) do
          {:ok, ban} ->
            socket
            |> assign(form: new_form(), form_error: nil)
            |> put_flash(:info, "Banned #{ban.subject}")

          {:error, message} ->
            assign(socket, form: form, form_error: message)
        end
      end

    {:noreply, reload(socket)}
  end

  def handle_event("lift", %{"id" => id}, socket) do
    socket =
      case Enum.find(socket.assigns.bans, &(&1.id == id)) do
        %Bans.Ban{} = ban ->
          if Bans.active?(ban) do
            {:ok, _lifted} =
              Bans.lift_ban(ban, by: Scope.user_id(socket.assigns.current_scope))
          end

          put_flash(socket, :info, "Lifted the ban on #{ban.subject}")

        nil ->
          put_flash(socket, :error, "Ban not found")
      end

    {:noreply, reload(socket)}
  end

  def handle_event("filter", params, socket) do
    {:noreply,
     socket
     |> assign(:kind_filter, Map.get(params, "kind", ""))
     |> assign(:target_filter, String.trim(Map.get(params, "target", "")))
     |> assign(:active_only, Map.get(params, "active") == "true")
     |> assign(:page, 1)
     |> reload()}
  end

  def handle_event("prev_page", _params, socket),
    do: {:noreply, socket |> LiveHelpers.prev_page() |> reload()}

  def handle_event("next_page", _params, socket),
    do: {:noreply, socket |> LiveHelpers.next_page() |> reload()}

  def handle_event("page_size", %{"size" => size}, socket),
    do: {:noreply, socket |> LiveHelpers.put_page_size(size) |> reload()}

  defp new_form do
    BanForm.empty()
    |> Map.merge(BanForm.chat_defaults())
    |> Map.merge(%{"kind" => "account", "target" => ""})
  end

  defp reload(socket) do
    filters = %{
      "kind" => socket.assigns.kind_filter,
      "subject" => socket.assigns.target_filter,
      "active" => socket.assigns.active_only
    }

    total = Bans.count(filters)

    socket
    |> assign(
      :bans,
      Bans.list(filters, page: socket.assigns.page, page_size: socket.assigns.page_size)
    )
    |> assign(:count, total)
    |> assign(:cached, length(Cache.list()))
    |> assign(:total_pages, LiveHelpers.total_pages(total, socket.assigns.page_size))
  end

  defp placed_by(%Bans.Ban{banned_by_user: %{} = admin}), do: user_display(admin)
  defp placed_by(%Bans.Ban{source: source}), do: to_string(source)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <.admin_header page="/admin/bans" />

      <div class="card bg-base-200">
        <div class="card-body">
          <div class="flex flex-wrap items-baseline gap-2">
            <h2 class="card-title">Bans ({@count})</h2>
            <span
              class="badge badge-sm badge-ghost"
              title="Active bans loaded into this node's memory. Enforcement reads this, not the database."
            >
              {@cached} on this node
            </span>
          </div>

          <p class="text-sm text-muted">
            An account ban lets the player sign in, read and delete their account, and nothing
            else: the API answers <code>account_banned</code>, the socket keeps only their user
            channel, and the website sends them to a page that says why and until when. An IP
            ban refuses every request from the address (an IPv6 one by its /64). A chat ban (a
            mute) rejects the player's messages everywhere, friend DMs included, or in one lobby,
            group or party. A ban that ends stays below as history.
          </p>

          <form
            phx-submit="ban"
            phx-change="form_change"
            phx-no-unused-field
            id="ban-add-form"
            class="flex flex-wrap items-end gap-2 my-2"
          >
            <div>
              <label class="label text-xs">Kind</label>
              <select name="kind" class="select select-bordered select-sm">
                <option value="account" selected={@form["kind"] == "account"}>Account</option>
                <option value="ip" selected={@form["kind"] == "ip"}>IP address</option>
                <option value="chat" selected={@form["kind"] == "chat"}>Chat (mute)</option>
              </select>
            </div>
            <div>
              <label class="label text-xs">
                {if @form["kind"] == "ip", do: "IP address", else: "User id"}
              </label>
              <input
                type="text"
                name="target"
                value={@form["target"]}
                class="input input-bordered input-sm w-72 font-mono"
              />
            </div>
            <BanForm.fields form={@form} />
            <BanForm.chat_fields :if={@form["kind"] == "chat"} form={@form} />
            <button type="submit" class="btn btn-warning btn-sm">
              <.icon name="hero-no-symbol" class="w-4 h-4" /> Ban
            </button>
          </form>

          <p :if={@form_error} class="text-error text-xs">{@form_error}</p>

          <form
            phx-change="filter"
            phx-no-unused-field
            id="bans-filter-form"
            class="flex flex-wrap items-center gap-3 my-2"
          >
            <select name="kind" class="select select-sm">
              <option value="" selected={@kind_filter == ""}>All kinds</option>
              <option value="account" selected={@kind_filter == "account"}>Accounts</option>
              <option value="ip" selected={@kind_filter == "ip"}>IP addresses</option>
              <option value="chat" selected={@kind_filter == "chat"}>Chat mutes</option>
            </select>
            <input
              type="text"
              name="target"
              value={@target_filter}
              placeholder="User id or IP"
              phx-debounce="300"
              class="input input-sm w-72 font-mono"
            />
            <label class="label cursor-pointer gap-2 text-sm">
              <input
                type="checkbox"
                name="active"
                value="true"
                checked={@active_only}
                class="checkbox checkbox-sm"
              /> Active only
            </label>
          </form>

          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>Target</th>
                  <th>Reason</th>
                  <th>Ends</th>
                  <th>Status</th>
                  <th>Placed</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={ban <- @bans} id={"ban-#{ban.id}"}>
                  <td>
                    <%= if ban.kind in [:account, :chat] do %>
                      <div class="flex items-center gap-2">
                        <span class="badge badge-sm">{ban.kind}</span>
                        <.user_avatar user={ban.user} class="size-6 shrink-0" />
                        {user_display(ban.user)}
                      </div>
                      <div class="font-mono text-xs text-muted">{ban.subject}</div>
                      <div :if={ban.kind == :chat} class="text-xs text-muted">
                        {ban.scope}
                        <span :if={ban.scope_ref_id} class="font-mono">
                          {ban.scope_ref_id}
                        </span>
                      </div>
                    <% else %>
                      <span class="badge badge-sm">ip</span>
                      <span class="font-mono text-xs">{ban.subject}</span>
                    <% end %>
                  </td>
                  <td class="text-sm max-w-xs truncate" title={ban.reason}>{ban.reason}</td>
                  <td class="text-xs">
                    <%= if ban.expires_at do %>
                      <.timestamp at={ban.expires_at} />
                    <% else %>
                      <span class="badge badge-error badge-xs">Permanent</span>
                    <% end %>
                  </td>
                  <td>
                    <%= cond do %>
                      <% Bans.active?(ban) -> %>
                        <span class="badge badge-error badge-xs">ACTIVE</span>
                      <% ban.lifted_at -> %>
                        <span
                          class="badge badge-success badge-xs"
                          title={"Lifted by #{user_display(ban.lifted_by_user)}"}
                        >
                          LIFTED
                        </span>
                      <% true -> %>
                        <span class="badge badge-ghost badge-xs">EXPIRED</span>
                    <% end %>
                  </td>
                  <td class="text-xs">
                    <.timestamp at={ban.inserted_at} />
                    <div class="flex items-center gap-1 text-muted">
                      <.user_avatar
                        :if={match?(%Gamend.Accounts.User{}, ban.banned_by_user)}
                        user={ban.banned_by_user}
                        class="size-4 shrink-0"
                      />
                      {placed_by(ban)}
                    </div>
                  </td>
                  <td class="text-right">
                    <button
                      :if={Bans.active?(ban)}
                      phx-click="lift"
                      phx-value-id={ban.id}
                      data-confirm
                      class="btn btn-outline btn-success btn-xs"
                    >
                      Lift
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <div :if={@bans == []} class="text-center py-8 text-muted">No bans.</div>

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
