defmodule GamendWeb.ContractLint do
  @moduledoc """
  What a client may send or be sent, held to a schema: the checks of
  `mix gamend.contract.lint`.

  Every way in is checked against its declaration before its handler runs
  (`GamendWeb.Plugs.RequestContract`, `GamendWeb.ChannelContract`,
  `GamendWeb.LiveEvents`), and every way out is typed for the SDKs. A check
  is only as good as what it is held to, so this fails on what would leave a
  message untyped:

    * `:api_operation` — an `/api/v1` route with no OpenAPI operation:
      nothing checks its request.
    * `:api_free_form` — a schema in the OpenAPI document that says nothing
      of its value: an object with no `properties` (and no typed
      `additionalProperties`, or `oneOf`/`anyOf`/`allOf`), or a schema with
      no type at all. A value no schema can say (a game's metadata, a
      plugin's arguments, a provider's webhook body) is marked with why:
      `extensions: %{"x-free-form" => "a game's metadata"}`, which
      `GamendWeb.Schemas.FreeForm.schema/1` writes.
    * `:event_protobuf` — a server→client event with no protobuf message in
      `GamendWeb.EventCodec`: sent as JSON only.
    * `:command_type` — a client→server command whose keys
      (`GamendWeb.RealtimeCommands`) are not all `GamendWeb.PayloadContract`
      types.
    * `:live_event` — a LiveView event a `handle_event/3` clause matches
      that no `event/2` declares, or a declaration no clause matches.

  It reads the compiled router, the document and the modules: run it with
  the project compiled (`mix gamend.contract.lint` compiles first). In a
  host it reads the host's router (`config :gamend_web, :router`) and the
  host's own modules.
  """

  alias GamendWeb.PayloadContract

  alias OpenApiSpex.{
    MediaType,
    Operation,
    Parameter,
    PathItem,
    Reference,
    RequestBody,
    Response,
    Schema
  }

  @verbs [:get, :post, :put, :patch, :delete]

  @type offense :: %{rule: atom(), where: String.t(), text: String.t()}

  @doc "Every offense, sorted by rule then place."
  @spec offenses(keyword()) :: [offense()]
  def offenses(opts \\ []) do
    spec = Keyword.get_lazy(opts, :spec, fn -> GamendWeb.ApiSpec.spec() end)
    router = Keyword.get_lazy(opts, :router, &router/0)
    modules = Keyword.get_lazy(opts, :modules, &project_modules/0)

    (api_operations(spec, router) ++
       api_free_forms(spec) ++
       event_protobufs() ++ command_types() ++ live_events(modules))
    |> Enum.sort_by(&{&1.rule, &1.where})
  end

  @doc """
  The free-form values that are marked, with their reasons: what the lint
  accepts, listed so the list stays short and each entry is read.
  """
  @spec free_forms(keyword()) :: [{String.t(), String.t()}]
  def free_forms(opts \\ []) do
    spec = Keyword.get_lazy(opts, :spec, fn -> GamendWeb.ApiSpec.spec() end)

    for {where, %Schema{extensions: %{"x-free-form" => reason}}} <- schemas_in(spec),
        do: {where, reason}
  end

  # ── :api_operation ─────────────────────────────────────────────────────────

  defp api_operations(_spec, nil), do: []

  defp api_operations(spec, router) do
    for route <- Phoenix.Router.routes(router),
        route.verb in @verbs,
        String.starts_with?(route.path, "/api/v1/"),
        not match?(%Operation{}, operation(spec, route.path, route.verb)),
        uniq: true do
      offense(
        :api_operation,
        "#{verb(route.verb)} #{route.path}",
        "no OpenAPI operation (#{inspect(route.plug)}.#{route.plug_opts}), so nothing checks its request"
      )
    end
  end

  defp operation(spec, path, verb) do
    case Map.get(spec.paths || %{}, openapi_path(path)) do
      %PathItem{} = item -> Map.get(item, verb)
      nil -> nil
    end
  end

  defp openapi_path(path), do: Regex.replace(~r/:(\w+)/, path, "{\\1}")

  # ── :api_free_form ─────────────────────────────────────────────────────────

  defp api_free_forms(spec) do
    for {where, %Schema{} = schema} <- schemas_in(spec),
        free_form?(schema),
        not marked?(schema) do
      offense(
        :api_free_form,
        where,
        "a schema that says nothing of its value: give it properties or a type, or mark it " <>
          "`GamendWeb.Schemas.FreeForm.schema(\"why\")`"
      )
    end
  end

  defp marked?(%Schema{extensions: %{"x-free-form" => reason}}) when is_binary(reason),
    do: String.trim(reason) != ""

  defp marked?(_schema), do: false

  defp free_form?(%Schema{} = schema) do
    composed? = Enum.any?([schema.oneOf, schema.anyOf, schema.allOf], &(&1 not in [nil, []]))

    typed_values? =
      match?(%Schema{}, schema.additionalProperties) or
        match?(%Reference{}, schema.additionalProperties) or
        is_atom_schema?(schema.additionalProperties)

    no_properties? = schema.properties in [nil, %{}]

    cond do
      composed? ->
        false

      schema.type == :object ->
        no_properties? and not typed_values?

      is_nil(schema.type) ->
        no_properties? and is_nil(schema.items) and is_nil(schema.enum) and not typed_values?

      true ->
        false
    end
  end

  defp is_atom_schema?(module) when is_atom(module) and module not in [nil, true, false],
    do: function_exported?(module, :schema, 0)

  defp is_atom_schema?(_), do: false

  # Every schema the document holds, named by where it sits: each component
  # and what it nests, and each operation's inline parameter, body and
  # response schemas. A `$ref` is read where it is defined, once.
  defp schemas_in(spec) do
    components =
      for {name, schema} <- (spec.components && spec.components.schemas) || %{},
          found <- walk(schema, "#" <> name),
          do: found

    inline =
      for {path, %PathItem{} = item} <- spec.paths || %{},
          verb <- @verbs,
          %Operation{} = op <- [Map.get(item, verb)],
          found <- operation_schemas(op, "#{verb(verb)} #{path}"),
          do: found

    components ++ inline
  end

  defp operation_schemas(%Operation{} = op, at) do
    params =
      for %Parameter{name: name, schema: schema} <- op.parameters || [],
          found <- walk(schema, "#{at} ?#{name}"),
          do: found

    body =
      case op.requestBody do
        %RequestBody{content: content} when is_map(content) ->
          for {_type, %MediaType{schema: schema}} <- content,
              found <- walk(schema, "#{at} body"),
              do: found

        _ ->
          []
      end

    responses =
      for {status, %Response{content: content}} when is_map(content) <- op.responses || %{},
          {_type, %MediaType{schema: schema}} <- content,
          found <- walk(schema, "#{at} -> #{status}"),
          do: found

    params ++ body ++ responses
  end

  defp walk(%Reference{}, _where), do: []

  defp walk(module, where) when is_atom(module) and module not in [nil, true, false] do
    # A schema module is a component: the document has it under its title, and
    # it is read there. Walking it again here would name it twice.
    if Code.ensure_loaded?(module) and function_exported?(module, :schema, 0),
      do: [],
      else: [{where, module}]
  end

  defp walk(%Schema{} = schema, where) do
    nested =
      Enum.flat_map(schema.properties || %{}, fn {key, value} ->
        walk(value, "#{where}.#{key}")
      end) ++
        walk_one(schema.items, where <> "[]") ++
        walk_one(schema.additionalProperties, where <> "{}") ++
        Enum.flat_map(
          (schema.oneOf || []) ++ (schema.anyOf || []) ++ (schema.allOf || []),
          &walk(&1, where <> "|")
        )

    [{where, schema} | nested]
  end

  defp walk(_other, _where), do: []

  defp walk_one(%Schema{} = schema, where), do: walk(schema, where)
  defp walk_one(_other, _where), do: []

  # ── :event_protobuf ────────────────────────────────────────────────────────

  defp event_protobufs do
    for %{topic: topic, event: event} <- GamendWeb.RealtimeEvents.all(),
        is_nil(GamendWeb.EventCodec.message_name(topic, event)) do
      offense(
        :event_protobuf,
        "#{topic} #{event}",
        "no protobuf message in GamendWeb.EventCodec: a protobuf client gets it as JSON"
      )
    end
  end

  # ── :command_type ──────────────────────────────────────────────────────────

  defp command_types do
    for %{topic: topic, event: event, types: types} <- GamendWeb.RealtimeCommands.all(),
        {key, type} <- types,
        not PayloadContract.valid_type?(type) do
      offense(
        :command_type,
        "#{topic} #{event}",
        "#{key}: #{inspect(type)} is not a declared type"
      )
    end
  end

  # ── :live_event ────────────────────────────────────────────────────────────

  defp live_events(modules) do
    for module <- modules,
        Code.ensure_loaded?(module),
        function_exported?(module, :__live_events__, 1),
        offense <- live_event_offenses(module),
        do: offense
  end

  defp live_event_offenses(module) do
    declared = module.__live_events__(:declared)
    handled = module.__live_events__(:handled)

    undeclared =
      for event <- handled, not Map.has_key?(declared, event) do
        offense(
          :live_event,
          "#{inspect(module)} #{event}",
          "handled with no `event/2` declaration"
        )
      end

    unhandled =
      for event <- Map.keys(declared), event not in handled do
        offense(
          :live_event,
          "#{inspect(module)} #{event}",
          "declared, and no `handle_event/3` clause matches it"
        )
      end

    undeclared ++ unhandled
  end

  # ── Where to look ──────────────────────────────────────────────────────────

  @doc false
  # The router the endpoint dispatches to, as `Gamend.ApiConventions` finds it.
  def router do
    [Application.get_env(:gamend_web, :router), GamendHost.Router, GamendWeb.Router]
    |> Enum.reject(&is_nil/1)
    |> Enum.find(&Code.ensure_loaded?/1)
  end

  @doc false
  # This repository's own modules: a dependency's are its own lint's.
  def project_modules do
    root = File.cwd!()

    for {app, _description, _version} <- Application.loaded_applications(),
        module <- Application.spec(app, :modules) || [],
        own_source?(module, root),
        do: module
  end

  defp own_source?(module, root) do
    with true <- Code.ensure_loaded?(module),
         source when is_list(source) <- module.module_info(:compile)[:source] do
      source = List.to_string(source)
      String.starts_with?(source, root) and not String.contains?(source, "/deps/")
    else
      _ -> false
    end
  end

  defp offense(rule, where, text), do: %{rule: rule, where: where, text: text}

  defp verb(verb), do: verb |> to_string() |> String.upcase()
end
