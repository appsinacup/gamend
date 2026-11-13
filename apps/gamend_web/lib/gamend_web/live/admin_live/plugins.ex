defmodule GamendWeb.AdminLive.Plugins do
  @moduledoc """
  `/admin/plugins`: the hook plugins this server loaded (and the host's RPC
  modules), reloading them, building a bundle, and calling any function one
  exports: pick a plugin, pick a function, give it arguments.

  A call goes through the pipeline the realtime transports use, as the admin
  who made it. In protobuf mode a typed hook also does the full binary round
  trip (arguments encoded to request bytes, reply decoded from reply bytes) and
  reports the wire sizes.
  """
  use GamendWeb, :live_view

  alias Gamend.Accounts.Scope
  alias Gamend.Hooks.HookSchemas
  alias Gamend.Hooks.KvSchemas
  alias Gamend.Hooks.MetadataSchemas
  alias Gamend.Hooks.PluginBuilder
  alias Gamend.Hooks.PluginManager
  alias GamendWeb.AdminLive.PluginFunctions

  require GamendWeb.WsFormat, as: WsFormat

  use GamendWeb.UrlState,
    reload: :assign_call,
    keys: [plugin: [type: :nilable], function: [param: "fn", type: :nilable]]

  @json "json"

  @impl true
  def mount(params, _session, socket) do
    # The endpoint can take traffic briefly before the plugins finish loading
    # (after a node restart): look once more shortly after connecting.
    if connected?(socket), do: Process.send_after(self(), :refresh_plugins, 250)

    {:ok,
     socket
     |> assign(
       page_title: "Admin · Plugins",
       plugin: nil,
       function: nil,
       last_reload: nil,
       reload_result: nil,
       call_result: nil,
       call_duration_us: nil,
       build_options: Enum.map(PluginBuilder.list_buildable_plugins(), &{&1, &1}),
       build_available?: PluginBuilder.available?(),
       build_mode: PluginBuilder.mode(),
       build_running?: false,
       build_result: nil
     )
     |> assign_build_form()
     |> load_plugins()
     |> GamendWeb.UrlState.from_url(params)
     |> assign_call()}
  end

  @impl true
  def handle_info(:refresh_plugins, socket), do: {:noreply, reload_view(socket)}

  def handle_info({:plugin_build_finished, _name, {:ok, build_result}}, socket) do
    # An in-process build restarts a plugin that was loaded, so the list may
    # have changed under us.
    {:noreply,
     socket
     |> assign(build_running?: false, build_result: build_result)
     |> reload_view()
     |> put_flash(:info, "Plugin build finished")}
  end

  def handle_info({:plugin_build_finished, _name, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:build_running?, false)
     |> put_flash(:error, "Plugin build failed: #{inspect(reason)}")}
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  @impl true
  def handle_event("reload_plugins", _params, socket) do
    result = PluginManager.reload_and_after_startup()

    {:noreply,
     socket
     |> assign(last_reload: DateTime.utc_now(), reload_result: result)
     |> reload_view()}
  end

  def handle_event("build_plugin_bundle", %{"plugin_build" => %{"name" => name}}, socket)
      when is_binary(name) do
    cond do
      socket.assigns.build_running? ->
        {:noreply, socket}

      not socket.assigns.build_available? ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "This image cannot build plugin bundles: it has neither mix nor the Elixir compiler."
         )}

      socket.assigns.build_options == [] ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "No buildable plugins found under #{PluginBuilder.sources_dir()}"
         )}

      true ->
        parent = self()

        Gamend.Async.run(fn ->
          send(parent, {:plugin_build_finished, name, PluginBuilder.build(name)})
        end)

        {:noreply,
         socket
         |> assign(build_running?: true, build_result: nil)
         |> put_flash(:info, "Building plugin bundle for #{name}…")}
    end
  end

  def handle_event("select_plugin", %{"plugin" => plugin}, socket) do
    {:noreply, socket |> assign(plugin: plugin, function: nil) |> assign_call()}
  end

  def handle_event("select_function", %{"function" => function}, socket) do
    {:noreply, socket |> assign(:function, function) |> assign_call()}
  end

  def handle_event(
        "call_change",
        %{"_target" => ["call", "plugin"], "call" => %{"plugin" => plugin}},
        socket
      ) do
    {:noreply, socket |> assign(plugin: plugin, function: nil) |> assign_call()}
  end

  def handle_event(
        "call_change",
        %{"_target" => ["call", "function"], "call" => %{"function" => function}},
        socket
      ) do
    {:noreply, socket |> assign(:function, function) |> assign_call()}
  end

  def handle_event("call_change", %{"call" => params}, socket) do
    {:noreply, assign(socket, :call_form, to_form(params, as: :call))}
  end

  def handle_event("call", %{"call" => params}, socket) do
    caller = Scope.user(socket.assigns.current_scope)

    {duration_us, result} = :timer.tc(fn -> run_call(params, caller) end)

    {:noreply,
     assign(socket,
       call_form: to_form(params, as: :call),
       call_result: result,
       call_duration_us: duration_us
     )}
  end

  # ── data ──────────────────────────────────────────────────────────────────

  defp load_plugins(socket) do
    functions = PluginFunctions.list()

    assign(socket,
      functions: functions,
      plugin_rows: plugin_rows(functions),
      metadata_schema_entities: MetadataSchemas.entities(),
      metadata_schemas: MetadataSchemas.all(),
      kv_schemas: KvSchemas.all()
    )
  end

  # Reloading must not take away what the admin typed, unless the function they
  # typed it for is gone.
  defp reload_view(socket) do
    %{function: previous, call_form: form} = socket.assigns
    reloaded = socket |> load_plugins() |> assign_call()

    if reloaded.assigns.function == previous,
      do: assign(reloaded, :call_form, form),
      else: reloaded
  end

  # What the URL or a click asked for, if it exists: a URL is anyone's to write.
  defp assign_call(socket) do
    %{functions: functions} = socket.assigns
    plugin = pick(socket.assigns.plugin, functions |> Enum.map(& &1.plugin) |> Enum.uniq())
    in_plugin = Enum.filter(functions, &(&1.plugin == plugin))
    function = pick(socket.assigns.function, Enum.map(in_plugin, &to_string(&1.name)))
    selected = Enum.find(in_plugin, &(to_string(&1.name) == function))

    format =
      case socket.assigns[:call_form] do
        nil -> @json
        form -> form[:format].value
      end

    form =
      to_form(
        %{
          "plugin" => plugin,
          "function" => function,
          "args" => example_args(selected),
          "format" => format
        },
        as: :call
      )

    assign(socket,
      plugin: plugin,
      function: function,
      plugin_functions: in_plugin,
      selected_function: selected,
      call_form: form
    )
  end

  defp pick(wanted, options), do: if(wanted in options, do: wanted, else: List.first(options))

  defp assign_build_form(socket) do
    name =
      case socket.assigns.build_options do
        [{first, _value} | _rest] -> first
        [] -> ""
      end

    assign(socket, :build_form, to_form(%{"name" => name}, as: :plugin_build))
  end

  defp plugin_rows(functions) do
    by_plugin = Enum.group_by(functions, & &1.plugin)

    loaded =
      for plugin <- PluginManager.list() do
        %{
          name: plugin.name,
          vsn: plugin.vsn,
          status: plugin.status,
          module: plugin.hooks_module,
          loaded_at: plugin.loaded_at
        }
      end

    hosted =
      for {name, module} <- PluginManager.host_rpc_modules() do
        %{name: name, vsn: nil, status: :host, module: module, loaded_at: nil}
      end

    for row <- loaded ++ hosted do
      exported = Map.get(by_plugin, row.name, [])

      Map.merge(row, %{
        functions: length(exported),
        typed: Enum.count(exported, & &1.typed_schema)
      })
    end
  end

  # A declared example when there is one; otherwise the shape of the call, so
  # the arity is right and only the values are left to fill in.
  defp example_args(nil), do: ""

  defp example_args(%{signatures: [%{example_args: example} | _rest]}) when is_binary(example),
    do: example

  defp example_args(%{typed_schema: typed}) when typed != nil, do: "[{}]"

  defp example_args(%{signatures: [%{arity: arity} | _rest]}) when is_integer(arity),
    do: Jason.encode!(List.duplicate(nil, arity))

  defp example_args(_function), do: "[]"

  defp run_call(%{"plugin" => plugin, "function" => function, "args" => text} = params, caller) do
    format = if params["format"] == WsFormat.protobuf(), do: :protobuf, else: :json

    case parse_args(text) do
      {:ok, args} -> run_call(plugin, function, args, format, caller)
      :error -> "error: the arguments are not valid JSON"
    end
  end

  defp run_call(plugin, function, args, :json, caller) do
    case HookSchemas.call(plugin, function, {:list, args}, :map, caller: caller) do
      {:ok, result} -> inspect(result)
      {:error, reason} -> "error: #{inspect(reason)}"
    end
  end

  defp run_call(plugin, function, args, :protobuf, caller) do
    case HookSchemas.lookup(plugin, function) do
      nil ->
        case HookSchemas.call(plugin, function, {:list, args}, :map, caller: caller) do
          {:ok, result} ->
            inspect(result) <> " (no typed schema — dynamic args, protobuf envelope only)"

          {:error, reason} ->
            "error: #{inspect(reason)}"
        end

      %{request: request, reply: reply} ->
        with {:ok, struct} <- typed_request(request, args),
             request_bytes = Protobuf.encode(struct),
             {:ok, {:raw, reply_bytes}} <-
               HookSchemas.call(plugin, function, {:raw, request_bytes}, :binary, caller: caller) do
          "#{inspect(reply.decode(reply_bytes))} (wire: #{byte_size(request_bytes)}B request, #{byte_size(reply_bytes)}B reply)"
        else
          {:error, reason} -> "error: #{inspect(reason)}"
        end
    end
  end

  defp typed_request(module, []), do: {:ok, struct(module)}
  defp typed_request(module, [map]) when is_map(map), do: Protobuf.JSON.from_decoded(map, module)
  defp typed_request(_module, _args), do: {:error, :typed_hook_expects_single_object_arg}

  defp parse_args(text) do
    case String.trim(text) do
      "" ->
        {:ok, []}

      trimmed ->
        case Jason.decode(trimmed) do
          {:ok, parsed} when is_list(parsed) -> {:ok, parsed}
          {:ok, parsed} -> {:ok, [parsed]}
          {:error, _reason} -> :error
        end
    end
  end

  # ── render ────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-6">
        <.admin_header page="/admin/plugins">
          <:subtitle>What loaded, and calling it by hand.</:subtitle>
          <:actions>
            <.link navigate={~p"/admin/logs"} class="btn btn-surface btn-sm">Logs</.link>
            <button
              id="plugins-reload-btn"
              type="button"
              phx-click="reload_plugins"
              class="btn btn-primary btn-sm"
            >
              Reload plugins
            </button>
          </:actions>
        </.admin_header>

        <div id="plugins-installed" class="card bg-base-200 shadow">
          <div class="card-body">
            <h2 class="card-title text-lg">Installed ({length(@plugin_rows)})</h2>
            <p class="font-mono text-xs text-muted break-all">{PluginManager.plugins_dir()}</p>

            <p :if={@plugin_rows == []} class="text-sm text-muted">
              No plugins here. Build one with <code>mix plugin.bundle</code> and reload.
            </p>

            <div :if={@plugin_rows != []} class="overflow-x-auto">
              <table class="table table-sm">
                <thead>
                  <tr>
                    <th>Plugin</th>
                    <th>Version</th>
                    <th>Status</th>
                    <th>Module</th>
                    <th class="text-right">Functions</th>
                    <th class="text-right">Typed</th>
                    <th>Loaded</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={row <- @plugin_rows} id={"plugin-#{row.name}"}>
                    <td>
                      <button
                        type="button"
                        phx-click="select_plugin"
                        phx-value-plugin={row.name}
                        class={["link font-mono text-sm", @plugin == row.name && "font-bold"]}
                      >
                        {row.name}
                      </button>
                    </td>
                    <td class="font-mono text-xs">{row.vsn || "—"}</td>
                    <td>
                      <.plugin_status status={row.status} />
                    </td>
                    <td class="font-mono text-xs break-all">{inspect(row.module)}</td>
                    <td class="text-right font-mono text-xs">{row.functions}</td>
                    <td class="text-right font-mono text-xs">{row.typed}</td>
                    <td class="text-xs"><.timestamp at={row.loaded_at} /></td>
                  </tr>
                </tbody>
              </table>
            </div>

            <p :if={@last_reload} class="text-xs text-muted">
              Last reload: <.timestamp at={@last_reload} />
            </p>
            <pre
              :if={@reload_result}
              id="plugins-reload-result"
              class="text-xs font-mono whitespace-pre-wrap break-words"
            >{inspect(@reload_result) |> String.slice(0, 1024)}</pre>
          </div>
        </div>

        <div id="plugins-call" class="card bg-base-200 shadow">
          <div class="card-body">
            <h2 class="card-title text-lg">Call a function</h2>

            <p :if={@functions == []} class="text-sm text-muted">
              No loaded plugin exports a function.
            </p>

            <div :if={@functions != []} class="grid grid-cols-1 lg:grid-cols-3 gap-6">
              <ul
                id="plugins-functions"
                class="space-y-1 lg:col-span-1 max-h-[32rem] overflow-y-auto"
              >
                <li :for={function <- @plugin_functions}>
                  <button
                    type="button"
                    phx-click="select_function"
                    phx-value-function={function.name}
                    aria-current={to_string(function.name) == @function && "true"}
                    class={[
                      "w-full text-left rounded-field px-3 py-2 transition-colors hover:bg-base-300",
                      to_string(function.name) == @function && "bg-base-300"
                    ]}
                  >
                    <span class="font-mono text-sm break-all">{function_label(function)}</span>
                    <span :if={function.typed_schema} class="badge badge-primary badge-xs ml-1">
                      protobuf
                    </span>
                    <span :if={summary(function)} class="block text-xs text-muted">
                      {summary(function)}
                    </span>
                  </button>
                </li>
              </ul>

              <div class="lg:col-span-2 space-y-3 min-w-0">
                <.form
                  for={@call_form}
                  id="plugins-call-form"
                  phx-change="call_change"
                  phx-submit="call"
                  class="space-y-2"
                >
                  <div class="grid grid-cols-1 sm:grid-cols-3 gap-2">
                    <.input
                      field={@call_form[:plugin]}
                      type="select"
                      label="Plugin"
                      options={@functions |> Enum.map(& &1.plugin) |> Enum.uniq()}
                    />
                    <.input
                      field={@call_form[:function]}
                      type="select"
                      label="Function"
                      options={Enum.map(@plugin_functions, &{function_label(&1), &1.name})}
                    />
                    <.input
                      field={@call_form[:format]}
                      type="select"
                      label="Format"
                      options={[{"JSON", "json"}, {"Protobuf", WsFormat.protobuf()}]}
                    />
                  </div>
                  <.input
                    field={@call_form[:args]}
                    type="textarea"
                    label="Arguments (JSON array)"
                    rows="3"
                    phx-debounce="200"
                  />
                  <button id="plugins-call-btn" type="submit" class="btn btn-primary btn-sm">
                    Call
                  </button>
                </.form>

                <div :if={@selected_function} id="plugins-function-doc" class="space-y-2">
                  <div :for={signature <- @selected_function.signatures} class="min-w-0">
                    <code :if={signature.signature} class="text-sm break-all">
                      {signature.signature}
                    </code>
                    <pre
                      :if={signature.doc}
                      class="mt-1 text-xs whitespace-pre-wrap break-words"
                    >{signature.doc}</pre>
                  </div>
                  <p :if={@selected_function.typed_schema} class="text-xs text-muted font-mono">
                    {inspect(@selected_function.typed_schema.request)} / {inspect(
                      @selected_function.typed_schema.reply
                    )}
                  </p>
                </div>

                <div :if={@call_result} id="plugins-call-result">
                  <div class="text-xs text-muted">
                    Result, in {format_duration_us(@call_duration_us)}
                  </div>
                  <pre class="mt-1 text-sm font-mono whitespace-pre-wrap break-words bg-base-100 rounded-box p-3 max-h-96 overflow-auto">{@call_result}</pre>
                </div>
              </div>
            </div>
          </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
          <div id="plugins-build" class="card bg-base-200 shadow">
            <div class="card-body">
              <h2 class="card-title text-lg">Build a bundle</h2>
              <.form
                for={@build_form}
                id="plugins-build-form"
                phx-submit="build_plugin_bundle"
                class="flex flex-wrap items-end gap-2"
              >
                <.input
                  field={@build_form[:name]}
                  type="select"
                  label="Source"
                  options={@build_options}
                />
                <button
                  id="plugins-build-btn"
                  type="submit"
                  class="btn btn-surface btn-sm"
                  disabled={@build_running? or @build_options == [] or not @build_available?}
                >
                  {if @build_running?, do: "Building…", else: "Build bundle"}
                </button>
              </.form>

              <div id="plugins-build-mode" class="text-xs font-mono text-muted break-all">
                SRC: {PluginBuilder.sources_dir()} — BUILD: {build_mode_label(@build_mode)}
              </div>

              <p :if={not @build_available?} class="text-xs text-muted">
                This image ships neither <code>mix</code>
                nor the Elixir compiler, so it cannot build bundles. Build them where the
                plugin sources live and mount the result.
              </p>
              <p
                :if={@build_mode == :in_process}
                id="plugins-build-in-process"
                class="text-xs text-muted"
              >
                No <code>mix</code>
                here, so bundles compile inside the running server. Elixir and GDScript
                plugins build; a dependency the server does not ship has to be prebuilt in
                the plugin's <code>deps/&lt;dep&gt;/ebin</code>. A loaded plugin restarts
                on the new bundle.
              </p>

              <div :if={@build_result} id="plugins-build-result">
                <div class="flex flex-wrap items-center gap-2">
                  <span class={[
                    "badge badge-sm",
                    if(@build_result.ok?, do: "badge-success", else: "badge-error")
                  ]}>
                    {if @build_result.ok?, do: "BUILD OK", else: "BUILD ERR"}
                  </span>
                  <span class="text-xs font-mono text-muted break-all">
                    {@build_result.plugin}
                  </span>
                </div>
                <pre class="mt-2 text-xs font-mono whitespace-pre-wrap break-words max-h-64 overflow-auto bg-base-100 rounded-box p-3">{build_output(@build_result)}</pre>
              </div>
            </div>
          </div>

          <div id="plugins-coverage" class="card bg-base-200 shadow">
            <div class="card-body">
              <h2 class="card-title text-lg">Protobuf schema coverage</h2>
              <p class="text-xs text-muted">
                What the loaded plugins registered. Anything marked JSON still works on protobuf
                sockets; it travels as JSON bytes.
              </p>
              <div class="overflow-x-auto">
                <table class="table table-xs">
                  <tbody>
                    <tr :for={entity <- @metadata_schema_entities}>
                      <td class="font-mono text-xs">{entity} metadata</td>
                      <td>
                        <%= if module = @metadata_schemas[entity] do %>
                          <span class="badge badge-primary badge-xs">protobuf</span>
                          <span class="font-mono text-xs ml-1">{inspect(module)}</span>
                        <% else %>
                          <span class="badge badge-ghost badge-xs">JSON</span>
                          <span class="text-xs text-muted ml-1">
                            define a {entity |> to_string() |> Macro.camelize()}Meta message to register
                          </span>
                        <% end %>
                      </td>
                    </tr>
                    <tr>
                      <td class="font-mono text-xs">kv data</td>
                      <td>
                        <%= if @kv_schemas.exact == %{} and @kv_schemas.prefixes == [] do %>
                          <span class="badge badge-ghost badge-xs">JSON</span>
                          <span class="text-xs text-muted ml-1">
                            export kv_schemas/0 (exact key or "prefix*") to register
                          </span>
                        <% else %>
                          <span class="badge badge-primary badge-xs">protobuf</span>
                          <span class="font-mono text-xs ml-1">{kv_schema_keys(@kv_schemas)}</span>
                        <% end %>
                      </td>
                    </tr>
                    <tr>
                      <td class="font-mono text-xs">typed hooks</td>
                      <td>
                        <span class="badge badge-ghost badge-xs">
                          {Enum.count(@functions, & &1.typed_schema)} / {length(@functions)}
                        </span>
                        <span class="text-xs text-muted ml-1">
                          functions with a &lt;FnName&gt;Request/Reply pair
                        </span>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :status, :any, required: true

  defp plugin_status(%{status: :ok} = assigns) do
    ~H"""
    <span class="badge badge-success badge-sm">OK</span>
    """
  end

  defp plugin_status(%{status: :host} = assigns) do
    ~H"""
    <span class="badge badge-info badge-sm">Host</span>
    """
  end

  defp plugin_status(%{status: {:error, reason}} = assigns) do
    assigns = assign(assigns, :reason, reason)

    ~H"""
    <span class="badge badge-error badge-sm">Error</span>
    <div class="text-xs font-mono text-error break-words">{inspect(@reason)}</div>
    """
  end

  defp function_label(%{name: name, signatures: signatures}) do
    case signatures |> Enum.map(& &1.arity) |> Enum.filter(&is_integer/1) do
      [] -> to_string(name)
      arities -> "#{name}/#{Enum.join(arities, ",")}"
    end
  end

  defp summary(%{signatures: [%{doc: doc} | _rest]}) when is_binary(doc) and doc != "" do
    doc |> String.split("\n", parts: 2) |> hd() |> String.slice(0, 120)
  end

  defp summary(_function), do: nil

  defp kv_schema_keys(%{exact: exact, prefixes: prefixes}) do
    Enum.join(Map.keys(exact) ++ Enum.map(prefixes, &(elem(&1, 0) <> "*")), ", ")
  end

  defp format_duration_us(us) when us < 1_000, do: "#{us}µs"
  defp format_duration_us(us) when us < 1_000_000, do: "#{Float.round(us / 1_000, 2)}ms"
  defp format_duration_us(us), do: "#{Float.round(us / 1_000_000, 2)}s"

  defp build_mode_label(:mix), do: "mix (MIX_ENV=#{System.get_env("MIX_ENV") || "<unset>"})"
  defp build_mode_label(:in_process), do: "in-process"
  defp build_mode_label(_mode), do: "unavailable"

  defp build_output(%{steps: steps}) when is_list(steps) do
    steps
    |> Enum.map_join("\n\n", fn step ->
      "$ #{step.cmd} (exit=#{step.status})\n" <> (step.output || "")
    end)
    |> String.trim()
    |> String.slice(0, 8192)
  end

  defp build_output(result), do: result |> inspect() |> String.slice(0, 8192)
end
