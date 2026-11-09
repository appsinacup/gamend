defmodule GamendWeb.AdminLive.ChatReports do
  @moduledoc """
  The chat report queue: what players — and the word filter — reported, newest
  first. A moderator claims a report for review, then dismisses it, warns the
  player, deletes the message or mutes the player; every action resolves the
  report and can notify both the player and the reporter.
  """
  use GamendWeb, :live_view

  alias Gamend.Accounts.Scope
  alias Gamend.Bans.Ban
  alias Gamend.Chat
  alias Gamend.Chat.Moderation.Notices
  alias Gamend.Chat.Report
  alias GamendWeb.AdminLive.BanForm
  alias GamendWeb.AdminLive.Shared
  alias GamendWeb.LiveHelpers

  @form_keys ~w(duration scope scope_ref_id reason message notify_user notify_reporter
                reporter_message)

  require GamendWeb.AdminLive.ChatReportAction, as: ChatReportAction
  require GamendWeb.AdminLive.BanDuration, as: BanDuration
  require GamendWeb.UrlParam, as: UrlParam

  use GamendWeb.UrlState,
    reload: :reload,
    keys: [
      :page,
      :page_size,
      status_filter: [param: UrlParam.status()],
      user_filter: [param: UrlParam.reported_user_id()]
    ]

  require Gamend.Bans.BanScope, as: BanScope
  require Gamend.Chat.ChatReportStatus, as: ChatReportStatus

  @warn ChatReportAction.warn()
  @permanent BanDuration.permanent()

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Admin · Chat reports")
      |> assign(:page, 1)
      |> assign(:page_size, 25)
      |> assign(:status_filter, "")
      |> assign(:user_filter, "")
      |> close_form()
      |> reload()

    {:ok, socket}
  end

  @impl true
  def handle_event("filter", params, socket) do
    {:noreply,
     socket
     |> assign(:status_filter, param(params, UrlParam.status(), ""))
     |> assign(:user_filter, param(params, UrlParam.reported_user_id(), ""))
     |> assign(:page, 1)
     |> reload()}
  end

  def handle_event("filter_user", %{"id" => id}, socket) do
    {:noreply, socket |> assign(:user_filter, id) |> assign(:page, 1) |> reload()}
  end

  def handle_event("prev_page", _params, socket),
    do: {:noreply, socket |> LiveHelpers.prev_page() |> reload()}

  def handle_event("next_page", _params, socket),
    do: {:noreply, socket |> LiveHelpers.next_page() |> reload()}

  def handle_event("page_size", %{"size" => size}, socket),
    do: {:noreply, socket |> LiveHelpers.put_page_size(size) |> reload()}

  def handle_event("refresh", _params, socket), do: {:noreply, reload(socket)}

  def handle_event("review", %{"id" => id}, socket) do
    socket =
      case find_report(socket, id) do
        nil -> put_flash(socket, :error, gettext("Report not found"))
        report -> review(socket, report)
      end

    {:noreply, reload(socket)}
  end

  def handle_event("open_action", %{"id" => id, "action" => action}, socket) do
    socket =
      case find_report(socket, id) do
        nil -> put_flash(socket, :error, gettext("Report not found"))
        report -> open_action(socket, action, report)
      end

    {:noreply, reload(socket)}
  end

  def handle_event("close_action", _params, socket), do: {:noreply, close_form(socket)}

  def handle_event("form_change", params, socket) do
    {:noreply, assign(socket, :form, Map.take(params, @form_keys))}
  end

  def handle_event("submit_action", params, socket) do
    form = Map.take(params, @form_keys)
    socket = socket |> assign(:form, form) |> assign(:form_error, nil)

    socket =
      apply_action(socket, socket.assigns.action, socket.assigns.action_report, form)

    {:noreply, reload(socket)}
  end

  # ── actions ───────────────────────────────────────────────────────────────

  defp review(socket, report) do
    case Chat.review_report(report) do
      {:ok, _report} -> put_flash(socket, :info, gettext("Report under review"))
      {:error, _reason} -> put_flash(socket, :error, gettext("Could not claim the report"))
    end
  end

  # A filter-filed report has nobody to reply to, so dismiss and delete have
  # nothing to compose and run in the same click.
  defp open_action(socket, action, %Report{reporter_id: nil} = report)
       when action in ~w(dismiss delete_message) do
    apply_action(socket, action, report, %{})
  end

  defp open_action(socket, action, report) do
    socket
    |> assign(:action, action)
    |> assign(:action_report, report)
    |> assign(:form, new_form(action, report))
    |> assign(:form_error, nil)
  end

  defp apply_action(socket, ChatReportAction.dismiss(), report, form) do
    finish(
      socket,
      report,
      form,
      ChatReportStatus.dismissed(),
      gettext("Dismissed from the report queue"),
      gettext("Report dismissed")
    )
  end

  defp apply_action(socket, ChatReportAction.delete_message(), report, form) do
    case delete_message(report.message_id) do
      {:error, reason} when reason != :not_found ->
        put_flash(socket, :error, gettext("Could not delete the message"))

      _gone ->
        finish(
          socket,
          report,
          form,
          ChatReportStatus.actioned(),
          gettext("Message deleted from the report queue"),
          gettext("Message deleted")
        )
    end
  end

  defp apply_action(socket, @warn, report, form) do
    message = notice(form["message"], Notices.default_warning_message(report.content_snapshot))
    Notices.notify_warning(report.reported_user_id, message)

    finish(
      socket,
      report,
      form,
      ChatReportStatus.actioned(),
      gettext("Warned from the report queue"),
      gettext("Player warned")
    )
  end

  defp apply_action(socket, ChatReportAction.mute(), report, form) do
    scope = form["scope"] || BanScope.global()
    scope_ref_id = Gamend.Parse.blank_to_nil(String.trim(form["scope_ref_id"] || ""))

    if scope != BanScope.global() and is_nil(scope_ref_id) do
      assign(socket, :form_error, gettext("A scoped mute needs the lobby, group or party id."))
    else
      mute(socket, report, form, scope, scope_ref_id)
    end
  end

  # Placed as a chat ban through the console's one ban form, which also sends
  # the player the notice when asked.
  defp mute(socket, report, form, scope, scope_ref_id) do
    ban_form =
      Map.merge(form, %{
        "scope" => scope,
        "scope_ref_id" => scope_ref_id || "",
        "notify" => form["notify_user"]
      })

    case BanForm.place(:chat, report.reported_user_id, ban_form, admin_id(socket)) do
      {:ok, _mute} ->
        finish(
          socket,
          report,
          form,
          ChatReportStatus.actioned(),
          gettext("Muted from the report queue"),
          gettext("Player muted")
        )

      {:error, _reason} ->
        put_flash(socket, :error, gettext("Could not mute the player"))
    end
  end

  defp finish(socket, report, form, status, note, message) do
    attrs = %{"note" => note, "resolved_by" => admin_id(socket)}

    case Chat.resolve_report(report, status, attrs) do
      {:ok, _report} ->
        notify_reporter(report, form, status)
        socket |> put_flash(:info, message) |> close_form()

      {:error, _reason} ->
        put_flash(socket, :error, gettext("Could not resolve the report"))
    end
  end

  defp notify_reporter(%Report{reporter_id: nil}, _form, _status), do: :ok

  defp notify_reporter(report, form, status) do
    if form["notify_reporter"] == "true" do
      Notices.notify_reporter(
        report.reporter_id,
        notice(form["reporter_message"], Notices.default_reporter_message(status))
      )
    end

    :ok
  end

  defp notice(value, default), do: Gamend.Parse.blank_to_nil(String.trim(value || "")) || default

  # ── form ──────────────────────────────────────────────────────────────────

  defp new_form(ChatReportAction.mute(), report) do
    %{
      "duration" => @permanent,
      "scope" => BanScope.global(),
      "scope_ref_id" => "",
      "reason" => gettext("Chat report %{id}", id: report.id),
      "message" => "",
      "notify_user" => "true"
    }
    |> reporter_defaults(report, ChatReportStatus.actioned())
  end

  defp new_form(@warn, report) do
    %{"message" => Notices.default_warning_message(report.content_snapshot)}
    |> reporter_defaults(report, ChatReportStatus.actioned())
  end

  defp new_form(ChatReportAction.dismiss(), report),
    do: reporter_defaults(%{}, report, ChatReportStatus.dismissed())

  defp new_form(_delete_message, report),
    do: reporter_defaults(%{}, report, ChatReportStatus.actioned())

  defp reporter_defaults(form, %Report{reporter_id: nil}, _status), do: form

  defp reporter_defaults(form, _report, status) do
    Map.merge(form, %{
      "notify_reporter" => "true",
      "reporter_message" => Notices.default_reporter_message(status)
    })
  end

  defp close_form(socket) do
    socket
    |> assign(:action, nil)
    |> assign(:action_report, nil)
    |> assign(:form, nil)
    |> assign(:form_error, nil)
  end

  defp action_title(ChatReportAction.mute()), do: gettext("Mute player")
  defp action_title(@warn), do: gettext("Warn player")
  defp action_title(ChatReportAction.dismiss()), do: gettext("Dismiss report")
  defp action_title(_delete_message), do: gettext("Delete message")

  # ── data ──────────────────────────────────────────────────────────────────

  defp reload(socket) do
    filters = %{
      "status" => Gamend.Parse.blank_to_nil(socket.assigns.status_filter),
      "reported_user_id" => Gamend.Parse.blank_to_nil(socket.assigns.user_filter)
    }

    reports =
      Chat.list_reports(filters,
        page: socket.assigns.page,
        page_size: socket.assigns.page_size
      )

    total = Chat.count_reports(filters)

    socket
    |> assign(:reports, reports)
    |> assign(:count, total)
    |> assign(:total_pages, LiveHelpers.total_pages(total, socket.assigns.page_size))
  end

  # The message row is gone the moment it is deleted, and `message_id` is
  # nilified with it — either way the report still resolves as actioned.
  defp delete_message(nil), do: {:error, :not_found}
  defp delete_message(message_id), do: Chat.admin_delete_message(message_id)

  defp find_report(socket, id), do: Enum.find(socket.assigns.reports, &(&1.id == id))

  defp admin_id(socket), do: Scope.user_id(socket.assigns.current_scope)

  defp param(params, key, default) do
    case Map.get(params, key) do
      value when is_binary(value) -> String.trim(value)
      _other -> default
    end
  end

  defp reporter_name(%Report{reporter_id: nil}), do: gettext("Filter")
  defp reporter_name(%Report{reporter: reporter}), do: user_display(reporter)

  defp status_class(ChatReportStatus.open()), do: "badge-warning"
  defp status_class(ChatReportStatus.reviewing()), do: "badge-info"
  defp status_class(ChatReportStatus.actioned()), do: "badge-error"
  defp status_class(_status), do: "badge-ghost"

  defp age(%DateTime{} = at) do
    case DateTime.diff(DateTime.utc_now(), at, :second) do
      seconds when seconds < 60 -> gettext("just now")
      seconds when seconds < 3600 -> gettext("%{count}m ago", count: div(seconds, 60))
      seconds when seconds < 86_400 -> gettext("%{count}h ago", count: div(seconds, 3600))
      seconds -> gettext("%{count}d ago", count: div(seconds, 86_400))
    end
  end

  # ── render ────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <.admin_header page="/admin/chat/reports" />

      <div class="card bg-base-200">
        <div class="card-body">
          <div class="flex flex-wrap items-center justify-between gap-2">
            <h2 class="card-title">{gettext("Chat reports")} ({@count})</h2>
            <button phx-click="refresh" class="btn btn-ghost btn-sm">{gettext("Refresh")}</button>
          </div>

          <p class="text-sm text-muted">
            {gettext(
              "Reports players filed about a chat message, plus the ones the word filter files itself. Acting on a report resolves it."
            )}
          </p>

          <form
            phx-change="filter"
            phx-no-unused-field
            id="chat-reports-filter-form"
            class="flex flex-wrap gap-2 my-2"
          >
            <select name="status" class="select select-sm">
              <option value="">{gettext("All")}</option>
              <option
                :for={status <- Report.statuses()}
                value={status}
                selected={@status_filter == status}
              >
                {status}
              </option>
            </select>
            <input
              type="text"
              name="reported_user_id"
              value={@user_filter}
              placeholder={gettext("Filter by reported user ID")}
              phx-debounce="300"
              class="input input-sm w-80 font-mono"
            />
          </form>

          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>{gettext("Reported")}</th>
                  <th>{gettext("Reporter")}</th>
                  <th>{gettext("Message")}</th>
                  <th>{gettext("Reason")}</th>
                  <th>{gettext("Status")}</th>
                  <th>{gettext("Age")}</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={report <- @reports} id={"chat-report-#{report.id}"}>
                  <td>
                    <div class="flex items-center gap-2">
                      <.user_avatar user={report.reported_user} class="size-6 shrink-0" />
                      <div>
                        <button
                          phx-click="filter_user"
                          phx-value-id={report.reported_user_id}
                          class="link link-hover"
                        >
                          {user_display(report.reported_user)}
                        </button>
                        <div class="font-mono text-xs text-muted">
                          {report.reported_user_id}
                        </div>
                      </div>
                    </div>
                  </td>
                  <td>
                    <div class="flex items-center gap-2">
                      <.user_avatar
                        :if={report.reporter_id}
                        user={report.reporter}
                        class="size-6 shrink-0"
                      />
                      {reporter_name(report)}
                    </div>
                  </td>
                  <td class="max-w-xs truncate" title={report.content_snapshot}>
                    {report.content_snapshot}
                  </td>
                  <td class="max-w-xs truncate text-xs" title={report.reason}>{report.reason}</td>
                  <td>
                    <span class={["badge badge-sm", status_class(report.status)]}>
                      {report.status}
                    </span>
                    <div
                      :if={report.resolved_by_user}
                      class="flex items-center gap-1 text-xs text-muted"
                    >
                      {gettext("by")}
                      <.user_avatar user={report.resolved_by_user} class="size-4 shrink-0" />
                      {user_display(report.resolved_by_user)}
                    </div>
                  </td>
                  <td class="text-xs whitespace-nowrap">
                    {age(report.inserted_at)}
                    <div class="text-muted">
                      <.timestamp at={report.inserted_at} format="full" />
                    </div>
                  </td>
                  <td class="text-right whitespace-nowrap">
                    <div :if={report.status in ~w(open reviewing)} class="flex justify-end gap-1">
                      <button
                        :if={report.status == ChatReportStatus.open()}
                        phx-click="review"
                        phx-value-id={report.id}
                        class="btn btn-ghost btn-xs"
                      >
                        {gettext("Review")}
                      </button>
                      <button
                        phx-click="open_action"
                        phx-value-action={ChatReportAction.dismiss()}
                        phx-value-id={report.id}
                        class="btn btn-ghost btn-xs"
                      >
                        {gettext("Dismiss")}
                      </button>
                      <button
                        phx-click="open_action"
                        phx-value-action={ChatReportAction.warn()}
                        phx-value-id={report.id}
                        class="btn btn-surface btn-xs"
                      >
                        {gettext("Warn")}
                      </button>
                      <%!-- With a reporter to answer, the modal is the confirm step. --%>
                      <button
                        phx-click="open_action"
                        phx-value-action={ChatReportAction.delete_message()}
                        phx-value-id={report.id}
                        data-confirm={is_nil(report.reporter_id)}
                        class="btn btn-outline btn-error btn-xs"
                      >
                        {gettext("Delete message")}
                      </button>
                      <button
                        phx-click="open_action"
                        phx-value-action={ChatReportAction.mute()}
                        phx-value-id={report.id}
                        class="btn btn-outline btn-warning btn-xs"
                      >
                        {gettext("Mute player")}
                      </button>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <div :if={@reports == []} class="text-center py-8 text-muted">
            {gettext("No reports.")}
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

      <div :if={@form} class="modal modal-open">
        <div class="modal-box">
          <h3 class="font-bold text-lg">{action_title(@action)}</h3>
          <p class="flex items-center gap-2 text-sm text-muted mt-1">
            <.user_avatar user={@action_report.reported_user} class="size-6 shrink-0" />
            {user_display(@action_report.reported_user)}
          </p>

          <form
            phx-submit="submit_action"
            phx-change="form_change"
            phx-no-unused-field
            id="chat-report-action-form"
            class="mt-3 space-y-3"
          >
            <div :if={@action == ChatReportAction.mute()} class="flex flex-wrap gap-2">
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
              <div>
                <label class="label text-xs">{gettext("Scope")}</label>
                <select name="scope" class="select select-bordered select-sm">
                  <option
                    :for={scope <- Ban.scopes()}
                    value={scope}
                    selected={@form["scope"] == scope}
                  >
                    {scope}
                  </option>
                </select>
              </div>
            </div>

            <div :if={@action == ChatReportAction.mute() and @form["scope"] != BanScope.global()}>
              <label class="label text-xs">{gettext("Lobby / group / party id")}</label>
              <input
                type="text"
                name="scope_ref_id"
                value={@form["scope_ref_id"]}
                required
                class="input input-bordered input-sm w-full font-mono"
              />
            </div>

            <div :if={@action == ChatReportAction.mute()}>
              <label class="label text-xs">{gettext("Reason")}</label>
              <input
                type="text"
                name="reason"
                value={@form["reason"]}
                class="input input-bordered input-sm w-full"
              />
            </div>

            <div :if={@action == ChatReportAction.mute()}>
              <label class="label cursor-pointer justify-start gap-2 text-sm">
                <input
                  type="checkbox"
                  name="notify_user"
                  value="true"
                  checked={@form["notify_user"] == "true"}
                  class="checkbox checkbox-sm"
                />
                {gettext("Notify the player")}
              </label>
            </div>

            <div :if={@action in [ChatReportAction.mute(), ChatReportAction.warn()]}>
              <label class="label text-xs">{gettext("Message to the player")}</label>
              <textarea
                name="message"
                rows="3"
                placeholder={gettext("Blank sends the default notice")}
                class="textarea textarea-bordered w-full text-sm"
              >{@form["message"]}</textarea>
            </div>

            <div :if={@action_report.reporter_id}>
              <label class="label cursor-pointer justify-start gap-2 text-sm">
                <input
                  type="checkbox"
                  name="notify_reporter"
                  value="true"
                  checked={@form["notify_reporter"] == "true"}
                  class="checkbox checkbox-sm"
                />
                {gettext("Notify the reporter")}
              </label>
              <textarea
                name="reporter_message"
                rows="3"
                placeholder={gettext("Blank sends the default notice")}
                class="textarea textarea-bordered w-full text-sm"
              >{@form["reporter_message"]}</textarea>
            </div>

            <p :if={@form_error} class="text-error text-xs">{@form_error}</p>

            <div class="modal-action">
              <button type="button" phx-click="close_action" class="btn btn-sm">
                {gettext("Cancel")}
              </button>
              <button type="submit" class="btn btn-primary btn-sm">
                {action_title(@action)}
              </button>
            </div>
          </form>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
