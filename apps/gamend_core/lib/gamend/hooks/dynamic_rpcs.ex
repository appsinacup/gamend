defmodule Gamend.Hooks.DynamicRpcs do
  @moduledoc """
  Runtime registry for *dynamic* RPC function names exported by hook plugins.

  ## Goal

  Allow hook plugins to expose additional callable function names without
  defining them as exported Elixir functions (eg. without `def my_fn/1`).

  The intended pattern is:

  - Plugin implements `after_startup/0` and returns a list of maps describing
    which dynamic RPC names should be callable.
  - Plugin implements `rpc/2` (or `rpc/3`) to handle these names at runtime.
  - `Gamend.Hooks.PluginManager.call_rpc/4` falls back to the registry when
    the requested function is not exported.

  ## Export format

  `after_startup/0` may return a list like:

      [
        %{hook: "my_dynamic_fn"},
        %{"hook" => "other_fn", "meta" => %{...}}
      ]

  Required:
  - `hook` (string): the callable function name.

  Optional:
  - `meta` (map): arbitrary metadata.

  Names are validated to contain only letters, digits, and underscores.

  Note: this registry is in-memory and is rebuilt on plugin reload.
  """

  require Logger

  @table :gamend_dynamic_rpcs

  @type plugin_name :: String.t()
  @type hook_name :: String.t()

  @type export :: %{
          hook: hook_name(),
          meta: map()
        }

  @spec ensure_table!() :: :ok
  def ensure_table! do
    case :ets.whereis(@table) do
      :undefined ->
        _tid =
          :ets.new(@table, [
            :named_table,
            :public,
            :set,
            read_concurrency: true,
            write_concurrency: true
          ])

        :ok

      _tid ->
        :ok
    end
  end

  @spec reset_all() :: :ok
  def reset_all do
    ensure_table!()
    true = :ets.delete_all_objects(@table)
    :ok
  end

  @doc "Forget one plugin's exports, leaving every other plugin's in place."
  @spec reset_plugin(plugin_name()) :: :ok
  def reset_plugin(plugin_name) when is_binary(plugin_name) do
    ensure_table!()
    true = :ets.match_delete(@table, {{plugin_name, :_}, :_})
    :ok
  end

  @spec register_exports(plugin_name(), any()) :: {:ok, non_neg_integer()} | {:error, term()}
  def register_exports(plugin_name, raw) when is_binary(plugin_name) do
    ensure_table!()

    exports = normalize_exports(raw)

    count =
      exports
      |> Enum.reduce(0, fn export, acc ->
        key = {plugin_name, export.hook}
        true = :ets.insert(@table, {key, export})
        acc + 1
      end)

    {:ok, count}
  rescue
    e ->
      {:error, Exception.message(e)}
  end

  @spec allowed?(plugin_name(), hook_name()) :: boolean()
  def allowed?(plugin_name, hook_name) when is_binary(plugin_name) and is_binary(hook_name) do
    ensure_table!()

    match?([_], :ets.lookup(@table, {plugin_name, hook_name}))
  end

  @spec lookup(plugin_name(), hook_name()) :: {:ok, export()} | {:error, :not_found}
  def lookup(plugin_name, hook_name) when is_binary(plugin_name) and is_binary(hook_name) do
    ensure_table!()

    case :ets.lookup(@table, {plugin_name, hook_name}) do
      [{{^plugin_name, ^hook_name}, export}] -> {:ok, export}
      _ -> {:error, :not_found}
    end
  end

  @spec list_all() :: %{optional(plugin_name()) => [export()]}
  def list_all do
    ensure_table!()

    @table
    |> :ets.tab2list()
    |> Enum.reduce(%{}, fn {{plugin_name, _hook_name}, export}, acc ->
      Map.update(acc, plugin_name, [export], fn list -> [export | list] end)
    end)
    |> Map.new(fn {plugin, list} ->
      {plugin, Enum.sort_by(list, & &1.hook)}
    end)
  end

  defp normalize_exports(raw) do
    raw
    |> List.wrap()
    |> Enum.flat_map(fn
      %{} = m ->
        case normalize_export(m) do
          {:ok, export} ->
            [export]

          {:error, reason} ->
            Logger.warning("ignoring invalid dynamic rpc export: #{inspect(reason)}")
            []
        end

      other ->
        Logger.warning("ignoring invalid dynamic rpc export: #{inspect(other)}")
        []
    end)
  end

  defp normalize_export(map) when is_map(map) do
    hook = Map.get(map, :hook) || Map.get(map, "hook")
    meta = Map.get(map, :meta) || Map.get(map, "meta")

    cond do
      not is_binary(hook) ->
        {:error, {:missing_hook, map}}

      not valid_hook_name?(hook) ->
        {:error, {:invalid_hook_name, hook}}

      not is_map(meta) and not is_nil(meta) ->
        {:error, {:invalid_meta, meta}}

      true ->
        {:ok, %{hook: hook, meta: meta || %{}}}
    end
  end

  defp valid_hook_name?(name) when is_binary(name) do
    String.match?(name, ~r/^[A-Za-z0-9_]+$/)
  end
end
