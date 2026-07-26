defmodule GameServer.ApiConventions do
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

  # The same checks run in every host repo (polyglot, the starter), where
  # core/web live under deps and the host's own code under lib/ and
  # modules/*/lib - so the scan roots are discovered, not hardcoded. Only
  # directories that exist take part.
  @schema_roots ["apps/game_server_core/lib", "lib", "modules"]
  @source_roots ["apps/game_server_web/lib", "lib", "modules"]

  defp schema_dirs, do: existing([dep_dir("game_server_core") | @schema_roots])
  defp source_dirs, do: existing([dep_dir("game_server_web") | @source_roots])

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
       stale_documented_routes())
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
  # every serializer. Such schemas encode through `GameServer.SchemaJSON`.

  defp derived_encoders_with_nullable_strings do
    for {file, line, text} <- source_lines(schema_dirs()),
        String.contains?(text, "@derive {Jason.Encoder"),
        schema_has_nullable_string?(file) do
      %{
        rule: "R2-derive-encoder",
        file: file,
        line: line,
        message: "schema has nullable string/map fields; encode via GameServer.SchemaJSON instead"
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

  defp hyphenated_route_paths do
    for {file, line, text} <- source_lines(source_dirs()),
        String.contains?(file, "router"),
        [_, verb, path] <-
          [Regex.run(~r/^\s*(get|post|put|patch|delete|live) "(\/[^"]*)"/, text)],
        String.contains?(path, "-") do
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
        not String.contains?(text, "format:"),
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
        message: "build pagination meta with GameServerWeb.Pagination.meta/4"
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
        message: "read the page window with GameServerWeb.Pagination.params/1"
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

  defp stale_documented_routes(declared) do
    for dir <- @doc_dirs,
        file <- Path.wildcard(Path.join(dir, "**/*.md")),
        {text, line} <- file |> File.read!() |> String.split("\n") |> Enum.with_index(1),
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
    [GameServerHost.Router, GameServerWeb.Router]
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
