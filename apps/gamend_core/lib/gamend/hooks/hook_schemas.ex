defmodule Gamend.Hooks.HookSchemas do
  @moduledoc """
  Registry of game-defined protobuf schemas for typed hooks, plus the
  argument/result conversion that makes typed hooks callable from every
  transport and payload format.

  Registration is convention-based, like `Gamend.Hooks.MetadataSchemas`:
  when a plugin loads, its modules are scanned for protobuf message pairs
  named `<FnName>Request` / `<FnName>Reply` — e.g. `HelloProtoRequest` and
  `HelloProtoReply` register the schema for the `hello_proto` hook. The
  plugin function then receives the decoded request struct as its single
  argument and returns a reply struct:

      def hello_proto(%MyGame.V1.HelloProtoRequest{} = req) do
        %MyGame.V1.HelloProtoReply{greeting: "Hello, " <> req.name}
      end

  Because the server converts at the boundary, the same hook is callable
  with binary protobuf (`args_raw` on protobuf DataChannels) and with plain
  JSON objects (WebSocket `call_hook`, JSON DataChannels, admin tester) —
  clients can switch formats at runtime without changing call sites.

  Hooks without a registered schema are dynamic: JSON args are passed as an
  argument list and the result must be JSON-encodable. Binary calls
  (`args_raw`) require a registered schema — there is no opaque relay, so a
  protobuf caller always has a contract on both ends.
  """

  require Logger

  alias Gamend.Hooks.PluginManager

  @pt_key {__MODULE__, :schemas}

  @doc "Returns the registered schema for a hook, or nil."
  @spec lookup(String.t(), String.t()) :: %{request: module(), reply: module()} | nil
  def lookup(plugin, fn_name) do
    Map.get(all(), {plugin, fn_name})
  end

  @doc "Returns the full {plugin, fn} -> schema registry (for the admin overview)."
  @spec all() :: %{{String.t(), String.t()} => %{request: module(), reply: module()}}
  def all, do: :persistent_term.get(@pt_key, %{})

  @doc "Rebuilds the registry from the loaded plugin list."
  @spec refresh([struct()]) :: :ok
  def refresh(plugins) do
    schemas =
      plugins
      |> Enum.filter(&(&1.status == :ok))
      |> Enum.reduce(%{}, &register_plugin/2)

    :persistent_term.put(@pt_key, schemas)

    if schemas != %{} do
      Logger.info("typed hook schemas registered: #{inspect(Map.keys(schemas))}")
    end

    :ok
  end

  defp register_plugin(plugin, acc) do
    modules = plugin.modules || []
    by_name = Map.new(modules, &{&1 |> Atom.to_string() |> String.split(".") |> List.last(), &1})

    Enum.reduce(by_name, acc, fn {last, req_mod}, acc ->
      with true <- String.ends_with?(last, "Request"),
           base = String.trim_trailing(last, "Request"),
           {:ok, reply_mod} <- Map.fetch(by_name, base <> "Reply"),
           true <- message_module?(req_mod) and message_module?(reply_mod) do
        Map.put(acc, {plugin.name, Macro.underscore(base)}, %{request: req_mod, reply: reply_mod})
      else
        _ -> acc
      end
    end)
  end

  defp message_module?(mod) do
    Code.ensure_loaded?(mod) and function_exported?(mod, :__message_props__, 0) and
      function_exported?(mod, :encode, 1)
  end

  # ── Conversion ───────────────────────────────────────────────────────────

  @doc """
  Calls a hook with transport-level arguments, converting through the
  registered schema when one exists.

  `args_input` is `{:raw, binary}` (protobuf-encoded request bytes) or
  `{:list, args}` (JSON argument list; for typed hooks a single object —
  or no argument — that decodes into the request message).

  `wire` selects the result encoding: `:binary` returns `{:ok, {:raw, bytes}}`
  (protobuf-encoded reply), `:map` returns `{:ok, json_encodable}`.
  """
  @spec call(
          String.t(),
          String.t(),
          {:raw, binary()} | {:list, list()},
          :binary | :map,
          keyword()
        ) ::
          {:ok, {:raw, binary()} | term()} | {:error, term()}
  def call(plugin, fn_name, args_input, wire, opts) do
    schema = lookup(plugin, fn_name)

    with {:ok, args} <- build_args(schema, args_input),
         {:ok, result} <- PluginManager.call_rpc(plugin, fn_name, args, opts) do
      encode_result(schema, result, wire)
    end
  end

  # Binary calls require a schema — no opaque relay.
  defp build_args(nil, {:raw, _raw}), do: {:error, :hook_schema_missing}
  defp build_args(nil, {:list, args}), do: {:ok, args}

  defp build_args(%{request: req_mod}, {:raw, raw}) do
    {:ok, [req_mod.decode(raw)]}
  rescue
    _ -> {:error, :invalid_request_payload}
  end

  defp build_args(%{request: req_mod}, {:list, args}) do
    case args do
      [] -> {:ok, [struct(req_mod)]}
      [map] when is_map(map) -> decode_json_request(req_mod, map)
      _ -> {:error, :typed_hook_expects_single_object_arg}
    end
  end

  defp decode_json_request(req_mod, map) do
    case Protobuf.JSON.from_decoded(map, req_mod) do
      {:ok, struct} -> {:ok, [struct]}
      {:error, _} -> {:error, :invalid_request_payload}
    end
  end

  # Typed replies encode per the requested wire format.
  defp encode_result(%{reply: reply_mod}, %mod{} = result, wire) when mod == reply_mod do
    case wire do
      :binary ->
        {:ok, {:raw, Protobuf.encode(result)}}

      :map ->
        case Protobuf.JSON.to_encodable(result, use_proto_names: true) do
          {:ok, map} -> {:ok, map}
          {:error, _} -> {:error, :invalid_reply_payload}
        end
    end
  rescue
    _ -> {:error, :invalid_reply_payload}
  end

  # A {:raw, binary} return has no defined contract on the wire without a
  # registered schema, so it is refused.
  defp encode_result(nil, {:raw, _}, _wire), do: {:error, :raw_reply_unsupported}

  # Dynamic results pass through; the caller JSON-encodes for its transport.
  defp encode_result(nil, result, _wire), do: {:ok, result}

  # A typed hook returned something that isn't its reply message.
  defp encode_result(%{reply: reply_mod}, _result, _wire),
    do: {:error, {:expected_reply_struct, reply_mod}}
end
