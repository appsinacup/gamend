defmodule GamendWeb.AdminLive.PluginFunctions do
  @moduledoc """
  Every function `/admin/plugins` can call: each plugin's and each host RPC
  module's exports, with what BEAM metadata says about them (signature, doc),
  the dynamically registered RPCs, and the typed schema where one exists.
  """

  alias Gamend.Hooks
  alias Gamend.Hooks.DynamicRpcs
  alias Gamend.Hooks.HookSchemas
  alias Gamend.Hooks.PluginManager

  @arg "arg"

  @doc "Every callable function, sorted by plugin and name."
  @spec list() :: [map()]
  def list do
    plugins = PluginManager.rpc_modules()

    static =
      plugins
      |> Enum.flat_map(fn {plugin, mod} ->
        Hooks.exported_functions(mod)
        |> Enum.map(&Map.put(&1, :plugin, plugin))
      end)

    dynamic_by_plugin = DynamicRpcs.list_all()

    dynamic =
      plugins
      |> Enum.flat_map(fn {plugin, _mod} ->
        dynamic_by_plugin
        |> Map.get(plugin, [])
        |> Enum.map(fn export ->
          %{
            name: export.hook,
            arities: [],
            signatures: [dynamic_signature(export)],
            plugin: plugin
          }
        end)
      end)

    (static ++ dynamic)
    |> Enum.uniq_by(fn f -> {f.plugin, f.name} end)
    |> Enum.sort_by(fn f -> {f.plugin, f.name} end)
    |> Enum.map(fn f ->
      Map.put(f, :typed_schema, HookSchemas.lookup(f.plugin, to_string(f.name)))
    end)
  end

  defp dynamic_signature(%{meta: meta} = export) when is_map(meta) do
    hook_name = Map.get(export, :hook) || Map.get(export, "hook") || Map.get(export, :name)
    doc = Map.get(meta, :description) || Map.get(meta, "description")
    args = Map.get(meta, :args) || Map.get(meta, "args")

    args_list = List.wrap(args)

    names =
      Enum.map(args_list, fn a ->
        Map.get(a, :name) || Map.get(a, "name") || @arg
      end)

    arity = length(names)

    signature =
      case hook_name do
        n when is_binary(n) and n != "" ->
          n <> "(" <> Enum.join(names, ", ") <> ")"

        _ ->
          "(" <> Enum.join(names, ", ") <> ")"
      end

    example_args = Map.get(meta, :example_args) || Map.get(meta, "example_args")

    example_args_text =
      case example_args do
        nil ->
          Jason.encode!(names)

        list when is_list(list) ->
          Jason.encode!(list)

        other ->
          Jason.encode!([other])
      end

    %{arity: arity, signature: signature, doc: doc, example_args: example_args_text}
  end

  defp dynamic_signature(_export), do: %{arity: :custom, signature: nil, doc: nil}
end
