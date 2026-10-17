defmodule GamendWeb.AdminLive.Reports do
  @moduledoc """
  The content report queue (`Gamend.Reports`): what players reported about
  pages, words and anything else a report kind covers, open ones first.

  Each report shows how many open reports share its subject, so twelve people
  flagging one word reads as one problem. Closing a report (fixed, won't fix,
  duplicate) can send the reporter a reply when they had an account; a kind
  whose fixes happen elsewhere offers an export of what the filter shows.
  """
  use GamendWeb, :live_view

  alias Gamend.Accounts.Scope
  alias Gamend.Reports
  alias Gamend.Reports.Notices
  alias Gamend.Reports.Report
  alias GamendWeb.LiveHelpers
  alias GamendWeb.Reports.KindUI

  @closing ~w(fixed wontfix duplicate)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Admin · Reports")
     |> assign(:page, 1)
     |> assign(:page_size, 25)
     |> assign(:filters, %{"status" => "open", "kind" => "", "topic" => "", "q" => ""})
     |> assign(:kinds, Reports.kinds())
     |> close_form()
     |> reload()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filters =
      Enum.reduce(~w(status kind topic q subject_ref), socket.assigns.filters, fn key, acc ->
        case params[key] do
          value when is_binary(value) -> Map.put(acc, key, String.trim(value))
          _ -> acc
        end
      end)

    {:noreply, socket |> assign(:filters, filters) |> assign(:page, 1) |> reload()}
  end

  @impl true
  def handle_event("filter", params, socket) do
    filters =
      socket.assigns.filters
      |> Map.merge(Map.take(params, ~w(status kind topic q)))
      |> Map.delete("subject_ref")

    # A topic belongs to a kind; switching kinds drops it.
    filters =
      if filters["kind"] != socket.assigns.filters["kind"],
        do: Map.put(filters, "topic", ""),
        else: filters

    {:noreply, socket |> assign(:filters, filters) |> assign(:page, 1) |> reload()}
  end

  def handle_event("group", %{"kind" => kind, "topic" => topic, "ref" => ref}, socket) do
    filters = %{
      "status" => "open",
      "kind" => kind,
      "topic" => topic,
      "q" => "",
      "subject_ref" => ref
    }

    {:noreply, socket |> assign(:filters, filters) |> assign(:page, 1) |> reload()}
  end

  def handle_event("prev_page", _params, socket),
    do: {:noreply, socket |> LiveHelpers.prev_page() |> reload()}

  def handle_event("next_page", _params, socket),
    do: {:noreply, socket |> LiveHelpers.next_page() |> reload()}

  def handle_event("page_size", %{"size" => size}, socket),
    do: {:noreply, socket |> LiveHelpers.put_page_size(size) |> reload()}

  def handle_event("refresh", _params, socket), do: {:noreply, reload(socket)}

  def handle_event("open_close", %{"id" => id, "status" => status}, socket)
      when status in @closing do
    case find(socket, id) do
      nil ->
        {:noreply, put_flash(socket, :error, gettext("Report not found"))}

      report ->
        label = KindUI.subject_label(ui_for(report), report)

        {:noreply,
         socket
         |> assign(:action_report, report)
         |> assign(:form, %{
           "status" => status,
           "note" => "",
           "notify" => if(report.user_id, do: "true", else: "false"),
           "message" => Notices.default_reporter_message(status, label)
         })}
    end
  end

  def handle_event("close_form", _params, socket), do: {:noreply, close_form(socket)}

  def handle_event("form_change", params, socket) do
    {:noreply, update(socket, :form, &Map.merge(&1, Map.take(params, ~w(note notify message))))}
  end

  def handle_event("submit_close", params, socket) do
    report = socket.assigns.action_report
    form = Map.merge(socket.assigns.form, Map.take(params, ~w(note notify message)))
    message = if form["notify"] == "true", do: form["message"], else: nil

    socket =
      case Reports.resolve(report, form["status"], %{
             "note" => form["note"],
             "message" => message,
             "resolved_by" => Scope.user_id(socket.assigns.current_scope)
           }) do
        {:ok, _report} -> socket |> close_form() |> put_flash(:info, gettext("Report closed"))
        {:error, _reason} -> put_flash(socket, :error, gettext("Could not close the report"))
      end

    {:noreply, reload(socket)}
  end

  def handle_event("reopen", %{"id" => id}, socket) do
    socket =
      with %Report{} = report <- find(socket, id),
           {:ok, _report} <- Reports.resolve(report, "open") do
        put_flash(socket, :info, gettext("Report reopened"))
      else
        _ -> put_flash(socket, :error, gettext("Could not reopen the report"))
      end

    {:noreply, reload(socket)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    socket =
      with %Report{} = report <- find(socket, id),
           {:ok, _report} <- Reports.delete(report) do
        put_flash(socket, :info, gettext("Report deleted"))
      else
        _ -> put_flash(socket, :error, gettext("Could not delete the report"))
      end

    {:noreply, reload(socket)}
  end

  # ── data ─────────────────────────────────────────────────────────────────

  defp reload(socket) do
    filters = socket.assigns.filters

    reports =
      Reports.list(filters, page: socket.assigns.page, page_size: socket.assigns.page_size)

    total = Reports.count(filters)

    socket
    |> assign(:reports, reports)
    |> assign(:groups, Reports.group_counts(reports))
    |> assign(:count, total)
    |> assign(:by_status, Reports.count_by_status())
    |> assign(:total_pages, LiveHelpers.total_pages(total, socket.assigns.page_size))
  end

  defp close_form(socket), do: socket |> assign(:form, nil) |> assign(:action_report, nil)

  defp find(socket, id), do: Enum.find(socket.assigns.reports, &(&1.id == id))

  defp ui_for(%Report{kind: kind}) do
    case Reports.kind(kind) do
      nil -> nil
      mod -> Reports.ui(mod)
    end
  end

  defp selected_kind(filters), do: Reports.kind(filters["kind"])

  defp export_path(filters) do
    query =
      filters
      |> Map.take(~w(status topic q subject_ref))
      |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)

    "/admin/reports/export/#{filters["kind"]}?" <> URI.encode_query(query)
  end

  defp status_class("open"), do: "badge-warning"
  defp status_class("fixed"), do: "badge-success"
  defp status_class(_status), do: "badge-ghost"

  defp user_label(%{user: %Gamend.Accounts.User{} = user}), do: user_display(user)
  defp user_label(_report), do: gettext("Visitor")

  defp age(%DateTime{} = at) do
    case DateTime.diff(DateTime.utc_now(), at, :second) do
      seconds when seconds < 60 -> gettext("just now")
      seconds when seconds < 3600 -> gettext("%{count}m ago", count: div(seconds, 60))
      seconds when seconds < 86_400 -> gettext("%{count}h ago", count: div(seconds, 3600))
      seconds -> gettext("%{count}d ago", count: div(seconds, 86_400))
    end
  end

  # ── render ───────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <.link navigate={~p"/admin"} class="btn btn-surface mb-4">
        ← {gettext("Back to Admin")}
      </.link>

      <div class="card bg-base-200">
        <div class="card-body space-y-3">
          <div class="flex flex-wrap items-center justify-between gap-2">
            <h2 class="card-title">{gettext("Reports")} ({@count})</h2>
            <div class="flex gap-2">
              <.link
                :if={selected_kind(@filters) && KindUI.export?(Reports.ui(selected_kind(@filters)))}
                href={export_path(@filters)}
                class="btn btn-surface btn-sm"
              >
                <.icon name="hero-arrow-down-tray" class="size-4" /> {gettext("Export")}
              </.link>
              <button phx-click="refresh" class="btn btn-ghost btn-sm">{gettext("Refresh")}</button>
            </div>
          </div>

          <p class="text-sm text-muted">
            {gettext(
              "What players reported about pages and content, from /report and the game. Open: %{open}, fixed: %{fixed}.",
              open: Map.get(@by_status, "open", 0),
              fixed: Map.get(@by_status, "fixed", 0)
            )}
          </p>

          <form
            phx-change="filter"
            phx-submit="filter"
            phx-no-unused-field
            id="reports-filter-form"
            class="flex flex-wrap gap-2"
          >
            <select name="status" class="select select-sm">
              <option value="">{gettext("Any status")}</option>
              <option
                :for={status <- Report.statuses()}
                value={status}
                selected={@filters["status"] == status}
              >
                {status}
              </option>
            </select>
            <select name="kind" class="select select-sm">
              <option value="">{gettext("Any kind")}</option>
              <option
                :for={kind <- @kinds}
                value={kind.key()}
                selected={@filters["kind"] == kind.key()}
              >
                {kind.key()}
              </option>
            </select>
            <select
              :if={selected_kind(@filters) && selected_kind(@filters).topics() != []}
              name="topic"
              class="select select-sm"
            >
              <option value="">{gettext("Any topic")}</option>
              <option
                :for={topic <- selected_kind(@filters).topics()}
                value={topic}
                selected={@filters["topic"] == topic}
              >
                {topic}
              </option>
            </select>
            <input
              type="search"
              name="q"
              value={@filters["q"]}
              placeholder={gettext("Search text, subject or email")}
              phx-debounce="300"
              class="input input-sm w-72"
            />
            <button
              :if={@filters["subject_ref"]}
              type="button"
              phx-click="filter"
              phx-value-status={@filters["status"]}
              class="btn btn-ghost btn-sm"
            >
              {@filters["subject_ref"]} <.icon name="hero-x-mark" class="size-4" />
            </button>
          </form>

          <div :if={@reports == []} class="py-8 text-center text-muted">
            {gettext("No reports.")}
          </div>

          <div class="space-y-3">
            <article
              :for={report <- @reports}
              id={"report-#{report.id}"}
              class="rounded-box border border-base-300 bg-base-100 p-4 space-y-3"
            >
              <div class="flex flex-wrap items-center gap-2 text-sm">
                <span class="badge badge-sm badge-neutral">{report.kind}</span>
                <span :if={report.topic} class="badge badge-sm badge-outline">
                  {KindUI.topic_label(ui_for(report), report.topic)}
                </span>
                <span class={["badge badge-sm", status_class(report.status)]}>{report.status}</span>
                <button
                  :if={(@groups[Reports.group_key(report)] || 0) > 1}
                  type="button"
                  phx-click="group"
                  phx-value-kind={report.kind}
                  phx-value-topic={report.topic || ""}
                  phx-value-ref={report.subject_ref}
                  class="badge badge-sm badge-error"
                  title={gettext("Show the open reports on this")}
                >
                  ×{@groups[Reports.group_key(report)]}
                </button>
                <span class="text-muted">
                  {age(report.inserted_at)} · <.timestamp at={report.inserted_at} format="full" />
                </span>
              </div>

              <div>
                <%= if KindUI.admin_subject?(ui_for(report)) do %>
                  {ui_for(report).admin_subject(%{report: report})}
                <% else %>
                  <span class="font-mono text-sm">{report.subject_ref}</span>
                <% end %>
              </div>

              <dl :if={report.data != %{}} class="grid grid-cols-[auto_1fr] gap-x-3 text-sm">
                <%= for {key, value} <- report.data do %>
                  <dt class="text-muted">{key}</dt>
                  <dd class="break-words">{value}</dd>
                <% end %>
              </dl>

              <p :if={report.description} class="whitespace-pre-line break-words">
                {report.description}
              </p>

              <div :if={Report.files(report) != []} class="flex flex-wrap gap-2">
                <a
                  :for={{_file, n} <- Enum.with_index(Report.files(report), 1)}
                  href={"/admin/reports/#{report.id}/attachments/#{n}"}
                  target="_blank"
                >
                  <img
                    src={"/admin/reports/#{report.id}/attachments/#{n}"}
                    alt={gettext("Screenshot %{n}", n: n)}
                    loading="lazy"
                    class="h-32 rounded-box border border-base-300 object-contain"
                  />
                </a>
              </div>

              <div class="flex flex-wrap gap-x-4 gap-y-1 text-xs text-muted">
                <span>
                  {user_label(report)}
                  <span :if={report.user_id} class="font-mono">{report.user_id}</span>
                </span>
                <a :if={report.email} href={"mailto:" <> report.email} class="link">{report.email}</a>
                <span :if={report.locale}>{report.locale}</span>
                <span>{report.source}</span>
                <span :if={report.client["viewport"]}>{report.client["viewport"]}</span>
                <span
                  :if={report.client["user_agent"]}
                  class="max-w-md truncate"
                  title={report.client["user_agent"]}
                >
                  {report.client["user_agent"]}
                </span>
              </div>

              <div :if={report.status != "open"} class="text-xs text-muted">
                {gettext("Closed")}
                <span :if={report.resolved_by_user}>
                  {gettext("by")} {user_display(report.resolved_by_user)}
                </span>
                <span :if={report.resolution_note}>— {report.resolution_note}</span>
              </div>

              <div class="flex flex-wrap justify-end gap-1">
                <%= if report.status == "open" do %>
                  <button
                    phx-click="open_close"
                    phx-value-id={report.id}
                    phx-value-status="fixed"
                    class="btn btn-primary btn-xs"
                  >
                    {gettext("Fixed")}
                  </button>
                  <button
                    phx-click="open_close"
                    phx-value-id={report.id}
                    phx-value-status="duplicate"
                    class="btn btn-surface btn-xs"
                  >
                    {gettext("Duplicate")}
                  </button>
                  <button
                    phx-click="open_close"
                    phx-value-id={report.id}
                    phx-value-status="wontfix"
                    class="btn btn-surface btn-xs"
                  >
                    {gettext("Won't fix")}
                  </button>
                <% else %>
                  <button phx-click="reopen" phx-value-id={report.id} class="btn btn-surface btn-xs">
                    {gettext("Reopen")}
                  </button>
                <% end %>
                <button
                  phx-click="delete"
                  phx-value-id={report.id}
                  data-confirm={gettext("Delete this report and its images?")}
                  class="btn btn-outline btn-error btn-xs"
                >
                  {gettext("Delete")}
                </button>
              </div>
            </article>
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
          <h3 class="text-lg font-bold">
            {gettext("Close as %{status}", status: @form["status"])}
          </h3>

          <form
            phx-submit="submit_close"
            phx-change="form_change"
            phx-no-unused-field
            id="report-close-form"
            class="mt-3 space-y-3"
          >
            <div>
              <label class="label text-xs">{gettext("Note (admins only)")}</label>
              <input type="text" name="note" value={@form["note"]} class="input input-sm w-full" />
            </div>

            <div :if={@action_report.user_id}>
              <label class="label cursor-pointer justify-start gap-2 text-sm">
                <input type="hidden" name="notify" value="false" />
                <input
                  type="checkbox"
                  name="notify"
                  value="true"
                  checked={@form["notify"] == "true"}
                  class="checkbox checkbox-sm"
                />
                {gettext("Tell the reporter")}
              </label>
              <textarea name="message" rows="3" class="textarea w-full text-sm">{@form["message"]}</textarea>
            </div>

            <p :if={!@action_report.user_id} class="text-xs text-muted">
              {gettext("Filed without an account: there is nobody to notify.")}
              <a :if={@action_report.email} href={"mailto:" <> @action_report.email} class="link">
                {@action_report.email}
              </a>
            </p>

            <div class="modal-action">
              <button type="button" phx-click="close_form" class="btn btn-sm">
                {gettext("Cancel")}
              </button>
              <button type="submit" class="btn btn-primary btn-sm">{gettext("Close report")}</button>
            </div>
          </form>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
