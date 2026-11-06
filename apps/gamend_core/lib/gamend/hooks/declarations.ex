defmodule Gamend.Hooks.Declarations do
  @moduledoc """
  Registry of what a plugin *declares* it contributes, for observability and
  validation.

  Three optional callbacks, registered the same convention-based way as
  `Gamend.Hooks.KvSchemas` — export them from the plugin's hooks module and
  they are picked up at load:

      def notification_types do
        %{"rival_online" => "A rival the player follows came online"}
      end

      def realtime_events do
        %{"quest_progress" => "Objective counter moved"}
      end

      def env_vars do
        [%{name: "MYGAME_DIFFICULTY", default: "normal", description: "Global difficulty"}]
      end

  `notification_types/0` is **enforced**: `Gamend.Notifications` rejects a
  notification whose `metadata["type"]` is not declared by core or a plugin, so
  a client is never sent a code nobody documented. The other two are
  declarations only — a plugin can always read an env var directly, and events
  are validated at the push site — but they make the admin runtime page tell
  the whole truth instead of only core's half.
  """

  require Logger

  @pt_key {__MODULE__, :declarations}
  @empty %{notification_types: %{}, realtime_events: %{}, env_vars: []}

  @doc "The merged registry: `%{notification_types:, realtime_events:, env_vars:}`."
  @spec all() :: %{
          notification_types: %{String.t() => String.t()},
          realtime_events: %{String.t() => String.t()},
          env_vars: [map()]
        }
  def all, do: :persistent_term.get(@pt_key, @empty)

  @doc "Notification codes declared by plugins, mapped to their description."
  @spec notification_types() :: %{String.t() => String.t()}
  def notification_types, do: all().notification_types

  @doc "Realtime event names declared by plugins, mapped to their description."
  @spec realtime_events() :: %{String.t() => String.t()}
  def realtime_events, do: all().realtime_events

  @doc """
  Env vars declared by plugins, each `%{name:, default:, type:, description:,
  secret:, plugin:}`. `secret` is the plugin's `secret: true`, false otherwise.
  """
  @spec env_vars() :: [map()]
  def env_vars, do: all().env_vars

  @doc "Rebuilds the registry from the loaded plugin list."
  @spec refresh([struct()]) :: :ok
  def refresh(plugins) do
    loaded = Enum.filter(plugins, &(&1.status == :ok))

    registry = %{
      notification_types: collect_map(loaded, :notification_types),
      realtime_events: collect_map(loaded, :realtime_events),
      env_vars: collect_env_vars(loaded)
    }

    :persistent_term.put(@pt_key, registry)
    log(registry)
    :ok
  end

  # A code declared by two plugins keeps the first (plugins arrive name-sorted),
  # mirroring how KV schema patterns resolve collisions.
  defp collect_map(plugins, callback) do
    Enum.reduce(plugins, %{}, fn plugin, acc ->
      plugin
      |> call(callback, %{})
      |> normalize_map(plugin, callback)
      |> Enum.reduce(acc, fn {code, description}, acc ->
        if Map.has_key?(acc, code) do
          Logger.warning("plugin=#{plugin.name} #{callback}: #{code} already declared; ignored")
          acc
        else
          Map.put(acc, code, description)
        end
      end)
    end)
  end

  defp collect_env_vars(plugins) do
    Enum.flat_map(plugins, fn plugin ->
      plugin
      |> call(:env_vars, [])
      |> List.wrap()
      |> Enum.filter(&valid_env_var?(&1, plugin))
      |> Enum.map(fn var ->
        default = Map.get(var, :default, "")

        %{
          name: var.name,
          default: default,
          type: Map.get(var, :type) || Gamend.Config.infer_type(default),
          description: Map.get(var, :description, ""),
          secret: Map.get(var, :secret) == true,
          plugin: plugin.name
        }
      end)
    end)
  end

  defp call(%{hooks_module: nil}, _callback, default), do: default

  defp call(%{hooks_module: mod}, callback, default) do
    if Code.ensure_loaded?(mod) and function_exported?(mod, callback, 0) do
      apply(mod, callback, [])
    else
      default
    end
  rescue
    error ->
      Logger.warning("#{inspect(mod)}.#{callback}/0 raised: #{Exception.message(error)}")
      default
  end

  defp normalize_map(value, plugin, callback) when is_map(value) do
    Enum.reduce(value, %{}, fn
      {code, description}, acc when is_binary(code) and is_binary(description) ->
        Map.put(acc, code, description)

      {code, _bad}, acc when is_binary(code) ->
        Map.put(acc, code, "")

      other, acc ->
        Logger.warning("plugin=#{plugin.name} #{callback}: ignoring #{inspect(other)}")
        acc
    end)
  end

  defp normalize_map(other, plugin, callback) do
    Logger.warning("plugin=#{plugin.name} #{callback} must return a map, got #{inspect(other)}")
    %{}
  end

  defp valid_env_var?(%{name: name}, _plugin) when is_binary(name) and name != "", do: true

  defp valid_env_var?(other, plugin) do
    Logger.warning("plugin=#{plugin.name} env_vars: ignoring #{inspect(other)} (needs :name)")
    false
  end

  defp log(%{notification_types: types, realtime_events: events, env_vars: vars}) do
    if types != %{}, do: Logger.info("plugin notification types: #{inspect(Map.keys(types))}")
    if events != %{}, do: Logger.info("plugin realtime events: #{inspect(Map.keys(events))}")
    if vars != [], do: Logger.info("plugin env vars: #{inspect(Enum.map(vars, & &1.name))}")
  end
end
