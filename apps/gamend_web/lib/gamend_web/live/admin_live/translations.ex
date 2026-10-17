defmodule GamendWeb.AdminLive.Translations do
  use GamendWeb, :live_view

  alias GamendWeb.Gettext.Stats, as: TranslationStats
  alias GamendWeb.LiveHelpers

  @impl true
  def mount(_params, _session, socket) do
    locales = TranslationStats.locales()
    first_locale = List.first(locales, "en")
    completeness = TranslationStats.all_completeness()
    domains = TranslationStats.domains(first_locale)

    strings =
      TranslationStats.list_strings(first_locale)

    {:ok,
     socket
     |> assign(:locales, locales)
     |> assign(:completeness, completeness)
     |> assign(:domains, domains)
     |> assign(:selected_locale, first_locale)
     |> assign(:selected_domain, "")
     |> assign(:selected_status, "")
     |> assign(:search, "")
     |> assign(:strings, strings)
     |> assign(:page, 1)
     |> assign(:page_size, 50)}
  end

  @impl true
  def render(assigns) do
    total = length(assigns.strings)
    page_size = assigns.page_size
    page = assigns.page
    total_pages = max(ceil(total / page_size), 1)
    start_idx = (page - 1) * page_size
    page_strings = Enum.slice(assigns.strings, start_idx, page_size)

    assigns =
      assigns
      |> assign(:total, total)
      |> assign(:total_pages, total_pages)
      |> assign(:page_strings, page_strings)

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-6">
        <.link navigate={~p"/admin"} class="btn btn-surface mb-4">&larr; Back to Admin</.link>

        <%!-- Completeness overview --%>
        <div class="card bg-base-200">
          <div class="card-body">
            <h2 class="card-title">Translation Completeness</h2>
            <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mt-2">
              <div
                :for={stats <- @completeness}
                class={[
                  "card p-4 cursor-pointer transition-all hover:shadow-md",
                  if(stats.locale == @selected_locale,
                    do: "bg-primary/10 ring-2 ring-primary",
                    else: "bg-base-100"
                  )
                ]}
                phx-click="select_locale"
                phx-value-locale={stats.locale}
              >
                <div class="flex items-center justify-between mb-2">
                  <span class="font-semibold text-sm">{String.upcase(stats.locale)}</span>
                  <span class={[
                    "text-xs font-bold",
                    if(stats.percent == 100.0, do: "text-success", else: "text-warning")
                  ]}>
                    {stats.percent}%
                  </span>
                </div>
                <div class="w-full bg-base-300 rounded-full h-2">
                  <div
                    class={[
                      "h-2 rounded-full transition-all",
                      if(stats.percent == 100.0, do: "bg-success", else: "bg-warning")
                    ]}
                    style={"width: #{stats.percent}%"}
                  >
                  </div>
                </div>
                <div class="text-xs text-muted mt-1">
                  {stats.translated}/{stats.total} strings
                </div>
              </div>
            </div>
          </div>
        </div>

        <%!-- String browser --%>
        <div class="card bg-base-200">
          <div class="card-body">
            <h2 class="card-title">
              Translation Strings — {String.upcase(@selected_locale)}
              <span class="text-sm font-normal text-muted">({@total} strings)</span>
            </h2>

            <%!-- Filters --%>
            <form phx-change="filter" phx-no-unused-field id="translations-filter-form" class="mt-2">
              <div class="flex flex-wrap gap-3 items-end">
                <div class="form-control w-full sm:w-auto">
                  <label class="label py-0.5">
                    <span class="label-text text-xs">Domain</span>
                  </label>
                  <select
                    name="domain"
                    class="select select-bordered select-sm w-full sm:w-48"
                    id="translations-domain-filter"
                  >
                    <option value="" selected={@selected_domain == ""}>All domains</option>
                    <option :for={d <- @domains} value={d} selected={@selected_domain == d}>
                      {d}
                    </option>
                  </select>
                </div>
                <div class="form-control w-full sm:w-auto">
                  <label class="label py-0.5">
                    <span class="label-text text-xs">Status</span>
                  </label>
                  <select
                    name="status"
                    class="select select-bordered select-sm w-full sm:w-48"
                    id="translations-status-filter"
                  >
                    <option value="" selected={@selected_status == ""}>All</option>
                    <option value="translated" selected={@selected_status == "translated"}>
                      Translated
                    </option>
                    <option value="untranslated" selected={@selected_status == "untranslated"}>
                      Untranslated
                    </option>
                  </select>
                </div>
                <div class="form-control w-full sm:w-auto flex-1">
                  <label class="label py-0.5">
                    <span class="label-text text-xs">Search</span>
                  </label>
                  <input
                    type="text"
                    name="search"
                    value={@search}
                    placeholder="Search msgid or translation…"
                    class="input input-bordered input-sm w-full"
                    phx-debounce="300"
                    id="translations-search-input"
                  />
                </div>
              </div>
            </form>

            <%!-- Table --%>
            <div class="overflow-x-auto mt-4">
              <table class="table table-zebra w-full" id="translations-table">
                <thead>
                  <tr>
                    <th class="w-24">Domain</th>
                    <th>Source (msgid)</th>
                    <th>Translation (msgstr)</th>
                    <th class="w-20">Status</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :if={@page_strings == []} id="translations-empty-row">
                    <td colspan="4" class="text-center text-muted py-8">
                      No strings match the current filters.
                    </td>
                  </tr>
                  <tr :for={s <- @page_strings} id={"str-#{s.domain}-#{:erlang.phash2(s.msgid)}"}>
                    <td class="font-mono text-xs">{s.domain}</td>
                    <td class="text-sm break-all max-w-xs">{s.msgid}</td>
                    <td class={[
                      "text-sm break-all max-w-xs",
                      !s.translated? && "text-muted italic"
                    ]}>
                      {if s.translated?, do: s.msgstr, else: "—"}
                    </td>
                    <td>
                      <span class={[
                        "badge badge-sm",
                        if(s.translated?, do: "badge-success", else: "badge-warning")
                      ]}>
                        {if s.translated?, do: "✓", else: "✗"}
                      </span>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>

            <%!-- Pagination --%>
            <div class="mt-4" id="translations-pagination">
              <.pagination
                page={@page}
                total_pages={@total_pages}
                total_count={@total}
                page_size={@page_size}
                on_prev="prev_page"
                on_next="next_page"
                on_page_size="translations_page_size"
              />
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def handle_event("select_locale", %{"locale" => locale}, socket) do
    domains = TranslationStats.domains(locale)

    strings =
      TranslationStats.list_strings(locale,
        domain: socket.assigns.selected_domain,
        search: socket.assigns.search,
        status: socket.assigns.selected_status
      )

    {:noreply,
     socket
     |> assign(:selected_locale, locale)
     |> assign(:domains, domains)
     |> assign(:strings, strings)
     |> assign(:page, 1)}
  end

  @impl true
  def handle_event("filter", params, socket) do
    domain = Map.get(params, "domain", "")
    search = Map.get(params, "search", "")
    status = Map.get(params, "status", "")

    strings =
      TranslationStats.list_strings(socket.assigns.selected_locale,
        domain: domain,
        search: search,
        status: status
      )

    {:noreply,
     socket
     |> assign(:selected_domain, domain)
     |> assign(:search, search)
     |> assign(:selected_status, status)
     |> assign(:strings, strings)
     |> assign(:page, 1)}
  end

  @impl true
  def handle_event("prev_page", _params, socket),
    do: {:noreply, LiveHelpers.prev_page(socket)}

  # The strings are all in memory, so the page count is derived here rather
  # than stored by a reload.
  @impl true
  def handle_event("next_page", _params, socket) do
    total_pages = ceil(length(socket.assigns.strings) / socket.assigns.page_size)
    {:noreply, socket |> assign(:total_pages, total_pages) |> LiveHelpers.next_page()}
  end

  @impl true
  def handle_event("translations_page_size", %{"size" => size}, socket),
    do: {:noreply, socket |> LiveHelpers.put_page_size(size)}
end
