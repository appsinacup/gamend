defmodule GameServer.Hooks.PluginManager do
  @moduledoc """
  Loads and manages hook plugins shipped as OTP applications under `modules/plugins/*`.

  Each plugin is expected to be a directory named after the OTP app name (e.g. `polyglot_hook`)
  containing:

      modules/plugins/polyglot_hook/
        ebin/polyglot_hook.app
        ebin/Elixir.GameServer.Modules.PolyglotHook.beam
        priv/**
        deps/*/ebin/*.beam
        deps/*/priv/**

  The plugin's `.app` env must include the key `:hooks_module`, whose value is either a
  charlist or string module name like `'Elixir.GameServer.Modules.PolyglotHook'`.

  This manager is intentionally dependency-free: it only adds `ebin` directories to the code
  path and uses `Application.load/1` + `Application.ensure_all_started/1`.
  """

  use GenServer

  require Logger

  alias GameServer.Hooks.Declarations
  alias GameServer.Hooks.DynamicRpcs
  alias GameServer.Hooks.HookSchemas
  alias GameServer.Hooks.KvSchemas
  alias GameServer.Hooks.MetadataSchemas

  @type plugin_name :: String.t()
  @type plugin_app :: atom()

  @timeout_ms 60_000
  @default_slow_hook_threshold_ms 200.0

  defmodule Plugin do
    @moduledoc """
    A loaded plugin descriptor.

    This is a runtime struct used by `GameServer.Hooks.PluginManager` to report which
    plugins were discovered and whether they successfully loaded and started.
    """

    @type t :: %__MODULE__{
            name: String.t(),
            app: atom(),
            vsn: String.t() | nil,
            hooks_module: module() | nil,
            status: :ok | {:error, term()},
            loaded_at: DateTime.t() | nil,
            ebin_paths: [String.t()],
            modules: [module()]
          }

    defstruct name: nil,
              app: nil,
              vsn: nil,
              hooks_module: nil,
              status: {:error, :not_loaded},
              loaded_at: nil,
              ebin_paths: [],
              modules: []
  end

  # Public API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @snapshot_key {__MODULE__, :snapshot}

  # Reads go through a :persistent_term snapshot refreshed on every reload, so
  # hot callers (hook dispatch on every KV read / presence event) never serialize
  # through the GenServer and a reload can't head-of-line-block them.
  @spec list() :: [Plugin.t()]
  def list, do: snapshot().list

  @spec lookup(plugin_name()) :: {:ok, Plugin.t()} | {:error, term()}
  def lookup(name) when is_binary(name) do
    case Map.fetch(snapshot().by_name, name) do
      {:ok, plugin} -> {:ok, plugin}
      :error -> {:error, :not_found}
    end
  end

  @spec hook_modules() :: [{plugin_name(), module()}]
  def hook_modules, do: snapshot().hook_modules

  defp snapshot do
    :persistent_term.get(@snapshot_key, %{list: [], by_name: %{}, hook_modules: []})
  end

  @spec reload() :: [Plugin.t()]
  def reload do
    GenServer.call(__MODULE__, :reload, @timeout_ms)
  end

  @spec reload_and_after_startup() :: %{plugins: [Plugin.t()], after_startup: map()}
  def reload_and_after_startup do
    GenServer.call(__MODULE__, :reload_and_after_startup, @timeout_ms)
  end

  @spec call_rpc(plugin_name(), String.t(), list(), keyword()) :: {:ok, any()} | {:error, term()}
  def call_rpc(plugin, fn_name, args, opts \\ [])
      when is_binary(plugin) and is_binary(fn_name) and is_list(args) and is_list(opts) do
    case validate_rpc_request(fn_name, args) do
      :ok ->
        start_time = System.monotonic_time()
        result = do_call_rpc(plugin, fn_name, args, opts)
        duration_ms = duration_ms_since(start_time)

        if duration_ms > slow_hook_threshold_ms() do
          Logger.warning(
            "Slow Hook: #{format_rpc_context(plugin, fn_name, args, opts)} result=#{rpc_result_status(result)} took #{format_duration_ms(duration_ms)}ms"
          )
        end

        # Every client-driven hook lands here — HTTP, user channel and WebRTC
        # DataChannel all route through call_rpc, never through Hooks.do_call/3.
        # Capturing only there recorded nothing for real traffic, leaving player
        # intent (the main mutation source) missing from the timeline.
        _ =
          GameServer.LobbySnapshots.capture_hook(
            fn_name,
            Keyword.get(opts, :caller),
            result
          )

        result

      {:error, _} = err ->
        err
    end
  end

  # Enforced here (not just at each transport) so every RPC entry point — HTTP,
  # user channel, and WebRTC DataChannel — rejects reserved lifecycle-hook names
  # and oversized argument payloads identically.
  defp validate_rpc_request(fn_name, args) do
    cond do
      reserved_hook_name?(fn_name) -> {:error, :reserved_hook_name}
      length(args) > GameServer.Limits.get(:max_hook_args_count) -> {:error, :too_many_args}
      rpc_args_too_large?(args) -> {:error, :args_too_large}
      true -> :ok
    end
  end

  defp reserved_hook_name?(fn_name) when is_binary(fn_name) do
    Enum.any?(GameServer.Hooks.internal_hooks(), &(Atom.to_string(&1) == fn_name))
  end

  defp rpc_args_too_large?(args) do
    Enum.sum_by(args, &rpc_arg_size/1) > GameServer.Limits.get(:max_hook_args_size)
  end

  # Typed hooks pass raw binaries and decoded protobuf structs, which are not
  # JSON-encodable — measure those by their own size instead of rejecting.
  defp rpc_arg_size(arg) when is_binary(arg), do: byte_size(arg)

  defp rpc_arg_size(arg) do
    case Jason.encode(arg) do
      {:ok, encoded} -> byte_size(encoded)
      _ -> :erlang.external_size(arg)
    end
  end

  defp do_call_rpc(plugin, fn_name, args, opts) do
    case lookup(plugin) do
      {:ok, %Plugin{status: :ok, hooks_module: mod}} when is_atom(mod) and not is_nil(mod) ->
        timeout = Keyword.get(opts, :timeout_ms, @timeout_ms)

        case resolve_function_atom(mod, fn_name, length(args)) do
          {:ok, fun_atom} ->
            safe_apply_with_caller(mod, fun_atom, args, opts, timeout)

          {:error, :not_implemented} ->
            call_dynamic_rpc(plugin, mod, fn_name, args, opts, timeout)

          {:error, _} = err ->
            err
        end

      {:ok, %Plugin{status: {:error, reason}}} ->
        {:error, reason}

      {:ok, %Plugin{hooks_module: nil}} ->
        {:error, :missing_hooks_module}

      {:error, _} = err ->
        err
    end
  end

  @spec plugins_dir() :: String.t()
  def plugins_dir do
    GameServer.Settings.get(GameServer.ContentSettings, :plugins_dir) ||
      Path.expand("modules/plugins")
  end

  # GenServer

  @impl true
  def init(_opts) do
    # Load plugins on boot.
    plugins = do_reload(%{})

    # Best-effort after_startup fan-out at boot.
    _ = do_after_startup(plugins)

    {:ok, plugins}
  end

  @impl true
  def handle_call(:reload, _from, state) do
    state = do_reload(state)

    # Best-effort: run after_startup for newly loaded plugins after a reload.
    _ = do_after_startup(state)

    {:reply, state_to_list(state), state}
  end

  def handle_call(:reload_and_after_startup, _from, state) do
    state = do_reload(state)
    results = do_after_startup(state)
    {:reply, %{plugins: state_to_list(state), after_startup: results}, state}
  end

  # Internals

  defp state_to_list(state) when is_map(state) do
    state
    |> Map.values()
    |> Enum.sort_by(& &1.name)
  end

  # Refresh the lock-free read snapshot; called after every state change.
  defp publish_snapshot(state) when is_map(state) do
    list = state_to_list(state)

    hook_modules =
      Enum.flat_map(list, fn
        %Plugin{name: name, hooks_module: mod, status: :ok}
        when is_atom(mod) and not is_nil(mod) ->
          [{name, mod}]

        _ ->
          []
      end)

    :persistent_term.put(@snapshot_key, %{list: list, by_name: state, hook_modules: hook_modules})
    MetadataSchemas.refresh(list)
    HookSchemas.refresh(list)
    KvSchemas.refresh(list)
    Declarations.refresh(list)
    register_plugin_settings(hook_modules)
    state
  end

  # Plugins load after config/runtime.exs has already run, so a plugin's
  # declared settings cannot be resolved by `from_env/0` at boot. Register them
  # here and fill in any the host did not configure, so a plugin setting behaves
  # exactly like one of core's.
  defp register_plugin_settings(hook_modules) do
    for {_name, module} <- hook_modules,
        Code.ensure_loaded?(module),
        function_exported?(module, :__settings__, 0) do
      GameServer.Settings.add_provider(module)

      for definition <- module.__settings__(),
          value = System.get_env(definition.env),
          value not in [nil, ""],
          {:ok, cast} = GameServer.Settings.cast(value, definition.type),
          existing = Application.get_env(definition.app, module, []),
          not Keyword.has_key?(existing, definition.key) do
        Application.put_env(definition.app, module, Keyword.put(existing, definition.key, cast))
      end
    end

    :ok
  end

  defp format_rpc_context(plugin, fn_name, args, opts) do
    [
      {"plugin", plugin},
      {"fn", fn_name},
      {"user_id", opts |> Keyword.get(:caller) |> user_id()},
      {"args_count", length(args)},
      {"args_types", Enum.map_join(args, ",", &arg_type/1)}
    ]
    |> Enum.flat_map(fn
      {_key, nil} -> []
      {key, value} -> ["#{key}=#{format_context_value(value)}"]
    end)
    |> Enum.join(" ")
  end

  defp arg_type(value) when is_binary(value), do: "string"
  defp arg_type(value) when is_integer(value), do: "integer"
  defp arg_type(value) when is_float(value), do: "float"
  defp arg_type(value) when is_boolean(value), do: "boolean"
  defp arg_type(value) when is_list(value), do: "list"
  defp arg_type(value) when is_map(value), do: "map"
  defp arg_type(nil), do: "nil"
  defp arg_type(_value), do: "unknown"

  defp rpc_result_status({:ok, _result}), do: "ok"
  defp rpc_result_status({:error, reason}), do: "error:#{inspect(reason)}"

  defp user_id(%{id: id}) when is_binary(id), do: id
  defp user_id(_user), do: nil

  defp format_context_value(value) when is_binary(value), do: inspect(value)
  defp format_context_value(value) when is_integer(value), do: Integer.to_string(value)
  defp format_context_value(value), do: inspect(value)

  defp duration_ms_since(start_time) do
    System.monotonic_time()
    |> Kernel.-(start_time)
    |> System.convert_time_unit(:native, :microsecond)
    |> Kernel./(1000)
  end

  defp format_duration_ms(duration_ms) do
    duration_ms
    |> Kernel.*(1.0)
    |> :erlang.float_to_binary(decimals: 3)
  end

  defp slow_hook_threshold_ms do
    Application.get_env(
      :game_server_core,
      :slow_hook_threshold_ms,
      @default_slow_hook_threshold_ms
    )
  end

  defp do_reload(prev_state) when is_map(prev_state) do
    # Dynamic RPC exports are derived from the currently loaded plugins.
    # Rebuild the registry on each reload.
    _ = DynamicRpcs.reset_all()

    # Stop/unload previous apps and purge their modules first.
    prev_state
    |> Map.values()
    |> Enum.each(&stop_unload_plugin/1)

    # Load current plugin dirs, then refresh the lock-free read snapshot.
    load_plugins_from_disk()
    |> publish_snapshot()
  end

  defp stop_unload_plugin(%Plugin{app: app, hooks_module: hooks_mod} = plugin)
       when is_atom(app) do
    # Allow hooks module to run cleanup before stop/unload.
    _ = safe_call_before_stop(plugin)

    case Application.stop(app) do
      :ok -> :ok
      {:error, {:not_started, _}} -> :ok
      {:error, :not_started} -> :ok
      other -> Logger.warning("plugin stop failed app=#{inspect(app)}: #{inspect(other)}")
    end

    # Purge modules so reloading picks up new beams.
    purge_modules(plugin.modules)

    case Application.unload(app) do
      :ok -> :ok
      {:error, {:not_loaded, _}} -> :ok
      {:error, :not_loaded} -> :ok
      other -> Logger.warning("plugin unload failed app=#{inspect(app)}: #{inspect(other)}")
    end

    # Also purge the hooks module explicitly.
    purge_modules([hooks_mod])

    # Remove plugin code paths so reloads don't grow the path list.
    Enum.each(plugin.ebin_paths, fn p ->
      _ = Code.delete_path(p)
    end)
  end

  defp stop_unload_plugin(_), do: :ok

  defp purge_modules(mods) when is_list(mods) do
    Enum.each(mods, fn
      mod when is_atom(mod) ->
        _ = :code.purge(mod)
        _ = :code.delete(mod)

      _ ->
        :ok
    end)
  end

  defp load_plugins_from_disk do
    dir = plugins_dir()

    with true <- File.dir?(dir),
         {:ok, entries} <- File.ls(dir) do
      entries
      |> Enum.map(&Path.join(dir, &1))
      |> Enum.filter(&File.dir?/1)
      |> Enum.map(&Path.basename/1)
      |> Enum.sort()
      |> Enum.reduce(%{}, fn plugin_name, acc ->
        case load_plugin(dir, plugin_name) do
          %Plugin{} = plugin -> Map.put(acc, plugin_name, plugin)
          nil -> acc
        end
      end)
    else
      _ -> %{}
    end
  end

  @max_plugin_name_length 64

  defp load_plugin(root, plugin_name) when byte_size(plugin_name) <= @max_plugin_name_length do
    app = String.to_atom(plugin_name)

    plugin_dir = Path.join(root, plugin_name)

    ebin_paths =
      [Path.join(plugin_dir, "ebin")] ++
        Path.wildcard(Path.join(plugin_dir, "deps/*/ebin"))

    Enum.each(ebin_paths, fn p ->
      if File.dir?(p) do
        # Ensure we don't accumulate duplicate paths across reloads.
        _ = Code.delete_path(p)
        Code.append_path(p)
      end
    end)

    now = DateTime.utc_now()

    plugin = %Plugin{name: plugin_name, app: app, ebin_paths: ebin_paths, loaded_at: now}

    with :ok <- safe_load_app(app),
         {:ok, vsn} <- app_vsn(app),
         {:ok, modules} <- app_modules(app),
         {:ok, hooks_mod} <- app_hooks_module(app),
         :ok <- safe_ensure_started(app) do
      Logger.info(
        "plugin=#{plugin_name} loaded vsn=#{inspect(vsn)} hooks_module=#{inspect(hooks_mod)} modules=#{length(modules)}"
      )

      %Plugin{plugin | vsn: vsn, modules: modules, hooks_module: hooks_mod, status: :ok}
    else
      {:error, reason} ->
        %Plugin{plugin | status: {:error, reason}}
    end
  end

  defp load_plugin(_root, plugin_name) do
    Logger.warning("plugin=#{plugin_name} skipped: name exceeds #{@max_plugin_name_length} chars")
    nil
  end

  defp safe_load_app(app) do
    case Application.load(app) do
      :ok -> :ok
      {:error, {:already_loaded, _}} -> :ok
      {:error, :already_loaded} -> :ok
      {:error, reason} -> {:error, {:load_failed, reason}}
    end
  end

  defp safe_ensure_started(app) do
    case Application.ensure_all_started(app) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:start_failed, reason}}
    end
  end

  defp app_vsn(app) do
    case :application.get_key(app, :vsn) do
      {:ok, vsn} -> {:ok, to_string(vsn)}
      :undefined -> {:ok, nil}
    end
  end

  defp app_modules(app) do
    case :application.get_key(app, :modules) do
      {:ok, mods} when is_list(mods) -> {:ok, mods}
      :undefined -> {:ok, []}
    end
  end

  defp app_hooks_module(app) do
    case Application.get_env(app, :hooks_module) do
      nil ->
        {:error, :missing_hooks_module}

      mod when is_atom(mod) ->
        {:ok, mod}

      mod when is_binary(mod) ->
        {:ok, String.to_atom(mod)}

      mod when is_list(mod) ->
        # charlist
        {:ok, String.to_atom(to_string(mod))}

      other ->
        {:error, {:invalid_hooks_module, other}}
    end
  end

  defp resolve_function_atom(mod, fn_name, arity) when is_atom(mod) and is_binary(fn_name) do
    mod.__info__(:functions)
    |> Enum.find_value({:error, :not_implemented}, fn {name, a} ->
      if a == arity and Atom.to_string(name) == fn_name do
        {:ok, name}
      else
        false
      end
    end)
  end

  defp safe_apply_with_caller(mod, fun, args, opts, timeout)
       when is_atom(mod) and is_atom(fun) and is_list(args) and is_list(opts) do
    task =
      Task.async(fn ->
        if caller = Keyword.get(opts, :caller) do
          Process.put(:game_server_hook_caller, caller)
        end

        try do
          apply(mod, fun, args)
        rescue
          e in FunctionClauseError -> {:error, {:function_clause, Exception.message(e)}}
          e -> {:error, {:exception, Exception.message(e)}}
        catch
          kind, reason -> {:error, {kind, reason}}
        end
      end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, res}} -> {:ok, res}
      {:ok, {:error, err}} -> {:error, err}
      {:ok, res} -> {:ok, res}
      nil -> {:error, :timeout}
      {:exit, reason} -> {:error, {:exit, reason}}
    end
  end

  defp do_after_startup(state) when is_map(state) do
    state
    |> Map.values()
    |> Enum.reduce(%{}, fn
      %Plugin{name: name, hooks_module: mod, status: :ok}, acc ->
        res =
          case Code.ensure_loaded(mod) do
            {:module, _} ->
              if function_exported?(mod, :after_startup, 0) do
                safe_apply(mod, :after_startup, [], @timeout_ms)
              else
                :not_exported
              end

            other ->
              Logger.error(
                "plugin=#{name} failed to load module=#{inspect(mod)}: #{inspect(other)}"
              )

              {:error, {:module_not_loaded, other}}
          end

        _ =
          case res do
            {:ok, exports} when is_list(exports) ->
              DynamicRpcs.register_exports(name, exports)

            {:ok, _other} ->
              :ok

            _ ->
              :ok
          end

        Map.put(acc, name, res)

      %Plugin{name: name, status: {:error, reason}}, acc ->
        Map.put(acc, name, {:skipped, reason})

      %Plugin{name: name}, acc ->
        Map.put(acc, name, :skipped)
    end)
  end

  defp call_dynamic_rpc(plugin, mod, fn_name, args, opts, timeout)
       when is_binary(plugin) and is_atom(mod) and is_binary(fn_name) and is_list(args) and
              is_list(opts) and is_integer(timeout) do
    if DynamicRpcs.allowed?(plugin, fn_name) do
      cond do
        function_exported?(mod, :on_custom_hook, 2) ->
          safe_apply_with_caller(mod, :on_custom_hook, [fn_name, args], opts, timeout)

        function_exported?(mod, :rpc, 2) ->
          safe_apply_with_caller(mod, :rpc, [fn_name, args], opts, timeout)

        function_exported?(mod, :rpc, 3) ->
          safe_apply_with_caller(
            mod,
            :rpc,
            [fn_name, args, Keyword.get(opts, :caller)],
            opts,
            timeout
          )

        true ->
          {:error, :not_implemented}
      end
    else
      {:error, :not_implemented}
    end
  end

  defp safe_call_before_stop(%Plugin{hooks_module: mod, status: :ok, name: name})
       when is_atom(mod) do
    case Code.ensure_loaded(mod) do
      {:module, _} ->
        if function_exported?(mod, :before_stop, 0) do
          safe_apply(mod, :before_stop, [])
        else
          Logger.debug("plugin #{name} has no before_stop/0")
          :not_exported
        end

      other ->
        Logger.error(
          "plugin=#{name} failed to load before_stop module=#{inspect(mod)}: #{inspect(other)}"
        )

        {:error, {:module_not_loaded, other}}
    end
  end

  defp safe_call_before_stop(_), do: :ok

  defp safe_apply(mod, fun, args, timeout \\ @timeout_ms)
       when is_atom(mod) and is_atom(fun) and is_list(args) and is_integer(timeout) do
    task =
      Task.async(fn ->
        try do
          apply(mod, fun, args)
        rescue
          e in FunctionClauseError -> {:error, {:function_clause, Exception.message(e)}}
          e -> {:error, {:exception, Exception.message(e)}}
        catch
          kind, reason -> {:error, {kind, reason}}
        end
      end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:error, _} = err} -> err
      {:ok, res} -> {:ok, res}
      nil -> {:error, :timeout}
      {:exit, reason} -> {:error, {:exit, reason}}
    end
  end
end
