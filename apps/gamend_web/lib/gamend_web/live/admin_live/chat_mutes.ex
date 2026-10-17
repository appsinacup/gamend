defmodule GamendWeb.AdminLive.ChatMutes do
  @moduledoc """
  Admin view over chat mutes: every mute in the system, filterable by scope and
  by whether it is still in force, with add and unmute.
  """
  use GamendWeb, :live_view

  alias Gamend.Accounts.Scope
  alias Gamend.Chat
  alias Gamend.Chat.Moderation.Cache
  alias Gamend.Chat.Moderation.Notices
  alias Gamend.Chat.Mute
  alias GamendWeb.AdminLive.Shared
  alias GamendWeb.LiveHelpers

  @empty_form %{
    "user_id" => "",
    "scope" => "global",
    "scope_ref_id" => "",
    "reason" => "",
    "duration" => "permanent",
    "notify" => "true",
    "notify_message" => ""
  }

  @edit_keys ~w(duration reason notify notify_message)

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Admin · Chat mutes")
      |> assign(:page, 1)
      |> assign(:page_size, 25)
      |> assign(:scope_filter, "")
      |> assign(:active_only, true)
      |> assign(:form_error, nil)
      |> assign(:edit_mute, nil)
      |> assign(:edit_form, nil)
      |> assign(:edit_error, nil)
      |> assign(:edit_notice_default, nil)
      |> reset_add_form()
      |> reload()

    {:ok, socket}
  end

  # Deep-link from the report queue: `?user_id=` pre-fills the mute form with the
  # reported player.
  @impl true
  def handle_params(%{"user_id" => user_id}, _uri, socket) when is_binary(user_id) do
    case String.trim(user_id) do
      "" ->
        {:noreply, socket}

      trimmed ->
        {:noreply, assign(socket, :form, Map.put(socket.assigns.form, "user_id", trimmed))}
    end
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("filter", params, socket) do
    {:noreply,
     socket
     |> assign(:scope_filter, Map.get(params, "scope", ""))
     |> assign(:active_only, Map.get(params, "active") == "true")
     |> assign(:page, 1)
     |> reload()}
  end

  def handle_event("form_change", params, socket) do
    form = Map.take(params, Map.keys(@empty_form))
    notice = default_notice(form)

    {:noreply,
     socket
     |> assign(:form, sync_notice(form, socket.assigns.notice_default, notice))
     |> assign(:notice_default, notice)}
  end

  def handle_event("mute", params, socket) do
    form = Map.take(params, Map.keys(@empty_form))
    socket = assign(socket, :form, form)

    user_id = String.trim(form["user_id"] || "")
    scope = form["scope"] || "global"
    scope_ref_id = Gamend.Parse.blank_to_nil(String.trim(form["scope_ref_id"] || ""))

    attrs = %{
      "expires_at" => expires_at(form["duration"]),
      "reason" => Gamend.Parse.blank_to_nil(String.trim(form["reason"] || "")),
      "muted_by" => Scope.user_id(socket.assigns.current_scope)
    }

    socket =
      cond do
        user_id == "" ->
          assign(socket, :form_error, gettext("Enter the player id to mute."))

        scope != "global" and is_nil(scope_ref_id) ->
          assign(
            socket,
            :form_error,
            gettext("A scoped mute needs the lobby, group or party id.")
          )

        true ->
          case Chat.mute_user(user_id, scope, scope_ref_id, attrs) do
            {:ok, mute} ->
              maybe_notify(form, socket.assigns.notice_default, mute)

              socket
              |> reset_add_form()
              |> assign(:form_error, nil)
              |> put_flash(:info, gettext("Player muted"))

            {:error, changeset} ->
              assign(socket, :form_error, changeset_error_summary(changeset))
          end
      end

    {:noreply, reload(socket)}
  end

  def handle_event("unmute", %{"id" => id}, socket) do
    socket =
      case Enum.find(socket.assigns.mutes, &(&1.id == id)) do
        nil ->
          put_flash(socket, :error, gettext("Mute not found"))

        mute ->
          case Chat.unmute_user(mute.user_id, mute.scope, mute.scope_ref_id) do
            {:ok, 0} -> put_flash(socket, :error, gettext("Mute not found"))
            {:ok, _count} -> put_flash(socket, :info, gettext("Player unmuted"))
          end
      end

    {:noreply, reload(socket)}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    case Enum.find(socket.assigns.mutes, &(&1.id == id)) do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("Mute not found"))}

      mute ->
        notice = Notices.default_mute_message(mute)

        form = %{
          "duration" => "keep",
          "reason" => mute.reason || "",
          "notify" => "true",
          "notify_message" => notice
        }

        {:noreply,
         socket
         |> assign(:edit_mute, mute)
         |> assign(:edit_form, form)
         |> assign(:edit_notice_default, notice)
         |> assign(:edit_error, nil)}
    end
  end

  def handle_event("edit_change", params, socket) do
    form = Map.take(params, @edit_keys)
    notice = edit_notice(form, socket.assigns.edit_mute)

    {:noreply,
     socket
     |> assign(:edit_form, sync_notice(form, socket.assigns.edit_notice_default, notice))
     |> assign(:edit_notice_default, notice)}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, socket |> assign(:edit_form, nil) |> assign(:edit_mute, nil)}
  end

  def handle_event("save_edit", params, socket) do
    mute = socket.assigns.edit_mute
    form = Map.take(params, @edit_keys)

    attrs = %{
      "expires_at" => edit_expires_at(form["duration"], mute),
      "reason" => Gamend.Parse.blank_to_nil(String.trim(form["reason"] || "")),
      "muted_by" => Scope.user_id(socket.assigns.current_scope)
    }

    socket =
      case Chat.mute_user(mute.user_id, mute.scope, mute.scope_ref_id, attrs) do
        {:ok, updated} ->
          maybe_notify(form, socket.assigns.edit_notice_default, updated)

          socket
          |> assign(:edit_mute, nil)
          |> assign(:edit_form, nil)
          |> assign(:edit_error, nil)
          |> put_flash(:info, gettext("Mute updated"))

        {:error, changeset} ->
          socket
          |> assign(:edit_form, form)
          |> assign(:edit_error, changeset_error_summary(changeset))
      end

    {:noreply, reload(socket)}
  end

  def handle_event("prev_page", _params, socket),
    do: {:noreply, socket |> LiveHelpers.prev_page() |> reload()}

  def handle_event("next_page", _params, socket),
    do: {:noreply, socket |> LiveHelpers.next_page() |> reload()}

  def handle_event("page_size", %{"size" => size}, socket),
    do: {:noreply, socket |> LiveHelpers.put_page_size(size) |> reload()}

  def handle_event("refresh", _params, socket) do
    {:noreply, reload(socket)}
  end

  # ── data ──────────────────────────────────────────────────────────────────

  defp reload(socket) do
    filters = %{
      "scope" => Gamend.Parse.blank_to_nil(socket.assigns.scope_filter),
      "active" => socket.assigns.active_only
    }

    mutes =
      Chat.list_mutes(filters, page: socket.assigns.page, page_size: socket.assigns.page_size)

    total = Chat.count_mutes(filters)

    socket
    |> assign(:mutes, mutes)
    |> assign(:count, total)
    |> assign(:cached_mutes, Cache.mute_count())
    |> assign(:total_pages, LiveHelpers.total_pages(total, socket.assigns.page_size))
  end

  defp expires_at("10m"), do: from_now(600)
  defp expires_at("1h"), do: from_now(3_600)
  defp expires_at("24h"), do: from_now(86_400)
  defp expires_at("7d"), do: from_now(604_800)
  defp expires_at(_permanent), do: nil

  defp from_now(seconds) do
    DateTime.add(DateTime.utc_now(:second), seconds, :second)
  end

  defp edit_duration_options do
    [{"keep", gettext("Keep current expiry")} | Shared.duration_options()]
  end

  defp edit_expires_at("keep", mute), do: mute.expires_at
  defp edit_expires_at(duration, _mute), do: expires_at(duration)

  defp reset_add_form(socket) do
    notice = default_notice(@empty_form)

    socket
    |> assign(:form, Map.put(@empty_form, "notify_message", notice))
    |> assign(:notice_default, notice)
  end

  defp default_notice(form) do
    Notices.default_mute_message(%Mute{
      scope: form["scope"] || "global",
      expires_at: expires_at(form["duration"]),
      reason: Gamend.Parse.blank_to_nil(String.trim(form["reason"] || ""))
    })
  end

  defp edit_notice(form, mute) do
    Notices.default_mute_message(%{
      mute
      | expires_at: edit_expires_at(form["duration"], mute),
        reason: Gamend.Parse.blank_to_nil(String.trim(form["reason"] || ""))
    })
  end

  # An untouched notice follows the duration and reason; once a moderator edits
  # it their wording wins.
  defp sync_notice(form, shown_default, new_default) do
    if form["notify_message"] == shown_default,
      do: Map.put(form, "notify_message", new_default),
      else: form
  end

  defp maybe_notify(form, shown_default, mute) do
    if form["notify"] == "true" do
      Notices.notify_muted(mute.user_id, notice_message(form, shown_default, mute))
    end

    :ok
  end

  # An untouched notice is rebuilt from the stored mute so the expiry it quotes
  # is the one that was actually saved.
  defp notice_message(form, shown_default, mute) do
    text = String.trim(form["notify_message"] || "")

    if text == "" or text == shown_default do
      Notices.default_mute_message(mute)
    else
      text
    end
  end

  defp muted_by_label(%{muted_by: nil}), do: gettext("System")
  defp muted_by_label(mute), do: user_display(mute.muted_by_user)

  defp changeset_error_summary(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> Enum.map_join("; ", fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
  end

  # ── render ────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <.link navigate={~p"/admin"} class="btn btn-surface mb-4">← {gettext("Back to Admin")}</.link>

      <div class="card bg-base-200">
        <div class="card-body">
          <div class="flex flex-wrap items-center justify-between gap-2">
            <div class="flex flex-wrap items-baseline gap-2">
              <h2 class="card-title">{gettext("Chat mutes")} ({@count})</h2>
              <span
                class="badge badge-sm badge-ghost"
                title={
                  gettext(
                    "Unexpired mutes loaded into this node's memory. Enforcement reads this, not the database."
                  )
                }
              >
                {gettext("%{n} on this node", n: @cached_mutes)}
              </span>
            </div>
            <button phx-click="refresh" class="btn btn-ghost btn-sm">{gettext("Refresh")}</button>
          </div>

          <p class="text-sm text-muted">
            {gettext(
              "A muted player's messages are rejected before they are stored. A global mute covers every chat including friend DMs; a scoped mute silences one lobby, group or party."
            )}
          </p>

          <form
            phx-submit="mute"
            phx-change="form_change"
            phx-no-unused-field
            id="chat-mute-add-form"
            class="flex flex-wrap items-end gap-2 my-2"
          >
            <div>
              <label class="label text-xs">{gettext("Player id")}</label>
              <input
                type="text"
                name="user_id"
                value={@form["user_id"]}
                class="input input-bordered input-sm w-72 font-mono"
              />
            </div>
            <div>
              <label class="label text-xs">{gettext("Scope")}</label>
              <select name="scope" class="select select-bordered select-sm">
                <option :for={scope <- Mute.scopes()} value={scope} selected={@form["scope"] == scope}>
                  {scope}
                </option>
              </select>
            </div>
            <div>
              <label class="label text-xs">{gettext("Lobby / group / party id")}</label>
              <input
                type="text"
                name="scope_ref_id"
                value={@form["scope_ref_id"]}
                placeholder={gettext("Global mutes leave this empty")}
                class="input input-bordered input-sm w-72 font-mono"
              />
            </div>
            <div>
              <label class="label text-xs">{gettext("Reason")}</label>
              <input
                type="text"
                name="reason"
                value={@form["reason"]}
                class="input input-bordered input-sm w-56"
              />
            </div>
            <div>
              <label class="label text-xs">{gettext("Duration")}</label>
              <select name="duration" class="select select-bordered select-sm">
                <option
                  :for={{value, label} <- Shared.duration_options()}
                  value={value}
                  selected={@form["duration"] == value}
                >
                  {label}
                </option>
              </select>
            </div>
            <div class="w-full">
              <label class="label cursor-pointer justify-start gap-2 text-xs">
                <input type="hidden" name="notify" value="false" />
                <input
                  type="checkbox"
                  name="notify"
                  value="true"
                  checked={@form["notify"] == "true"}
                  class="checkbox checkbox-sm"
                />
                {gettext("Notify the player")}
              </label>
              <textarea
                name="notify_message"
                rows="2"
                class="textarea textarea-bordered textarea-sm w-full"
              ><%= @form["notify_message"] %></textarea>
            </div>
            <button type="submit" class="btn btn-warning btn-sm">{gettext("Mute player")}</button>
          </form>

          <p :if={@form_error} class="text-error text-xs">{@form_error}</p>

          <form
            phx-change="filter"
            phx-no-unused-field
            id="chat-mutes-filter-form"
            class="flex flex-wrap gap-3 my-2"
          >
            <select name="scope" class="select select-sm">
              <option value="">{gettext("All scopes")}</option>
              <option :for={scope <- Mute.scopes()} value={scope} selected={@scope_filter == scope}>
                {scope}
              </option>
            </select>
            <label class="label cursor-pointer gap-2 text-sm">
              <input
                type="checkbox"
                name="active"
                value="true"
                checked={@active_only}
                class="checkbox checkbox-sm"
              />
              {gettext("Active only")}
            </label>
          </form>

          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>{gettext("Player")}</th>
                  <th>{gettext("Muted by")}</th>
                  <th>{gettext("Scope")}</th>
                  <th>{gettext("Reason")}</th>
                  <th>{gettext("Expires")}</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={mute <- @mutes} id={"mute-#{mute.id}"}>
                  <td>
                    {user_display(mute.user)}
                    <div class="font-mono text-xs text-muted">{mute.user_id}</div>
                  </td>
                  <td>{muted_by_label(mute)}</td>
                  <td>
                    <span class="badge badge-sm">{mute.scope}</span>
                    <div :if={mute.scope_ref_id} class="font-mono text-xs text-muted">
                      {mute.scope_ref_id}
                    </div>
                  </td>
                  <td class="text-sm max-w-xs truncate">{mute.reason}</td>
                  <td class="text-xs">
                    <%= if mute.expires_at do %>
                      <.timestamp at={mute.expires_at} format="full" />
                    <% else %>
                      <span class="badge badge-error badge-xs">{gettext("Permanent")}</span>
                    <% end %>
                  </td>
                  <td class="text-right">
                    <div class="flex justify-end gap-1">
                      <button
                        phx-click="edit"
                        phx-value-id={mute.id}
                        class="btn btn-outline btn-info btn-xs"
                      >
                        {gettext("Edit")}
                      </button>
                      <button
                        phx-click="unmute"
                        phx-value-id={mute.id}
                        data-confirm={gettext("Unmute this player?")}
                        class="btn btn-outline btn-error btn-xs"
                      >
                        {gettext("Unmute")}
                      </button>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <div :if={@mutes == []} class="text-center py-8 text-muted">
            {gettext("No mutes.")}
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

      <div :if={@edit_form} class="modal modal-open">
        <div class="modal-box">
          <h3 class="font-bold text-lg">{gettext("Edit mute")}</h3>
          <p class="text-sm text-muted mt-1">
            {user_display(@edit_mute.user)}
            <span class="badge badge-sm ml-1">{@edit_mute.scope}</span>
          </p>

          <form
            phx-submit="save_edit"
            phx-change="edit_change"
            phx-no-unused-field
            id="chat-mute-edit-form"
            class="mt-3 space-y-2"
          >
            <div>
              <label class="label text-xs">{gettext("Duration")}</label>
              <select name="duration" class="select select-bordered select-sm w-full">
                <option
                  :for={{value, label} <- edit_duration_options()}
                  value={value}
                  selected={@edit_form["duration"] == value}
                >
                  {label}
                </option>
              </select>
            </div>

            <div>
              <label class="label text-xs">{gettext("Reason")}</label>
              <input
                type="text"
                name="reason"
                value={@edit_form["reason"]}
                class="input input-bordered input-sm w-full"
              />
            </div>

            <div>
              <label class="label cursor-pointer justify-start gap-2 text-xs">
                <input type="hidden" name="notify" value="false" />
                <input
                  type="checkbox"
                  name="notify"
                  value="true"
                  checked={@edit_form["notify"] == "true"}
                  class="checkbox checkbox-sm"
                />
                {gettext("Notify the player")}
              </label>
              <textarea
                name="notify_message"
                rows="3"
                class="textarea textarea-bordered textarea-sm w-full"
              ><%= @edit_form["notify_message"] %></textarea>
            </div>

            <p :if={@edit_error} class="text-error text-xs">{@edit_error}</p>

            <div class="modal-action">
              <button type="button" phx-click="cancel_edit" class="btn btn-sm">
                {gettext("Cancel")}
              </button>
              <button type="submit" class="btn btn-primary btn-sm">{gettext("Save")}</button>
            </div>
          </form>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
