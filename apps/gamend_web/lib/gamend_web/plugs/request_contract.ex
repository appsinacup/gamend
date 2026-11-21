defmodule GamendWeb.Plugs.RequestContract do
  @moduledoc """
  Refuses an API request that does not match its documented operation, before
  the action runs.

  Every value of a request is the client's: a field the spec says is a string
  can arrive as a list, an object, a number or `null`, and an id in the path
  can be any text. An action written for the documented shape crashed on the
  rest (a `FunctionClauseError` answered 500 and wrote an `[error]`). This
  plug casts the path, query and body against the operation's OpenAPI schema
  (`OpenApiSpex.cast_and_validate/5`) and answers a mismatch 422
  `validation_failed`, each field with its messages
  (`GamendWeb.ChangesetErrors.unprocessable/2`), so the spec the SDKs are
  generated from is also the rule the server holds requests to. A path whose
  segments do not match (`/groups/abc`) names nothing, and is answered 404
  `not_found` instead.

  It only checks: `conn.params` and `conn.body_params` stay as Plug parsed
  them (string keys, `replace_params: false`), so no action changes. The cast
  values are in `conn.private.open_api_spex`, unread.

  Every controller plugs it (`use GamendWeb, :controller`), so it runs after
  the router's gates: a caller without a token is told 401 and a non-admin
  403 before their body is read. It acts only where the `:api` pipeline put
  the spec (`OpenApiSpex.Plug.PutApiSpec`); a browser controller passes
  through untouched. A route whose action has no operation is let
  through (an action with `operation :x, false` is one, on purpose);
  `GamendWeb.Api.V1.ApiWrongTypesTest` fails on any `/api` route that has
  none, so that is never by accident. Its twin for responses is
  `GamendWeb.ResponseContract` (test-only).
  """
  @behaviour Plug

  import GamendWeb.Reply, only: [reply_error: 3]

  require Gamend.HttpHeader, as: HttpHeader
  require Logger

  alias GamendWeb.ChangesetErrors
  alias OpenApiSpex.{Cast, Operation, Parameter, PathItem}
  alias OpenApiSpex.Plug.PutApiSpec

  # The types Plug parses into `body_params`: absent (a test's map) included.
  @parsed_types [
    "",
    "application/json",
    "application/x-www-form-urlencoded",
    "multipart/form-data",
    # Phoenix.ConnTest sends a test's params this way.
    "multipart/mixed"
  ]

  @impl true
  def init(opts), do: opts

  @impl true
  def call(
        %{private: %{open_api_spex: _, phoenix_controller: controller, phoenix_action: action}} =
          conn,
        _opts
      ) do
    case operation(conn, controller, action) do
      nil -> conn
      {spec, operation} -> validate(conn, spec, operation)
    end
  end

  def call(conn, _opts), do: conn

  defp operation(conn, controller, action) do
    {spec, lookup} = PutApiSpec.get_spec_and_operation_lookup(conn)

    case lookup[{controller, action}] do
      nil -> documented(conn, spec, controller, action)
      operation -> {spec, operation}
    end
  end

  # Found by the route, as `GamendWeb.ResponseContract` does, never by
  # `open_api_operation/1`: for an action with no `operation` that prints a
  # warning, which would be one a request.
  defp documented(%{private: %{phoenix_router: router}} = conn, spec, controller, action) do
    with %{route: route} <-
           Phoenix.Router.route_info(router, conn.method, conn.request_path, conn.host),
         %PathItem{} = item <- Map.get(spec.paths, openapi_path(route)),
         %Operation{operationId: id} when is_binary(id) <- Map.get(item, method_key(conn.method)) do
      {spec, PutApiSpec.get_and_cache_controller_action(conn, id, {controller, action})}
    else
      _ -> nil
    end
  end

  defp documented(_conn, _spec, _controller, _action), do: nil

  defp openapi_path(route), do: Regex.replace(~r/:(\w+)/, route, "{\\1}")

  defp method_key("GET"), do: :get
  defp method_key("POST"), do: :post
  defp method_key("PUT"), do: :put
  defp method_key("PATCH"), do: :patch
  defp method_key("DELETE"), do: :delete
  defp method_key("HEAD"), do: :head
  defp method_key("OPTIONS"), do: :options
  defp method_key(_method), do: nil

  defp validate(conn, spec, operation) do
    {checked, operation} = conn |> without_empty_query() |> documented_type(operation)

    case OpenApiSpex.cast_and_validate(spec, operation, checked, nil, replace_params: false) do
      {:ok, _cast} ->
        conn

      {:error, errors} ->
        conn |> refuse(errors, path_names(operation)) |> Plug.Conn.halt()
    end
  end

  # A path that does not match (`/groups/abc`, `/auth/twitch`) names nothing:
  # 404, as a route that is not there. Anything else is the body or query's,
  # 422 with each field.
  defp refuse(conn, errors, path_names) do
    fields = Enum.group_by(errors, &field/1, &Cast.Error.message/1)

    # The client's mistake, never ours: info, so it is seen and not alarmed on.
    Logger.info(fn ->
      "RequestContract: refused #{conn.method} #{conn.request_path}: #{inspect(fields, limit: 10)}"
    end)

    if Enum.all?(Map.keys(fields), &(&1 in path_names)),
      do: reply_error(conn, :not_found, "not_found"),
      else: ChangesetErrors.unprocessable(conn, fields)
  end

  defp path_names(%Operation{parameters: parameters}) do
    for %Parameter{in: :path, name: name} <- parameters || [], do: to_string(name)
  end

  # What is checked is what the action reads.
  #
  # A body Plug parsed into params (JSON, a form, a test's map) is checked
  # against the operation's JSON schema whatever type it came as. A raw body
  # (an upload's bytes) is the action's to read: its path and query are
  # checked, not its bytes. And params documented in the query may come in
  # the body (a DELETE's, as Phoenix merges them): both are read there.
  defp documented_type(conn, %Operation{requestBody: %{content: content}} = operation)
       when is_map(content) and map_size(content) > 0 do
    sent =
      conn
      |> Plug.Conn.get_req_header(HttpHeader.content_type())
      |> List.first("")
      |> media_type()

    cond do
      Map.has_key?(content, sent) ->
        {conn, operation}

      sent in @parsed_types ->
        {Plug.Conn.put_req_header(conn, HttpHeader.content_type(), documented(content)),
         operation}

      true ->
        {conn, %{operation | requestBody: nil}}
    end
  end

  defp documented_type(conn, operation) do
    {%{conn | query_params: Map.merge(body_params(conn), conn.query_params)}, operation}
  end

  # An empty query value (`?index`, an SDK's unset parameter) is no value, as
  # every action reads it.
  defp without_empty_query(%{query_params: %{} = query} = conn),
    do: %{conn | query_params: Map.reject(query, fn {_key, value} -> value == "" end)}

  defp without_empty_query(conn), do: conn

  defp body_params(%{body_params: %{} = params}), do: params
  defp body_params(_conn), do: %{}

  defp media_type(header), do: header |> String.split(";") |> hd() |> String.trim()

  defp documented(content) do
    if Map.has_key?(content, "application/json"),
      do: "application/json",
      else: content |> Map.keys() |> hd()
  end

  # literal-ok: the field a whole body's error is reported under
  defp field(%Cast.Error{path: []}), do: "body"
  defp field(%Cast.Error{path: path}), do: Enum.map_join(path, ".", &to_string/1)
end
