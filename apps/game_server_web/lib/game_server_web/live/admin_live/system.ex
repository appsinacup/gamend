defmodule GameServerWeb.AdminLive.System do
  use GameServerWeb, :live_view

  alias GameServerWeb.ConnectionTracker

  @refresh_interval 5_000

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-6">
        <.link navigate={~p"/admin"} class="btn btn-outline mb-4">&larr; Back to Admin</.link>

        <%!-- Top-level stats --%>
        <div class="grid grid-cols-2 md:grid-cols-4 xl:grid-cols-6 gap-4">
          <div class="bg-base-100 rounded-lg shadow-sm p-4">
            <div class="text-xs text-base-content/60">Uptime</div>
            <div class="text-xl font-bold">
              {ConnectionTracker.format_uptime(@sys.uptime_seconds)}
            </div>
          </div>
          <div class="bg-base-100 rounded-lg shadow-sm p-4">
            <div class="text-xs text-base-content/60">OTP</div>
            <div class="text-xl font-bold">{@sys.otp_release}</div>
          </div>
          <div class="bg-base-100 rounded-lg shadow-sm p-4">
            <div class="text-xs text-base-content/60">Schedulers</div>
            <div class="text-xl font-bold">{@sys.schedulers}</div>
            <div class="text-xs text-base-content/40">{@scheduler_util}% busy</div>
          </div>
          <div class="bg-base-100 rounded-lg shadow-sm p-4">
            <div class="text-xs text-base-content/60">Node</div>
            <div class="text-sm font-bold font-mono break-all">{@sys.node}</div>
          </div>
          <div class="bg-base-100 rounded-lg shadow-sm p-4">
            <div class="text-xs text-base-content/60">Cluster Nodes</div>
            <div class="text-xl font-bold">{@sys.cluster_size}</div>
          </div>
          <div class="bg-base-100 rounded-lg shadow-sm p-4">
            <div class="text-xs text-base-content/60">Elixir</div>
            <div class="text-xl font-bold">{@elixir_version}</div>
          </div>
        </div>

        <%!-- External metrics --%>
        <div class="card bg-base-200 shadow">
          <div class="card-body">
            <div class="flex flex-col md:flex-row md:items-center md:justify-between gap-4">
              <div>
                <h2 class="card-title text-lg">Metrics</h2>
                <p class="text-sm text-base-content/60">
                  Grafana contains host, container, app, and log history.
                </p>
              </div>
              <.link
                href={@grafana_url}
                target="_blank"
                rel="noopener noreferrer"
                class="btn btn-primary"
              >
                Open Grafana
              </.link>
            </div>
          </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <%!-- Memory breakdown --%>
          <div class="card bg-base-200 shadow">
            <div class="card-body">
              <h2 class="card-title text-lg">Memory (BEAM VM)</h2>
              <p class="text-xs text-base-content/60 mb-2">
                Memory allocated by the Erlang VM. Does not include OS-level overhead.
              </p>
              <div class="overflow-x-auto">
                <table class="table table-sm">
                  <thead>
                    <tr>
                      <th>Category</th>
                      <th class="text-right">Used</th>
                      <th class="text-right">% of Total</th>
                      <th class="text-right">Description</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={{label, mb, pct, desc} <- @memory_breakdown} id={"mem-#{label}"}>
                      <td class="font-medium">{label}</td>
                      <td class="text-right font-mono">{mb} MB</td>
                      <td class="text-right">
                        <div class="flex items-center justify-end gap-2">
                          <div class="w-16 bg-base-300 rounded-full h-2">
                            <div
                              class="bg-primary h-2 rounded-full transition-all"
                              style={"width: #{min(pct, 100)}%"}
                            >
                            </div>
                          </div>
                          <span class="font-mono text-xs w-10 text-right">{pct}%</span>
                        </div>
                      </td>
                      <td class="text-right text-xs text-base-content/60">{desc}</td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
          </div>

          <%!-- Processes & Ports --%>
          <div class="card bg-base-200 shadow">
            <div class="card-body">
              <h2 class="card-title text-lg">Processes & Ports</h2>
              <div class="space-y-6 mt-2">
                <div>
                  <div class="flex justify-between text-sm mb-1">
                    <span class="font-medium">Processes</span>
                    <span class="font-mono">
                      {format_number(@sys.process_count)} / {format_number(@sys.process_limit)}
                    </span>
                  </div>
                  <div class="w-full bg-base-300 rounded-full h-3">
                    <div
                      class="bg-primary h-3 rounded-full transition-all"
                      style={"width: #{@process_pct}%"}
                    >
                    </div>
                  </div>
                  <div class="text-xs text-base-content/60 mt-1">
                    {Float.round(@process_pct, 2)}% utilization
                  </div>
                </div>

                <div>
                  <div class="flex justify-between text-sm mb-1">
                    <span class="font-medium">Ports</span>
                    <span class="font-mono">
                      {format_number(@sys.port_count)} / {format_number(@sys.port_limit)}
                    </span>
                  </div>
                  <div class="w-full bg-base-300 rounded-full h-3">
                    <div
                      class="bg-primary h-3 rounded-full transition-all"
                      style={"width: #{@port_pct}%"}
                    >
                    </div>
                  </div>
                  <div class="text-xs text-base-content/60 mt-1">
                    {Float.round(@port_pct, 2)}% utilization
                  </div>
                </div>

                <div>
                  <div class="flex justify-between text-sm mb-1">
                    <span class="font-medium">Atoms</span>
                    <span class="font-mono">
                      {format_number(@atom_count)} / {format_number(@atom_limit)}
                    </span>
                  </div>
                  <div class="w-full bg-base-300 rounded-full h-3">
                    <div
                      class="bg-primary h-3 rounded-full transition-all"
                      style={"width: #{@atom_pct}%"}
                    >
                    </div>
                  </div>
                  <div class="text-xs text-base-content/60 mt-1">
                    {Float.round(@atom_pct, 2)}% utilization
                  </div>
                </div>

                <div>
                  <div class="flex justify-between text-sm mb-1">
                    <span class="font-medium">Scheduler CPU</span>
                    <span class="font-mono">
                      {@scheduler_util}%
                    </span>
                  </div>
                  <div class="w-full bg-base-300 rounded-full h-3">
                    <div
                      class="bg-primary h-3 rounded-full transition-all"
                      style={"width: #{@scheduler_util}%"}
                    >
                    </div>
                  </div>
                  <div class="text-xs text-base-content/60 mt-1">
                    Average busy time across {@sys.schedulers} schedulers
                  </div>
                </div>
              </div>
            </div>
          </div>

          <%!-- IO stats --%>
          <div class="card bg-base-200 shadow">
            <div class="card-body">
              <h2 class="card-title text-lg">I/O & GC</h2>
              <div class="overflow-x-auto">
                <table class="table table-sm">
                  <thead>
                    <tr>
                      <th>Metric</th>
                      <th class="text-right">Value</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr>
                      <td class="font-medium">I/O Input</td>
                      <td class="text-right font-mono">{format_bytes(@io_input)}</td>
                    </tr>
                    <tr>
                      <td class="font-medium">I/O Output</td>
                      <td class="text-right font-mono">{format_bytes(@io_output)}</td>
                    </tr>
                    <tr>
                      <td class="font-medium">GC Runs</td>
                      <td class="text-right font-mono">{format_number(@gc_count)}</td>
                    </tr>
                    <tr>
                      <td class="font-medium">GC Words Reclaimed</td>
                      <td class="text-right font-mono">{format_bytes(@gc_words_reclaimed * 8)}</td>
                    </tr>
                    <tr>
                      <td class="font-medium">Reductions</td>
                      <td class="text-right font-mono">{format_number(@reductions)}</td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
          </div>

          <%!-- ETS tables --%>
          <div class="card bg-base-200 shadow">
            <div class="card-body">
              <h2 class="card-title text-lg flex items-center gap-2">
                ETS Tables <span class="badge badge-sm badge-primary">{length(@ets_tables)}</span>
              </h2>
              <div class="overflow-x-auto max-h-80">
                <table class="table table-xs table-zebra">
                  <thead class="sticky top-0 bg-base-200">
                    <tr>
                      <th>Name</th>
                      <th class="text-right">Size</th>
                      <th class="text-right">Memory</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={table <- @ets_tables} id={"ets-#{table.id}"}>
                      <td class="font-mono text-xs truncate max-w-48">{table.name}</td>
                      <td class="text-right font-mono text-xs">{format_number(table.size)}</td>
                      <td class="text-right font-mono text-xs">{format_bytes(table.memory)}</td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        </div>

        <%!-- Data retention --%>
        <div class="card bg-base-200 shadow">
          <div class="card-body">
            <div class="flex flex-col md:flex-row md:items-center md:justify-between gap-4">
              <div>
                <h2 class="card-title text-lg">Data Retention</h2>
                <p class="text-sm text-base-content/60">
                  Sweeps every 6 hours. Windows are set per class with
                  <code class="text-xs">RETENTION_*</code>
                  env vars; a class missing below is configured to keep forever.
                </p>
              </div>
              <div class="flex items-center gap-3">
                <div class="text-right">
                  <div class="text-xs text-base-content/60">Last run</div>
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
                    <th class="text-right">Rows pruned</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={{class, count} <- @retention_rows} id={"retention-#{class}"}>
                    <td class="font-mono text-xs">{class}</td>
                    <td class="text-right font-mono">{count}</td>
                  </tr>
                </tbody>
              </table>
              <div class="text-xs text-base-content/40 mt-1">
                Took {@retention.duration_ms} ms. Classes that pruned nothing are hidden.
              </div>
            </div>
          </div>
        </div>

        <%!-- Cluster nodes --%>
        <%= if @cluster_nodes != [] do %>
          <div class="card bg-base-200 shadow">
            <div class="card-body">
              <h2 class="card-title text-lg">Cluster Topology</h2>
              <div class="flex flex-wrap gap-2 mt-2">
                <div class="badge badge-lg badge-primary gap-1">
                  <span class="w-2 h-2 rounded-full bg-success"></span>
                  {@sys.node} (self)
                </div>
                <div
                  :for={n <- @cluster_nodes}
                  class="badge badge-lg badge-outline badge-primary gap-1"
                >
                  <span class="w-2 h-2 rounded-full bg-success"></span>
                  {n}
                </div>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: schedule_refresh()

    {:ok,
     socket
     |> assign(:retention_running, false)
     |> assign_retention()
     |> assign_all_stats()}
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
    pruned = results |> Map.values() |> Enum.sum()

    {:noreply,
     socket
     |> assign(:retention_running, false)
     |> assign_retention()
     |> put_flash(:info, "Retention pruned #{pruned} rows.")}
  end

  def handle_info({:pruned, :unavailable}, socket) do
    {:noreply,
     socket
     |> assign(:retention_running, false)
     |> put_flash(:error, "Retention sweeper is not running.")}
  end

  def handle_info(:refresh, socket) do
    schedule_refresh()
    {:noreply, assign_all_stats(socket)}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  defp schedule_refresh, do: Process.send_after(self(), :refresh, @refresh_interval)

  # The button must resolve either way: a sweeper that is down or dies mid-run
  # would otherwise leave the page stuck on "Running...".
  defp run_sweep do
    {:ok, GameServer.Retention.run_now()}
  catch
    :exit, _reason -> :unavailable
  end

  defp assign_retention(socket) do
    status = GameServer.Retention.status()

    socket
    |> assign(:retention, status)
    |> assign(:retention_rows, Enum.sort(for {class, n} <- status.results, n > 0, do: {class, n}))
  end

  defp assign_all_stats(socket) do
    sys = ConnectionTracker.system_stats()
    memory = :erlang.memory()
    total_bytes = memory[:total]

    {io_input, io_output} =
      :erlang.statistics(:io) |> then(fn {{:input, i}, {:output, o}} -> {i, o} end)

    {gc_count, gc_words, _} = :erlang.statistics(:garbage_collection)
    {reductions, _} = :erlang.statistics(:exact_reductions)

    memory_breakdown = build_memory_breakdown(memory, total_bytes)

    process_pct = safe_pct(sys.process_count, sys.process_limit)
    port_pct = safe_pct(sys.port_count, sys.port_limit)

    atom_count = :erlang.system_info(:atom_count)
    atom_limit = :erlang.system_info(:atom_limit)
    atom_pct = safe_pct(atom_count, atom_limit)

    ets_tables = build_ets_tables()

    {scheduler_util, scheduler_sample} = get_scheduler_utilization(socket)

    assign(socket,
      sys: sys,
      elixir_version: System.version(),
      memory_breakdown: memory_breakdown,
      process_pct: process_pct,
      port_pct: port_pct,
      atom_count: atom_count,
      atom_limit: atom_limit,
      atom_pct: atom_pct,
      io_input: io_input,
      io_output: io_output,
      gc_count: gc_count,
      gc_words_reclaimed: gc_words,
      reductions: reductions,
      ets_tables: ets_tables,
      cluster_nodes: Node.list(),
      scheduler_util: scheduler_util,
      scheduler_sample: scheduler_sample,
      grafana_url: grafana_url()
    )
  end

  defp grafana_url do
    GameServerWeb.Observability.get(:grafana_url) || "http://localhost:3130"
  end

  defp build_memory_breakdown(memory, total_bytes) do
    categories = [
      {"Total", memory[:total], "All memory allocated by the BEAM VM"},
      {"Processes", memory[:processes],
       "Heap, stack, and internal data for all Erlang processes"},
      {"ETS", memory[:ets], "In-memory key-value tables (caches, registries)"},
      {"Atom", memory[:atom], "Interned strings (module names, map keys, etc.)"},
      {"Binary", memory[:binary], "Reference-counted binary data (large strings, files)"},
      {"Code", memory[:code], "Loaded modules (compiled .beam bytecode)"},
      {"System", memory[:system], "VM internals, drivers, NIF memory"}
    ]

    Enum.map(categories, fn {label, bytes, desc} ->
      mb = Float.round(bytes / 1_048_576, 2)
      pct = if total_bytes > 0, do: Float.round(bytes / total_bytes * 100, 1), else: 0.0
      {label, mb, pct, desc}
    end)
  end

  defp build_ets_tables do
    :ets.all()
    |> Enum.with_index()
    |> Enum.map(fn {table_id, idx} ->
      try do
        info = :ets.info(table_id)

        name =
          case Keyword.get(info, :name, table_id) do
            n when is_atom(n) -> Atom.to_string(n)
            n when is_binary(n) -> n
            _ -> "unnamed_#{idx}"
          end

        %{
          id: idx,
          name: name,
          size: Keyword.get(info, :size, 0),
          memory: Keyword.get(info, :memory, 0) * :erlang.system_info(:wordsize)
        }
      rescue
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.memory, :desc)
  end

  defp safe_pct(count, limit) when limit > 0, do: count / limit * 100
  defp safe_pct(_, _), do: 0.0

  defp format_number(n) when is_integer(n) and n >= 1_000_000_000 do
    "#{Float.round(n / 1_000_000_000, 1)}B"
  end

  defp format_number(n) when is_integer(n) and n >= 1_000_000 do
    "#{Float.round(n / 1_000_000, 1)}M"
  end

  defp format_number(n) when is_integer(n) and n >= 1_000 do
    "#{Float.round(n / 1_000, 1)}K"
  end

  defp format_number(n), do: to_string(n)

  defp format_bytes(bytes) when bytes >= 1_073_741_824 do
    "#{Float.round(bytes / 1_073_741_824, 2)} GB"
  end

  defp format_bytes(bytes) when bytes >= 1_048_576 do
    "#{Float.round(bytes / 1_048_576, 2)} MB"
  end

  defp format_bytes(bytes) when bytes >= 1_024 do
    "#{Float.round(bytes / 1_024, 1)} KB"
  end

  defp format_bytes(bytes), do: "#{bytes} B"

  defp get_scheduler_utilization(socket) do
    current_sample = scheduler_wall_time_sample()
    prev_sample = socket.assigns[:scheduler_sample]

    {scheduler_utilization(prev_sample, current_sample), current_sample}
  end

  defp scheduler_wall_time_sample do
    _ = :erlang.system_flag(:scheduler_wall_time, true)
    :erlang.statistics(:scheduler_wall_time)
  end

  defp scheduler_utilization(prev_sample, current_sample)
       when is_list(prev_sample) and is_list(current_sample) do
    prev_by_id = Map.new(prev_sample, fn {id, active, total} -> {id, {active, total}} end)

    {active_delta, total_delta} =
      Enum.reduce(current_sample, {0, 0}, fn {id, active, total}, {active_acc, total_acc} ->
        case Map.get(prev_by_id, id) do
          {prev_active, prev_total} when total >= prev_total and active >= prev_active ->
            {active_acc + active - prev_active, total_acc + total - prev_total}

          _ ->
            {active_acc, total_acc}
        end
      end)

    if total_delta > 0 do
      Float.round(active_delta / total_delta * 100, 1)
    else
      0.0
    end
  end

  defp scheduler_utilization(_prev_sample, _current_sample) do
    0.0
  end
end
