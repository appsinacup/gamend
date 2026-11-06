defmodule Gamend.ApiConventions do
  @moduledoc """
  Mechanical checks for the conventions in `docs/specs/api-conventions.md`.

  Source-level, not runtime: the rules are about how code is *written*
  (field names, serializer shapes, route paths), so they are checked by
  parsing files rather than by introspecting a booted app. `mix gamend.api.lint`
  runs them; CI fails on any violation.

  These exist because the conventions were implicit for a year and drifted
  exactly where nobody was looking — 16 fields serialized `null` against a
  documented "never null" policy, OpenAPI schemas contradicted their own
  serializers, and one duration setting shipped with no unit in its name.
  A convention nothing enforces is a suggestion.
  """

  @type violation :: %{
          rule: String.t(),
          file: String.t(),
          line: pos_integer(),
          message: String.t()
        }

  # The same checks run in every host repo (the starter, downstream games), where
  # core/web live under deps and the host's own code under lib/ and
  # modules/*/lib - so the scan roots are discovered, not hardcoded. Only
  # directories that exist take part.
  @schema_roots ["apps/gamend_core/lib", "lib", "modules"]
  @source_roots ["apps/gamend_web/lib", "lib", "modules"]

  defp schema_dirs, do: existing([dep_dir("gamend_core") | @schema_roots])
  defp source_dirs, do: existing([dep_dir("gamend_web") | @source_roots])

  # In a host repo core/web are deps; their code obeys the rules too, and a
  # violation there means the host pulled a bad version - worth failing on.
  defp dep_dir(app), do: Path.join(["deps", app, "apps", app, "lib"])

  defp existing(paths), do: paths |> Enum.filter(&File.dir?/1) |> Enum.uniq()

  # Durations must name their unit. `_at` is for instants, not durations.
  @duration_units ~w(ms sec seconds min minutes hours days)
  @duration_stems ~w(timeout interval grace window ttl delay debounce backoff
                     lifetime cooldown)

  @doc "Every violation, ordered by rule then file."
  @spec violations() :: [violation()]
  def violations do
    (nullable_strings_not_coalesced() ++
       derived_encoders_with_nullable_strings() ++
       instants_not_suffixed() ++
       durations_without_unit() ++
       hyphenated_route_paths() ++
       nullable_string_schemas() ++
       hand_rolled_meta() ++
       hand_rolled_page_params() ++
       hand_rolled_changeset_errors() ++
       hand_rolled_context_paging() ++
       inline_display_name_fallback() ++
       stale_documented_routes() ++
       role_named_predicates() ++
       inline_ownership_checks() ++
       unnamed_responses() ++
       raising_lookups_at_boundaries() ++
       open_error_answers())
    |> Enum.sort_by(&{&1.rule, &1.file, &1.line})
  end

  # ── R1: nullable string/map fields must be coalesced when serialized ───────
  #
  # The API's null policy (see the spec): a string is never `null`, an unset
  # one is `""`. Godot's JSON parsing crashes where it expects a string.

  defp nullable_strings_not_coalesced do
    nullable = nullable_schema_fields()

    for {file, line, text} <- source_lines(source_dirs()),
        # Only code that writes JSON responses: a `key: var.field` line in a
        # context is usually changeset attrs, where nil is fine.
        String.contains?(file, "_web/"),
        not live_view?(file),
        [_, key, _var, field] <- [Regex.run(~r/^\s*(\w+): ([a-z_]+)\.(\w+),?\s*$/, text)],
        Map.has_key?(nullable, field),
        not String.contains?(text, "||") do
      %{
        rule: "R1-null-string",
        file: file,
        line: line,
        message: ~s(`#{key}: ...#{field}` may serialize null \(#{nullable[field]}\); coalesce it)
      }
    end
  end

  # ── R2: schemas with nullable strings must not use @derive Jason.Encoder ───
  #
  # `@derive` emits the raw value, so a nil string becomes `null` — bypassing
  # every serializer. Such schemas encode through `Gamend.SchemaJSON`.

  defp derived_encoders_with_nullable_strings do
    for {file, line, text} <- source_lines(schema_dirs()),
        String.contains?(text, "@derive {Jason.Encoder"),
        schema_has_nullable_string?(file) do
      %{
        rule: "R2-derive-encoder",
        file: file,
        line: line,
        message: "schema has nullable string/map fields; encode via Gamend.SchemaJSON instead"
      }
    end
  end

  # ── R3: instants are `*_at`, and nothing else is ───────────────────────────

  defp instants_not_suffixed do
    for {file, line, text} <- source_lines(schema_dirs()),
        [_, field] <- [Regex.run(~r/^\s*field :(\w+), :utc_datetime/, text)],
        not String.ends_with?(field, "_at") do
      %{
        rule: "R3-instant-suffix",
        file: file,
        line: line,
        message: "`#{field}` is an instant; name it `#{field}_at`"
      }
    end
  end

  # ── R4: durations name their unit ──────────────────────────────────────────

  defp durations_without_unit do
    for {file, line, text} <- source_lines(schema_dirs() ++ source_dirs()),
        [_, name] <- [Regex.run(~r/^\s*setting\(?:(\w+), :integer/, text)],
        duration_name?(name),
        not unit_suffixed?(name) do
      %{
        rule: "R4-duration-unit",
        file: file,
        line: line,
        message: "`#{name}` is a duration; suffix the unit (#{Enum.join(@duration_units, "|")})"
      }
    end
  end

  # Whole segments only: "max_page_size" must not match the stem "age".
  defp duration_name?(name) do
    name |> String.split("_") |> Enum.any?(&(&1 in @duration_stems))
  end

  defp unit_suffixed?(name), do: Enum.any?(@duration_units, &String.ends_with?(name, "_" <> &1))

  # ── R5: route paths use underscores ────────────────────────────────────────

  # A path that names a file is spelled the way the world spells that file:
  # `sitemap.xml`, `llms-full.txt`, `.well-known`. The rule is about the
  # paths this app coins.
  defp hyphenated_route_paths do
    for {file, line, text} <- source_lines(source_dirs()),
        String.contains?(file, "router"),
        [_, verb, path] <-
          [Regex.run(~r/^\s*(get|post|put|patch|delete|live) "(\/[^"]*)"/, text)],
        String.contains?(path, "-"),
        not Regex.match?(~r/\.[a-z0-9]+$/, path) do
      %{
        rule: "R5-path-underscore",
        file: file,
        line: line,
        message: ~s|#{verb} "#{path}" is hyphenated; API and page paths use underscores|
      }
    end
  end

  # ── R6: OpenAPI must not declare a string field nullable ───────────────────
  #
  # A schema saying `nullable: true` where the serializer emits `""` is a lie
  # clients generate code from. Datetimes keep `nullable` — absence is
  # semantic there (`ends_at: null` = permanent).

  defp nullable_string_schemas do
    for {file, line, text} <- source_lines(source_dirs()),
        String.contains?(text, "nullable: true"),
        String.contains?(text, "type: :string"),
        not Regex.match?(~r/format: :?"?date/, text),
        [_, field] <- [Regex.run(~r/^\s*(\w+): %Schema\{/, text)] do
      %{
        rule: "R6-schema-nullable",
        file: file,
        line: line,
        message: "`#{field}` is a string; drop `nullable: true` (unset serializes as \"\")"
      }
    end
  end

  # ── R7: pagination meta comes from Pagination.meta/4 ───────────────────────
  #
  # `total_pages` and `has_more` are meta-only keys; a controller computing
  # either is building the shape by hand, which is how endpoints ended up
  # emitting three, four and six keys.

  defp hand_rolled_meta do
    for {file, line, text} <- source_lines(source_dirs()),
        controller?(file),
        Regex.match?(~r/^\s*(total_pages|has_more):/, text),
        not String.contains?(text, "%Schema{") do
      %{
        rule: "R7-meta-helper",
        file: file,
        line: line,
        message: "build pagination meta with GamendWeb.Pagination.meta/4"
      }
    end
  end

  # ── R14: one way to name a user ───────────────────────────────────────────
  #
  # Four inline fallbacks were in use at once. Parties wrote
  # `display_name || ""`, so an invite from a player who had set no display
  # name arrived from nobody; group invites wrote `display_name || username`;
  # three admin views fell through to the email and then the raw id.

  defp inline_display_name_fallback do
    for {file, line, text} <- source_lines(schema_dirs() ++ source_dirs()),
        not String.ends_with?(file, "accounts.ex"),
        # `display_name: user.display_name || ""` is R1's null coalescing on the
        # field itself, not a name fallback. Only a fallback to *another* value
        # is one.
        Regex.match?(~r/\.display_name\s*\|\|\s*[^\s"]/, text) do
      %{
        rule: "R14-display-name",
        file: file,
        line: line,
        message:
          "name a user with Gamend.Accounts.display_name/1, " <>
            "or display_label/1 where the handle disambiguates"
      }
    end
  end

  # ── R13: contexts window queries through Gamend.Query ─────────────────────
  #
  # Seven contexts each had a private `paginate/2`, in four behaviours. Three
  # applied `:page_size` unclamped, so a plugin calling the context directly
  # could ask for a million rows; two clamped to a hard-coded 1000 that ignored
  # the configurable `max_page_size`. R8 covers the controller layer, which is
  # not the layer a plugin calls.

  defp hand_rolled_context_paging do
    for {file, line, text} <- source_lines(schema_dirs()),
        not String.ends_with?(file, "query.ex"),
        # Mix tasks are not context listings; a sampling `limit` is theirs to set.
        not String.contains?(file, "/mix/tasks/"),
        Regex.match?(~r/^\s*\|>\s*(limit|offset)\(\^/, text) do
      %{
        rule: "R13-context-paging",
        file: file,
        line: line,
        message:
          "window a listing with Gamend.Query.page/2 or maybe_page/2, " <>
            "or clamp with Gamend.Limits.clamp_page/1 and clamp_page_size/2"
      }
    end
  end

  # ── R12: changeset errors go through GamendWeb.ChangesetErrors ────────────
  #
  # Forty-six sites serialized them by hand in three payload shapes under three
  # envelope keys. Seventeen left the raw `{msg, opts}` tuple in the map, which
  # Jason cannot encode — those endpoints answered 500 where their own OpenAPI
  # operation documented a 422.

  defp hand_rolled_changeset_errors do
    for {file, line, text} <- source_lines(source_dirs()),
        controller?(file),
        String.contains?(text, "Ecto.Changeset.traverse_errors") do
      %{
        rule: "R12-changeset-errors",
        file: file,
        line: line,
        message:
          "answer a failed changeset with unprocessable/2, or " <>
            "GamendWeb.ChangesetErrors.errors/1 when the status must differ"
      }
    end
  end

  # ── R8: the page window comes from Pagination.params/1 ────────────────────
  #
  # Four controllers each had a private `parse_int/2` and a literal
  # `min(size, 100)`, which ignored the configurable `max_page_size` limit.

  defp hand_rolled_page_params do
    for {file, line, text} <- source_lines(source_dirs()),
        controller?(file),
        String.contains?(text, ~s(params["page_size"])) or
          String.contains?(text, ~s(params["page"])) do
      %{
        rule: "R8-page-params",
        file: file,
        line: line,
        message: "read the page window with GamendWeb.Pagination.params/1"
      }
    end
  end

  defp controller?(file), do: String.contains?(file, "/controllers/")

  # ── R9: docs reference only routes that exist ──────────────────────────────
  #
  # Guides and specs name concrete `/api/v1/...` paths; a rename that misses
  # one leaves documentation teaching a 404. Prefixes of real routes are fine
  # ("endpoints live under /api/v1/chat"), as are file paths.

  @doc_dirs ["priv/docs", "docs"]

  defp stale_documented_routes do
    case declared_route_paths() do
      [] -> []
      declared -> stale_documented_routes(declared)
    end
  end

  # A design spec for a feature that has not been built yet is *supposed* to name
  # routes that do not exist — that is what a spec is. This rule is about
  # shipped documentation drifting out of step with a rename, so such a document
  # opts out by declaring itself, on any line:
  #
  #     <!-- api-lint: unimplemented -->
  #
  # Deliberately a per-file marker rather than skipping `docs/specs/` wholesale:
  # a spec that describes something already shipped (load-testing.md cites real
  # endpoints) should still be checked, and the marker has to be deleted when
  # the feature lands, which is the moment the routes become checkable.
  @unimplemented_marker "api-lint: unimplemented"

  defp stale_documented_routes(declared) do
    for dir <- @doc_dirs,
        file <- Path.wildcard(Path.join(dir, "**/*.md")),
        contents = File.read!(file),
        not String.contains?(contents, @unimplemented_marker),
        {text, line} <- contents |> String.split("\n") |> Enum.with_index(1),
        path <- documented_api_paths(text),
        not known_or_prefix?(path, declared) do
      %{
        rule: "R9-doc-route",
        file: file,
        line: line,
        message: "documents `#{path}`, which matches no declared route"
      }
    end
  end

  defp documented_api_paths(line) do
    ~r|/api/v1/[A-Za-z0-9_\-/:{}]*[A-Za-z0-9_}]|
    |> Regex.scan(line)
    |> List.flatten()
    |> Enum.reject(&(String.contains?(&1, "controller") or String.ends_with?(&1, ".ex")))
    |> Enum.map(&normalize_path/1)
  end

  defp normalize_path(path) do
    Regex.replace(~r/(:\w+|\{\w+\})/, path, "{}")
  end

  # A documented path is fine when a declared route matches it — params on
  # either side are wildcards, so `/payments/validate/google` satisfies
  # `/payments/validate/{}` — or when it is a prefix of one ("endpoints live
  # under /api/v1/chat").
  defp known_or_prefix?(path, declared) do
    Enum.any?(declared, fn route ->
      Regex.match?(wildcard_regex(route, ""), path) or
        Regex.match?(wildcard_regex(path, "(/|$)"), route)
    end)
  end

  defp wildcard_regex(pattern, tail) do
    inner =
      pattern
      |> Regex.escape()
      |> String.replace("\\{\\}", "[^/]+")

    Regex.compile!("^" <> inner <> if(tail == "", do: "$", else: tail))
  end

  @doc """
  Every path the compiled router serves, `:params` as `{}`.

  Read from `Phoenix.Router.routes/1` rather than parsed from source — routes
  live inside `scope` blocks, so the literal strings in the source are
  suffixes, not full paths.
  """
  @spec declared_route_paths() :: [String.t()]
  def declared_route_paths do
    # The router the endpoint dispatches to, first: a host names its own in
    # `config :gamend_web, :router`, and reading only the two known module
    # names here reported every host-declared route as undocumented — the
    # same drift `GamendWeb.ApiSpec` had before it resolved the router the way
    # `dispatch_router/2` does.
    [Application.get_env(:gamend_web, :router), GamendHost.Router, GamendWeb.Router]
    |> Enum.reject(&is_nil/1)
    |> Enum.find(&Code.ensure_loaded?/1)
    |> case do
      nil ->
        []

      router ->
        router
        |> Phoenix.Router.routes()
        |> Enum.map(&normalize_path(&1.path))
        |> Enum.uniq()
    end
  end

  # ── Shared analysis ────────────────────────────────────────────────────────

  @doc """
  String/map schema fields that can actually be nil: no `default:`, and not in
  the changeset's required list.
  """
  @spec nullable_schema_fields() :: %{String.t() => String.t()}
  def nullable_schema_fields do
    per_schema =
      for path <- ex_files(schema_dirs()),
          [_, table, body] <- [Regex.run(~r/schema "(\w+)" do(.*?)\n  end/s, File.read!(path))] do
        required = required_fields(File.read!(path))

        declared =
          for [_, f, _, _] <- Regex.scan(~r/field :(\w+), :(string|map)([^\n]*)/, body), do: f

        {table, declared, nullable_in_body(body, required)}
      end

    # A field name is only actionable when every schema declaring it leaves it
    # nullable. `status` is nullable on oauth_sessions but defaulted on eight
    # others, and the source line alone does not say which struct it is.
    declared_in = tally(per_schema, fn {_t, declared, _n} -> declared end)
    nullable_in = tally(per_schema, fn {t, _d, nullable} -> Enum.map(nullable, &{&1, t}) end)

    for {field, tables} <- nullable_in,
        length(tables) == Map.get(declared_in, field, []) |> length(),
        into: %{},
        do: {field, Enum.join(tables, ", ")}
  end

  defp tally(per_schema, extract) do
    Enum.reduce(per_schema, %{}, fn entry, acc ->
      Enum.reduce(extract.(entry), acc, fn
        {field, table}, inner -> Map.update(inner, field, [table], &[table | &1])
        field, inner -> Map.update(inner, field, [elem(entry, 0)], &[elem(entry, 0) | &1])
      end)
    end)
  end

  defp nullable_in_body(body, required) do
    for [_, field, _type, rest] <-
          Regex.scan(~r/field :(\w+), :(string|map)([^\n]*)/, body),
        not String.contains?(rest, "default:"),
        field not in required,
        do: field
  end

  defp required_fields(text) do
    inline = Regex.scan(~r/validate_required\(\[([^\]]*)\]/, text)
    attrs = Regex.scan(~r/@required\w*\s+~w\(([^)]*)\)a/, text)

    inline_fields = Enum.flat_map(inline, fn [_, list] -> Regex.scan(~r/:(\w+)/, list) end)

    Enum.map(inline_fields, fn [_, f] -> f end) ++
      Enum.flat_map(attrs, fn [_, list] -> String.split(list) end)
  end

  defp schema_has_nullable_string?(file) do
    text = File.read!(file)

    case Regex.run(~r/schema "(\w+)" do(.*?)\n  end/s, text) do
      [_, _table, body] -> nullable_in_body(body, required_fields(text)) != []
      _ -> false
    end
  end

  # ── R10: authority predicates name the capability, not the role ────────────
  #
  # `admin?`, `leader?`, `host_of?` each answer "may this user act here", and
  # each answered it slightly differently — argument orders disagreed and one
  # copy of the lobby rule drifted until every member of a matchmaking lobby
  # could kick. One name shape, `can_<verb>_<resource>?(subject, resource)`,
  # and `Gamend.Policy` routes to it. `member?` is not authority and is fine.

  @role_predicates ~w(admin owner leader host host_of)

  defp role_named_predicates do
    for {file, line, text} <- source_lines(source_dirs() ++ schema_dirs()),
        [_, name] <- [Regex.run(~r/^\s*defp?\s+(\w+)\?\(/, text)],
        name in @role_predicates do
      %{
        rule: "R10-authority-predicate",
        file: file,
        line: line,
        message:
          "#{name}?/N names a role; authority predicates are " <>
            "can_<verb>_<resource>?(subject, resource) - see Gamend.Policy"
      }
    end
  end

  # ── R11: controllers do not re-derive who owns a resource ──────────────────
  #
  # The rule lives in the context that owns the resource. A controller or
  # channel comparing `host_id`/`leader_id` to a caller's id is a copy of it,
  # and copies are what drift. LiveViews are exempt: they compare the same
  # fields to render "host" badges next to members, which is display, not a
  # decision.

  defp inline_ownership_checks do
    for {file, line, text} <- source_lines(source_dirs()),
        decision_site?(file),
        Regex.match?(
          ~r/(host_id|leader_id)\s*==\s*\w+\.id|\w+\.id\s*==\s*\w+\.(host_id|leader_id)/,
          text
        ) do
      %{
        rule: "R11-inline-ownership",
        file: file,
        line: line,
        message:
          "re-derives ownership; ask the context (Lobbies.can_manage_lobby?/2, " <>
            "Parties.can_manage_party?/2) or Gamend.Policy.can?/3"
      }
    end
  end

  # ── R15: an API controller answers in one of the four shapes ───────────────
  #
  # `GamendWeb.Reply` writes them; `GamendWeb.ApiShapeTest` holds the document
  # to them and `GamendWeb.ResponseContract` every response a test provokes.
  # Both see only documented operations, so this catches what slips past them
  # in source: an API controller calling `json/2` itself (the upload target
  # and the API 404 are undocumented, and kept their own shapes that way), and
  # a response documented with an inline schema instead of a named
  # `GamendWeb.Schemas` module.

  defp unnamed_responses do
    for path <- ex_files(source_dirs()),
        String.contains?(path, "/controllers/api/"),
        text = File.read!(path),
        violation <- direct_json(path, text) ++ inline_response_schemas(path, text),
        do: violation
  end

  defp direct_json(path, text) do
    for {line_text, line} <- Enum.with_index(String.split(text, "\n"), 1),
        not String.starts_with?(String.trim_leading(line_text), "#"),
        Regex.match?(~r/(?<![\w.])json\(/, line_text) do
      %{
        rule: "R15-response-shape",
        file: path,
        line: line,
        message: "answer through GamendWeb.Reply (reply_data, reply_page, reply_ok, reply_error)"
      }
    end
  end

  defp inline_response_schemas(path, text) do
    for {start, _len} <- responses_blocks(text),
        [{offset, _}] <-
          Regex.scan(~r/"application\/json",\s*%(OpenApiSpex\.)?Schema\{/, block_at(text, start),
            return: :index
          ) do
      %{
        rule: "R15-response-shape",
        file: path,
        line: line_of(text, start + offset),
        message:
          "document the response with a named GamendWeb.Schemas module, not an inline schema"
      }
    end
  end

  # Where each `responses: [...]` or `responses: %{...}` value starts.
  defp responses_blocks(text) do
    Regex.scan(~r/responses:\s*(?=\[|%\{)/, text, return: :index)
    |> Enum.map(fn [{index, length}] -> {index + length, 0} end)
  end

  # The bracketed value starting at `start`, up to its matching close. Only
  # the opening bracket's own kind is counted, so a brace in a description
  # string cannot end a list early.
  defp block_at(text, start) do
    rest = binary_part(text, start, byte_size(text) - start)
    {open, close} = if String.starts_with?(rest, "["), do: {"[", "]"}, else: {"{", "}"}

    rest
    |> String.graphemes()
    |> Enum.reduce_while({0, []}, fn char, {depth, acc} ->
      depth =
        cond do
          char == open -> depth + 1
          char == close -> depth - 1
          true -> depth
        end

      if depth == 0 and char == close,
        do: {:halt, {depth, [char | acc]}},
        else: {:cont, {depth, [char | acc]}}
    end)
    |> elem(1)
    |> Enum.reverse()
    |> Enum.join()
  end

  defp line_of(text, offset),
    do: text |> binary_part(0, offset) |> String.split("\n") |> length()

  # ── R17: a boundary does not look a row up with a `!` ──────────────────────
  #
  # At a boundary the id comes from a client, or the row from state another
  # process can delete, so a miss is an answer, not a bug. `get_x!` turned it
  # into a raise: over HTTP that happened to render a 404, while a channel
  # join, a LiveView event and a hook crashed, and the same race answered 404
  # from one controller and 400 from the next. The rule is "Errors" in
  # CONTRIBUTING.md. Boundaries are API controllers and channels (the whole
  # module), and a LiveView's `handle_event`/`handle_info`/`handle_async` and a
  # job's `perform` (those bodies: `mount` and `handle_params` may let
  # `Ecto.NoResultsError` render its 404).

  @raising_repo_lookups ~w(get! get_by! one! get_uuid! reload!)a
  @event_callbacks ~w(handle_event handle_info handle_async perform)a

  defp raising_lookups_at_boundaries do
    for path <- ex_files(schema_dirs() ++ source_dirs()),
        text = File.read!(path),
        scope = boundary_scope(path, text),
        {:ok, ast} <- [Code.string_to_quoted(text)],
        {line, call} <- raising_lookups(ast, scope) do
      %{
        rule: "R17-boundary-raise",
        file: path,
        line: line,
        message:
          "#{call} raises on a miss at a boundary; call its tuple/nil twin and answer " <>
            "the miss (CONTRIBUTING.md \"Errors\")"
      }
    end
  end

  defp boundary_scope(path, text) do
    cond do
      String.contains?(path, "/controllers/api/") or String.contains?(path, "/channels/") ->
        :module

      String.contains?(path, "/live/") or String.contains?(text, "Oban.Worker") ->
        :callbacks

      true ->
        nil
    end
  end

  defp raising_lookups(ast, :module), do: lookups_in(ast)

  defp raising_lookups(ast, :callbacks) do
    {_ast, bodies} =
      Macro.prewalk(ast, [], fn
        {:def, _, [head, body]} = node, acc ->
          if callback_name(head) in @event_callbacks, do: {node, [body | acc]}, else: {node, acc}

        node, acc ->
          {node, acc}
      end)

    Enum.flat_map(bodies, &lookups_in/1)
  end

  defp callback_name({:when, _, [head | _]}), do: callback_name(head)
  defp callback_name({name, _, args}) when is_atom(name) and is_list(args), do: name
  defp callback_name(_head), do: nil

  defp lookups_in(ast) do
    {_ast, found} =
      Macro.prewalk(ast, [], fn
        {{:., _, [{:__aliases__, _, parts}, fun]}, meta, args} = node, acc
        when is_atom(fun) and is_list(args) ->
          if raising_lookup?(List.last(parts), fun),
            do: {node, [{meta[:line], "#{Enum.join(parts, ".")}.#{fun}"} | acc]},
            else: {node, acc}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(found)
  end

  defp raising_lookup?(:Repo, fun), do: fun in @raising_repo_lookups

  defp raising_lookup?(_module, fun) do
    name = Atom.to_string(fun)
    String.starts_with?(name, "get_") and String.ends_with?(name, "!")
  end

  # ── R18: a reason no clause names goes to reply_reason/2 ───────────────────
  #
  # A catch-all error clause gave every reason it caught one status, chosen
  # for the first reason the author had in mind: a party that lost its leader
  # answered 400 from one endpoint and 403 from the next, a hook's veto came
  # back as `invalid_data`, and a reason added to a context later was
  # answered as whatever the catch-all said. The reasons a controller does
  # not answer its own way go to `reply_reason(conn, reason)`, which takes the
  # status from `GamendWeb.ErrorStatus` and raises on a reason it has none
  # for. Flagged wherever a web module answers JSON (API controllers and the
  # helpers they share, such as `GamendWeb.ControllerScope`; not LiveViews):
  #
  # - `reply_error(conn, :status, reason)`: a chosen status, a code from a
  #   variable (a status looked up with the code, `{status, code} = ...`, is
  #   fine);
  # - `{:error, _} -> reply_error(...)`: the reason thrown away, and the
  #   same for a function clause taking `_reason`/`_error`/`_other`;
  # - `_ -> reply_error(...)` in a `with`'s `else`, or in a `case` that also
  #   matches `{:error, ...}`: every failure answered alike;
  # - `reply_error(conn, :status, "code")` where `code` is a reason the table
  #   gives another status: the status follows the reason.
  #
  # A reason set that is open by design (a plugin's own codes, over the hook
  # RPC) says so with `# open-error: <why>` on the line above.

  @ignored_reasons ~w(_ _reason _error _other _err)a

  defp open_error_answers do
    for path <- ex_files(source_dirs()),
        String.contains?(path, "_web/") or String.contains?(path, "/controllers/"),
        not live_view?(path),
        text = File.read!(path),
        {:ok, ast} <- [Code.string_to_quoted(text)],
        lines = List.to_tuple(String.split(text, "\n")),
        {line, message} <- ast |> open_errors() |> Enum.uniq_by(&elem(&1, 0)),
        not open_marked?(lines, line) do
      %{rule: "R18-open-error", file: path, line: line, message: message}
    end
  end

  defp open_marked?(lines, line) do
    Enum.any?([line - 1, line], fn n ->
      n >= 1 and n <= tuple_size(lines) and
        String.contains?(elem(lines, n - 1), "# open-error:")
    end)
  end

  defp open_errors(ast) do
    {_ast, found} =
      Macro.prewalk(ast, [], fn node, acc ->
        node = unpipe(node)
        {node, open_errors_at(node) ++ acc}
      end)

    Enum.sort(found)
  end

  # `conn |> reply_error(:forbidden, reason)` reads as the call it is.
  defp unpipe({:|>, _, _} = pipe) do
    [{head, _} | rest] = Macro.unpipe(pipe)
    Enum.reduce(rest, head, fn {call, position}, acc -> Macro.pipe(acc, call, position) end)
  end

  defp unpipe(node), do: node

  defp open_errors_at({:reply_error, meta, [_conn, status, code | _]}) when is_atom(status) do
    cond do
      not literal_code?(code) ->
        [
          {meta[:line],
           "answers a reason no clause names with #{status}; match it, or " <>
             "reply_reason(conn, reason) (GamendWeb.ErrorStatus)"}
        ]

      (expected = reason_status(code)) not in [nil, status] ->
        [
          {meta[:line],
           "`#{code}` is #{expected} in GamendWeb.ErrorStatus, not #{status}: " <>
             "the status follows the reason"}
        ]

      true ->
        []
    end
  end

  defp open_errors_at({:->, meta, [[{:error, reason}], body]}) do
    if ignored_reason?(reason) and replies_error?(body),
      do: [
        {meta[:line],
         "throws the error reason away; match the ones it answers and " <>
           "reply_reason(conn, reason) the rest"}
      ],
      else: []
  end

  defp open_errors_at({:with, _, args}) when is_list(args) do
    case List.last(args) do
      [{:do, _} | _] = blocks -> catch_alls(Keyword.get(blocks, :else, []), "a with's else")
      _ -> []
    end
  end

  defp open_errors_at({:case, _, [_subject, [do: clauses]]}) when is_list(clauses) do
    if Enum.any?(clauses, &error_clause?/1),
      do: catch_alls(clauses, "a case on a result"),
      else: []
  end

  defp open_errors_at({kind, meta, [head, body]}) when kind in [:def, :defp] do
    if Enum.any?(head_args(head), &ignored_reason?/1) and replies_error?(body),
      do: [
        {meta[:line],
         "a clause for any reason answers them all alike; match the ones " <>
           "it answers and reply_reason(conn, reason) the rest"}
      ],
      else: []
  end

  defp open_errors_at(_node), do: []

  defp catch_alls(clauses, where) do
    for {:->, meta, [[pattern], body]} <- List.wrap(clauses),
        bare_var?(pattern),
        replies_error?(body) do
      {meta[:line],
       "#{where} catches every failure and answers them alike; name each, " <>
         "and reply_reason(conn, reason) an {:error, reason}"}
    end
  end

  defp error_clause?({:->, _, [[{:error, _}], _]}), do: true
  defp error_clause?(_clause), do: false

  defp head_args({:when, _, [head | _]}), do: head_args(head)
  defp head_args({_name, _, args}) when is_list(args), do: Enum.drop(args, 1)
  defp head_args(_head), do: []

  defp ignored_reason?({name, _, context}) when is_atom(context), do: name in @ignored_reasons
  defp ignored_reason?(_pattern), do: false

  defp bare_var?({name, _, context}) when is_atom(name) and is_atom(context),
    do: name not in [:__MODULE__, :__ENV__]

  defp bare_var?(_pattern), do: false

  defp literal_code?(code), do: is_binary(code) or is_atom(code)

  defp replies_error?(body) do
    {_ast, found?} =
      Macro.prewalk(body, false, fn
        {:reply_error, _, args} = node, _acc when is_list(args) -> {node, true}
        node, acc -> {node, acc}
      end)

    found?
  end

  # The status `GamendWeb.ErrorStatus` gives a code, read at lint time: core
  # does not depend on web, and in a host repo both are deps. Tests point
  # `:api_lint_error_status` at a stand-in.
  defp reason_status(code) do
    module = Application.get_env(:gamend_core, :api_lint_error_status, GamendWeb.ErrorStatus)

    if Code.ensure_loaded?(module) and function_exported?(module, :status, 1),
      do: module.status(String.to_atom(to_string(code))),
      else: nil
  end

  defp decision_site?(file),
    do: String.contains?(file, "/controllers/") or String.contains?(file, "/channels/")

  # LiveViews assign structs to sockets rather than serializing them; the null
  # policy is about what crosses the wire as JSON.
  defp live_view?(file), do: String.contains?(file, "/live/")

  defp source_lines(roots) do
    for path <- ex_files(roots),
        {text, line} <- Enum.with_index(String.split(File.read!(path), "\n"), 1),
        do: {path, line, text}
  end

  defp ex_files(roots) when is_list(roots) do
    roots
    |> Enum.flat_map(fn root ->
      # A root may itself live under deps/ (core/web pulled into a host), but
      # anything *nested* below a root - a plugin's own deps/_build - is
      # third-party code and not ours to lint.
      for path <- Path.wildcard(Path.join(root, "**/*.ex")),
          rest = String.trim_leading(path, root),
          not String.contains?(rest, "/deps/"),
          not String.contains?(rest, "/_build/"),
          do: path
    end)
    |> Enum.uniq()
  end
end
