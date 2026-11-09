defmodule GamendWeb.Api.V1.HookController do
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gamend.Accounts.Scope
  alias Gamend.Hooks.DynamicRpcs
  alias Gamend.Hooks.HookSchemas
  alias Gamend.Hooks.PluginManager
  alias GamendWeb.HookErrors
  alias GamendWeb.Pagination
  alias GamendWeb.Schemas
  alias GamendWeb.Schemas.{HookCallResponse, HookFunctionPage}
  alias OpenApiSpex.Schema
  require Logger
  require GamendWeb.ChannelError, as: ChannelError
  require GamendWeb.HookErrors.HookErrorCode, as: HookErrorCode

  @call_hook "call_hook"

  @arg "arg"

  operation(:index,
    operation_id: "list_hooks",
    summary: "List available hook functions",
    description: "Every function `POST /hooks/call` accepts, by plugin then name.",
    tags: ["Hooks"],
    security: [%{"authorization" => []}],
    parameters: [
      page: [in: :query, schema: %Schema{type: :integer, default: 1}, required: false],
      page_size: [in: :query, schema: %Schema{type: :integer, default: 25}, required: false]
    ],
    responses: [
      ok: {"Callable functions", "application/json", HookFunctionPage},
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  def index(conn, params) do
    static_functions =
      PluginManager.rpc_modules()
      |> Enum.flat_map(fn {plugin_name, mod} ->
        Gamend.Hooks.exported_functions(mod)
        |> Enum.map(&Map.merge(&1, %{plugin: plugin_name, dynamic: false, meta: %{}}))
      end)

    static_keys =
      static_functions
      |> Enum.map(&{&1.plugin, &1.name})
      |> MapSet.new()

    dynamic_functions =
      DynamicRpcs.list_all()
      |> Enum.flat_map(fn {plugin_name, exports} ->
        Enum.map(exports, fn export ->
          args = Map.get(export.meta || %{}, :args) || Map.get(export.meta || %{}, "args")
          args_list = List.wrap(args)

          arg_names =
            Enum.map(args_list, fn a ->
              Map.get(a, :name) || Map.get(a, "name") || @arg
            end)

          arity = length(arg_names)

          doc =
            Map.get(export.meta || %{}, :description) ||
              Map.get(export.meta || %{}, "description")

          signature = to_string(export.hook) <> "(" <> Enum.join(arg_names, ", ") <> ")"

          %{
            plugin: plugin_name,
            name: export.hook,
            dynamic: true,
            meta: export.meta || %{},
            arities: [arity],
            signatures: [
              %{
                arity: arity,
                signature: signature,
                doc: doc || "",
                example_args: Jason.encode!(arg_names)
              }
            ]
          }
        end)
      end)
      |> Enum.reject(fn f -> MapSet.member?(static_keys, {f.plugin, f.name}) end)

    functions =
      (static_functions ++ dynamic_functions)
      |> Enum.sort_by(&{&1.plugin, &1.name})
      |> Enum.map(&serialize_function/1)

    {page, page_size} = Pagination.params(params)
    rows = functions |> Enum.drop((page - 1) * page_size) |> Enum.take(page_size)

    reply_page(conn, rows, page, page_size, length(functions))
  end

  # `fn`, as `call_hook` takes it: a thing is not called `name` (R16).
  defp serialize_function(function) do
    %{
      plugin: to_string(function.plugin),
      fn: to_string(function.name),
      dynamic: function.dynamic,
      arities: function.arities,
      signatures: Enum.map(function.signatures, &serialize_signature/1),
      meta: function.meta
    }
  end

  defp serialize_signature(signature) do
    %{
      arity: signature.arity,
      signature: to_string(signature.signature || ""),
      doc: to_string(signature.doc || ""),
      example_args: to_string(signature.example_args || "")
    }
  end

  @json_schema %OpenApiSpex.Schema{
    description: "JSON object with arbitrary properties",
    type: :object,
    additionalProperties: true
  }

  operation(:invoke,
    operation_id: @call_hook,
    summary: "Invoke a hook function",
    description: """
    Calls `fn` in `plugin` with `args` and answers what it returned under
    `data`. Refusals: `missing_param` (no `plugin` or `fn`), `too_many_args`,
    `reserved_hook_name` (400); `args_too_large` (413); `plugin_not_found`,
    `not_implemented` (404: no such plugin, or no such function at that arity);
    `timeout` (504). An error the hook itself returns answers 400: its reason
    as the code when that is a snake_case atom, otherwise `hook_error`, with
    any detail in `message`; arguments none of its clauses accept answer
    `function_clause`. A hook that raises answers 500 `exception`, with no
    detail: the server log has the stack trace.
    """,
    tags: ["Hooks"],
    security: [%{"authorization" => []}],
    request_body:
      {"Call hook", "application/json",
       %OpenApiSpex.Schema{
         type: :object,
         properties: %{
           plugin: %OpenApiSpex.Schema{type: :string},
           fn: %OpenApiSpex.Schema{type: :string},
           args: %OpenApiSpex.Schema{type: :array, items: @json_schema}
         },
         required: [:plugin, :fn]
       }},
    responses: [
      ok: {"What the hook returned", "application/json", HookCallResponse},
      bad_request: Schemas.error("Malformed call, or the hook returned an error"),
      not_found: Schemas.error("No such plugin or function"),
      request_entity_too_large: Schemas.error("Arguments too large"),
      internal_server_error: Schemas.error("The hook raised (`exception`)"),
      gateway_timeout: Schemas.error("The hook timed out"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  def invoke(conn, %{"plugin" => plugin, "fn" => fn_name} = params)
      when is_binary(plugin) and is_binary(fn_name) do
    user = Scope.user(conn.assigns.current_scope)
    args = Map.get(params, "args", [])

    args = if is_list(args), do: args, else: [args]

    max_count = Gamend.Limits.get(:max_hook_args_count)
    max_size = Gamend.Limits.get(:max_hook_args_size)

    args_too_many = length(args) > max_count

    args_too_large =
      case Jason.encode(args) do
        {:ok, encoded} -> byte_size(encoded) > max_size
        _ -> true
      end

    hook = hook_label(plugin, fn_name, length(args))

    cond do
      args_too_many ->
        log_rejected(hook, "too_many_args (#{length(args)} > #{max_count})")
        reply_error(conn, :bad_request, "too_many_args", "at most #{max_count} arguments")

      args_too_large ->
        log_rejected(hook, "args_too_large (> #{max_size} bytes)")

        reply_error(
          conn,
          :request_entity_too_large,
          "args_too_large",
          "at most #{max_size} bytes"
        )

      reserved_hook_name?(fn_name) ->
        log_rejected(hook, ChannelError.reserved_hook_name())

        reply_error(conn, :bad_request, "reserved_hook_name")

      true ->
        # Typed hooks (registered <FnName>Request/<FnName>Reply schemas) accept
        # a single JSON object argument and reply with a JSON map; untyped
        # hooks pass through unchanged.
        reply_to_hook_call(
          conn,
          HookSchemas.call(plugin, fn_name, {:list, args}, :map, caller: user),
          hook
        )
    end
  end

  def invoke(conn, _params) do
    log_rejected("(unparseable)", "invalid_request — missing or non-string plugin/fn")
    reply_error(conn, :bad_request, "missing_param", "plugin and fn are required strings")
  end

  defp reply_to_hook_call(conn, result, hook) do
    case result do
      {:ok, res} ->
        reply_data(conn, res)

      {:error, :not_implemented} ->
        # Almost always a version skew: the client calls a hook the deployed
        # plugin build does not export yet. Silent here, this cost an afternoon.
        log_rejected(hook, "not_implemented — plugin exports no such function/arity")
        reply_error(conn, :not_found, "not_implemented")

      {:error, :not_found} ->
        log_rejected(hook, "plugin_not_found")
        reply_error(conn, :not_found, "plugin_not_found")

      {:error, :missing_hooks_module} ->
        log_rejected(hook, "missing_hooks_module")
        reply_error(conn, :not_found, "missing_hooks_module")

      {:error, :timeout} ->
        log_rejected(hook, HookErrorCode.timeout())
        reply_error(conn, :gateway_timeout, "timeout")

      # Logged with its stack trace by `Gamend.Hooks`; the client gets no detail.
      {:error, {:exception, _}} ->
        reply_error(conn, :internal_server_error, "exception")

      {:error, reason} ->
        log_rejected(hook, inspect(reason))

        {code, message} = HookErrors.describe(reason)
        # open-error: the plugin's own reasons, whose codes the game defines
        reply_error(conn, :bad_request, code, message)
    end
  end

  defp hook_label(plugin, fn_name, arity), do: "#{plugin}.#{fn_name}/#{arity}"

  # Every rejected hook call says which hook and why. Deliberately no argument
  # values: they carry user data, and the hook plus arity is what identifies the
  # problem. The client only ever sees a 4xx status, so without this line
  # a rejection is invisible on both ends.
  defp log_rejected(hook, reason) do
    Logger.warning("hooks/call rejected: #{hook} — #{reason}")
  end

  defp reserved_hook_name?(fn_name) when is_binary(fn_name) do
    Gamend.Hooks.internal_hooks()
    |> Enum.any?(fn atom -> to_string(atom) == fn_name end)
  end
end
