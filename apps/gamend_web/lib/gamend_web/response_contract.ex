defmodule GamendWeb.ResponseContract do
  @moduledoc """
  Test-only: fails any API response that does not match the OpenAPI schema
  documented for it.

  The endpoint plugs this in when `config :gamend_web, :response_contract,
  true` is set at compile time (only `config/test.exs` does). Before each JSON
  response from a documented operation, it checks that:

    1. the body casts against the schema documented for the status;
    2. no object carries a key its schema does not declare — the drift a typed
       SDK would silently drop;
    3. a 2xx status is documented. An undocumented error status must still be
       an `ErrorResponse`: every error is that one type, so an unlisted status
       costs a client nothing;
    4. a response documented as a bare `type: object` really is `{}`;
    5. an error's `error` is a snake_case code, and `errors` appears only
       with `validation_failed` (422, or 409 for a uniqueness clash).

  A violation raises inside the request, so every controller test is also a
  contract test without being edited. Raising stops a test at its first
  violation; to see all of a domain's drift in one run, set
  `RESPONSE_CONTRACT_REPORT=<file>` and violations are appended there instead.
  The check only sees what the tests request: `RESPONSE_CONTRACT_SEEN=<file>`
  records each checked operation and status, which shows the ones no test
  reaches. Both are environment variables rather than declared settings
  because they switch a single test run, not a server.

  Every documented operation is checked. It started as a ratchet over a list
  of tags, one domain at a time (`docs/specs/named-api-schemas.md`); the list
  went once every domain was in, so a new endpoint is held to its schema from
  its first test.
  """
  @behaviour Plug

  alias OpenApiSpex.{Cast, Operation, PathItem, Reference, Response, Schema}
  alias OpenApiSpex.Plug.PutApiSpec

  require Gamend.HttpHeader, as: HttpHeader

  @json "json"

  defmodule Violation do
    @moduledoc "A response that contradicts its documented schema."
    defexception [:message]
  end

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts), do: Plug.Conn.register_before_send(conn, &check/1)

  @doc false
  @spec check(Plug.Conn.t()) :: Plug.Conn.t()
  def check(conn) do
    with true <- json?(conn),
         {:ok, spec, operation} <- operation(conn) do
      verify(conn, spec, operation)
    end

    conn
  end

  # A 5xx is already a failure, and it is also the page Phoenix renders after a
  # violation raised — checking it would replace the real message with its own.
  defp json?(conn) do
    conn.status != 204 and conn.status < 500 and
      Enum.any?(Plug.Conn.get_resp_header(conn, HttpHeader.content_type()), &(&1 =~ @json))
  end

  # The spec is only on conns that went through the `:api` pipeline, which is
  # also exactly the set of responses the document describes.
  defp operation(%Plug.Conn{private: %{open_api_spex: _, phoenix_router: router}} = conn) do
    {spec, _lookup} = PutApiSpec.get_spec_and_operation_lookup(conn)

    with %{route: route} <-
           Phoenix.Router.route_info(router, conn.method, conn.request_path, conn.host),
         %PathItem{} = item <- Map.get(spec.paths, openapi_path(route)),
         %Operation{} = operation <- Map.get(item, method_key(conn.method)) do
      {:ok, spec, operation}
    else
      _ -> :skip
    end
  end

  defp operation(_conn), do: :skip

  defp openapi_path(route), do: Regex.replace(~r/:(\w+)/, route, "{\\1}")

  defp method_key(method), do: method |> String.downcase() |> String.to_existing_atom()

  defp verify(conn, spec, operation) do
    with path when is_binary(path) <- System.get_env("RESPONSE_CONTRACT_SEEN") do
      File.write!(path, "#{operation.operationId} #{conn.status}\n", [:append])
    end

    case documented_schema(operation, conn.status) do
      %{} = schema ->
        verify_body(conn, spec.components.schemas, operation, schema)

      nil when conn.status >= 400 ->
        error = %Reference{"$ref": "#/components/schemas/ErrorResponse"}
        verify_body(conn, spec.components.schemas, operation, error)

      nil ->
        violation!(conn, operation, "status #{conn.status} is not documented")
    end
  end

  defp verify_body(conn, schemas, operation, schema) do
    body = Jason.decode!(conn.resp_body)

    case Cast.cast(schema, body, schemas) do
      {:ok, _} ->
        :ok

      {:error, errors} ->
        violation!(conn, operation, Enum.map_join(errors, "; ", &Cast.Error.message_with_path/1))
    end

    case undeclared(schema, body, schemas, "") ++ unlisted(schema, body, schemas) do
      [] -> :ok
      paths -> violation!(conn, operation, "undeclared keys: " <> Enum.join(paths, ", "))
    end

    if conn.status >= 400, do: error_rules(conn, operation, body)
  end

  # R12 and R15: an error is a snake_case code a client can switch on, and
  # field detail rides only on `validation_failed`, which is 422 — or 409 for
  # a uniqueness clash.
  defp error_rules(conn, operation, %{"error" => code} = body) do
    unless is_binary(code) and code =~ ~r/^[a-z][a-z0-9_]*$/ do
      violation!(conn, operation, "error #{inspect(code)} is not a snake_case code")
    end

    if Map.has_key?(body, "errors") and
         (code != "validation_failed" or conn.status not in [409, 422]) do
      violation!(conn, operation, "errors belongs to validation_failed, answered 422 or 409")
    end
  end

  defp error_rules(_conn, _operation, _body), do: :ok

  # A response documented as a bare `type: object` accepts anything, so a body
  # with keys in it is a body nobody wrote down — and a generator emits no type
  # for it. A response that really is a free-form map says so with
  # `additionalProperties`. Nested bare objects (metadata, KV values) are
  # free-form by design and are not checked.
  defp unlisted(%Reference{} = ref, body, schemas),
    do: unlisted(resolve(ref, schemas), body, schemas)

  defp unlisted(%Schema{type: :object, properties: nil, additionalProperties: nil}, body, _)
       when is_map(body),
       do: Enum.map(Map.keys(body), &".#{&1}")

  defp unlisted(_schema, _body, _schemas), do: []

  defp documented_schema(%Operation{responses: responses}, status) do
    case Map.get(responses || %{}, status) || Map.get(responses || %{}, to_string(status)) do
      %Response{content: %{"application/json" => %{schema: schema}}} -> schema
      _ -> nil
    end
  end

  # Keys present in the body that no schema on their path declares. Objects
  # with `additionalProperties` are maps by design; composed schemas
  # (allOf/oneOf/anyOf) are left to the cast.
  defp undeclared(%Reference{} = ref, value, schemas, path),
    do: undeclared(resolve(ref, schemas), value, schemas, path)

  defp undeclared(%Schema{additionalProperties: %Schema{} = inner}, value, schemas, path)
       when is_map(value) do
    Enum.flat_map(value, fn {key, v} -> undeclared(inner, v, schemas, "#{path}.#{key}") end)
  end

  defp undeclared(
         %Schema{properties: %{} = properties, additionalProperties: nil},
         value,
         schemas,
         path
       )
       when is_map(value) do
    declared = Map.new(properties, fn {key, schema} -> {to_string(key), schema} end)

    Enum.flat_map(value, fn {key, v} ->
      case Map.fetch(declared, key) do
        {:ok, schema} -> undeclared(schema, v, schemas, "#{path}.#{key}")
        :error -> ["#{path}.#{key}"]
      end
    end)
  end

  defp undeclared(%Schema{type: :array, items: items}, value, schemas, path)
       when is_list(value) and not is_nil(items) do
    value
    |> Enum.with_index()
    |> Enum.flat_map(fn {v, i} -> undeclared(items, v, schemas, "#{path}[#{i}]") end)
  end

  defp undeclared(_schema, _value, _schemas, _path), do: []

  defp resolve(%Reference{"$ref": "#/components/schemas/" <> name}, schemas),
    do: Map.fetch!(schemas, name)

  defp violation!(conn, %Operation{operationId: id}, message) do
    message =
      "#{conn.method} #{conn.request_path} (#{id}) -> #{conn.status}: #{message}\n" <>
        "body: #{conn.resp_body}"

    case System.get_env("RESPONSE_CONTRACT_REPORT") do
      nil -> raise Violation, message: message
      path -> File.write!(path, message <> "\n", [:append])
    end
  end
end
