defmodule GamendWeb.AdminLive.Retention do
  @moduledoc """
  Admin view over data retention: the configured per-class windows, what the
  last sweep pruned, and a manual "run now".
  """
  use GamendWeb, :live_view

  alias Gamend.Settings

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-6">
        <.link navigate={~p"/admin"} class="btn btn-surface mb-4">&larr; Back to Admin</.link>

        <%!-- Last sweep --%>
        <div class="card bg-base-200 shadow">
          <div class="card-body">
            <div class="flex flex-col md:flex-row md:items-center md:justify-between gap-4">
              <div>
                <h2 class="card-title text-lg">Data Retention</h2>
                <p class="text-sm text-muted">
                  Sweeps every 6 hours. Windows are set per class with
                  <code class="text-xs">GAMEND_RETENTION_*</code>
                  env vars (client log sessions with <code class="text-xs">GAMEND_CLIENT_LOGS_RETENTION_*</code>).
                  A window of 0 usually keeps that class forever; each setting's
                  description below says what 0 does for it.
                </p>
              </div>
              <div class="flex items-center gap-3">
                <div class="text-right">
                  <div class="text-xs text-muted">Last run</div>
                  <div class="text-sm font-mono">
                    <.timestamp at={@retention.last_run_at} format="full" empty="never" />
                  </div>
                </div>
                <button phx-click="prune_now" class="btn btn-primary" disabled={@retention_running}>
                  {if @retention_running, do: "Running...", else: "Run now"}
                </button>
              </div>
            </div>

            <div :if={@retention.last_run_at} class="overflow-x-auto mt-2">
              <table class="table table-sm">
                <thead>
                  <tr>
                    <th>Class</th>
                    <th class="text-right">Rows affected</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={{class, count} <- @retention_rows} id={"retention-#{class}"}>
                    <td class="font-mono text-xs">{class}</td>
                    <td class="text-right font-mono">{count}</td>
                  </tr>
                </tbody>
              </table>
              <div class="text-xs text-muted mt-1">
                Took {@retention.duration_ms} ms. Classes that affected no rows are hidden.
                Most classes delete rows; a few release seats or send warnings instead.
              </div>
            </div>
          </div>
        </div>

        <%!-- Configured windows --%>
        <div class="card bg-base-200 shadow">
          <div class="card-body">
            <h2 class="card-title text-lg">Configured Windows</h2>
            <p class="text-xs text-muted mb-2">
              Every declared retention setting, client log sessions included, with its
              effective value. Values marked default were never configured by the host.
            </p>
            <div class="overflow-x-auto">
              <table class="table table-sm">
                <thead>
                  <tr>
                    <th>Setting</th>
                    <th class="text-right">Value</th>
                    <th>Description</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={window <- @windows} id={"window-#{window.key}"}>
                    <td class="font-mono text-xs">{window.env}</td>
                    <td class="text-right font-mono">
                      {window.value}
                      <span :if={window.source == :default} class="badge badge-ghost badge-xs ml-1">
                        default
                      </span>
                    </td>
                    <td class="text-xs text-muted">{window.doc}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Admin · Retention")
     |> assign(:retention_running, false)
     |> assign(:windows, Enum.map(retention_settings(), &Settings.describe/1))
     |> assign_retention()}
  end

  @impl true
  def handle_event("prune_now", _params, socket) do
    # Off the LiveView process: a sweep with a backlog can take minutes, and
    # the page must stay live while it runs.
    parent = self()
    Task.start(fn -> send(parent, {:pruned, run_sweep()}) end)

    {:noreply, assign(socket, :retention_running, true)}
  end

  @impl true
  def handle_info({:pruned, {:ok, results}}, socket) do
    affected = results |> Map.values() |> Enum.sum()

    {:noreply,
     socket
     |> assign(:retention_running, false)
     |> assign_retention()
     |> put_flash(
       :info,
       ngettext(
         "Retention sweep affected %{count} row.",
         "Retention sweep affected %{count} rows.",
         affected
       )
     )}
  end

  def handle_info({:pruned, :unavailable}, socket) do
    {:noreply,
     socket
     |> assign(:retention_running, false)
     |> put_flash(:error, "Retention sweeper is not running.")}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  # The button must resolve either way: a sweeper that is down or dies mid-run
  # would otherwise leave the page stuck on "Running...".
  defp run_sweep do
    {:ok, Gamend.Retention.run_now()}
  catch
    :exit, _reason -> :unavailable
  end

  # The sweep also prunes client log sessions, on `Gamend.ClientLogs`'s own
  # settings rather than a retention one, so the group alone left them out.
  defp retention_settings do
    Settings.group(:retention) ++
      Enum.filter(
        Settings.group(:client_logs),
        &(&1.key in [:retention_days, :retention_flagged_days])
      )
  end

  defp assign_retention(socket) do
    status = Gamend.Retention.status()

    socket
    |> assign(:retention, status)
    |> assign(:retention_rows, Enum.sort(for {class, n} <- status.results, n > 0, do: {class, n}))
  end
end
