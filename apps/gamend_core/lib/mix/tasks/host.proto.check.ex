defmodule Mix.Tasks.Host.Proto.Check do
  @moduledoc """
  Check that registered protobuf schemas actually match the JSON they encode.

  A protobuf schema here is an opt-in wire optimisation over a value that is
  still stored and sent as JSON. The encoder is deliberately safe: a value the
  schema does not fully describe is sent as JSON instead, so a schema can never
  drop or corrupt data. The cost of that safety is silence — a schema missing
  one field is not an error anywhere, it simply never encodes, and the
  optimisation you think you shipped is inert.

  That has happened twice in this codebase and neither was noticed by a test:

    * `Progress` listed neither `words_total` nor several other keys the
      canonical shape always carries, so *every* player's progress fell back to
      JSON — the protobuf path had never encoded a single row.
    * A hand-written Godot decoder omitted `awaiting_continue`, so a paid
      continue offer was decoded away and players sat in a paused game with no
      prompt and no way on.

  This task is the check that would have caught both, run against real data:
  for every registered schema it takes the values actually stored under those
  keys and reports which of them fail to encode, and why.

  ## Usage

      mix host.proto.check                     # every registered schema
      mix host.proto.check --limit 200         # rows sampled per key (default 50)
      mix host.proto.check --key progress      # one key or entity only

  It covers both places a schema is applied to stored data: KV entry values
  (registered explicitly via `kv_schemas/0`) and user/lobby/group/party
  metadata (registered by naming a `UserMeta`/`LobbyMeta`/`GroupMeta`/
  `PartyMeta` message). It also prints, without failing, what is NOT typed —
  the KV keys, metadata entities and hooks still going out as JSON — because
  nothing else in the system reports that either.

  What it cannot sample is anything that is never stored — a typed hook's
  request or reply, most of all. Capture one real payload and name its module;
  this is also the form to hand someone who reports "protobuf is not working":

      mix host.proto.check --json captured.json --message MyGame.V1.HelloReply

  Exit status is 1 when any sampled value fails to encode, so it can gate CI.

  ## What a failure means

  `unknown keys` are keys present in the data that the schema has no field for.
  They are the usual cause: add the field to the `.proto`, regenerate with
  `mix host.proto.gen`, and re-run. `encode errors` are keys the schema knows
  but whose *type* disagrees, which is the same class of bug one level down.
  """
  use Mix.Task

  alias Gamend.Hooks.HookSchemas
  alias Gamend.Hooks.KvSchemas
  alias Gamend.Hooks.MetadataSchemas
  alias Gamend.Hooks.PluginManager

  @key "key"
  @hooks "hooks"
  @metadata "metadata"

  @shortdoc "Check protobuf schemas against the JSON values they encode"

  @default_limit 50
  @coverage_shown 12

  @impl Mix.Task
  def run(args) do
    {opts, _rest} =
      OptionParser.parse!(args,
        strict: [limit: :integer, key: :string, json: :string, message: :string]
      )

    Mix.Task.run("app.start")

    case {opts[:json], opts[:message]} do
      {nil, nil} ->
        results = check_registry(opts)
        cov = if opts[:key], do: nil, else: coverage()
        report(results, cov)

      {json, message} when is_binary(json) and is_binary(message) ->
        report([check_file(json, message)], nil)

      _ ->
        Mix.raise("--json and --message must be given together")
    end
  end

  # ── registered KV schemas ────────────────────────────────────────────────

  defp check_registry(opts) do
    limit = opts[:limit] || @default_limit
    check_kv(opts, limit) ++ check_metadata(opts, limit)
  end

  # ── coverage: what is still going out as JSON ────────────────────────────
  #
  # A schema that is missing is not a failure — it is the default, and it is
  # invisible. Everything below encodes as JSON today and could carry a
  # protobuf schema instead; the point of listing it is that nothing else in
  # the system ever will.
  defp coverage do
    %{kv: untyped_kv_keys(), metadata: untyped_metadata(), hooks: untyped_hooks()}
  end

  # Keys with rows in kv_entries that no registered schema matches, counted —
  # a key with 40k rows is worth a message and a key with 2 is not.
  #
  # Reported by PATTERN rather than by key: `map_users:es:es-gi:` and its
  # twenty siblings are one decision, not twenty, and `"map_users:*"` is
  # exactly what `kv_schemas/0` would be given. Keys with no `:` stand alone.
  defp untyped_kv_keys do
    import Ecto.Query

    Gamend.KV.Entry
    |> group_by([e], e.key)
    |> select([e], {e.key, count(e.id)})
    |> Gamend.Repo.all()
    |> Enum.reject(fn {key, _count} -> KvSchemas.module_for(key) end)
    |> Enum.group_by(fn {key, _count} -> kv_pattern(key) end)
    |> Enum.map(fn {pattern, rows} ->
      {pattern, Enum.sum(Enum.map(rows, &elem(&1, 1))), length(rows)}
    end)
    |> Enum.sort_by(fn {_pattern, rows, _keys} -> -rows end)
  rescue
    _ -> []
  end

  defp kv_pattern(key) do
    case String.split(key, ":", parts: 2) do
      [_only] -> key
      [head, _rest] -> head <> ":*"
    end
  end

  defp untyped_metadata do
    registered = MetadataSchemas.all()

    for entity <- MetadataSchemas.entities(),
        not Map.has_key?(registered, entity),
        rows = length(sample_metadata(entity, @default_limit)),
        rows > 0,
        do: {entity, rows}
  end

  # Untyped hooks behave differently from untyped KV: a JSON call still works
  # (args pass through as a list), but a binary call is refused outright with
  # `:hook_schema_missing`. So this list is also the list of hooks a protobuf
  # DataChannel cannot call at all.
  defp untyped_hooks do
    typed = HookSchemas.all()

    for {plugin, mod} <- PluginManager.hook_modules(),
        f <- Gamend.Hooks.exported_functions(mod),
        not Map.has_key?(typed, {plugin, f.name}),
        do: {plugin, f.name}
  rescue
    _ -> []
  end

  # ── entity metadata (user / lobby / group / party) ───────────────────────
  #
  # Registered by CONVENTION, not declaration: `MetadataSchemas` scans a
  # loading plugin for `UserMeta`/`LobbyMeta`/`GroupMeta`/`PartyMeta`. That
  # makes them easy to add and easy to forget — an entity with no message is
  # not an error, it just never encodes, so the coverage line below names the
  # ones still going as JSON.
  @metadata_sources %{
    user: {Gamend.Accounts.User, "users"},
    lobby: {Gamend.Lobbies.Lobby, "lobbies"},
    group: {Gamend.Groups.Group, "groups"},
    party: {Gamend.Parties.Party, "parties"}
  }

  defp check_metadata(opts, limit) do
    registered = MetadataSchemas.all()

    registered
    |> Enum.filter(fn {entity, _mod} ->
      is_nil(opts[:key]) or to_string(entity) == opts[:key]
    end)
    |> Enum.map(fn {entity, mod} ->
      values = sample_metadata(entity, limit)
      summarise("#{entity}.metadata", mod, values)
    end)
  end

  defp sample_metadata(entity, limit) do
    import Ecto.Query

    case Map.fetch(@metadata_sources, entity) do
      {:ok, {schema, _table}} ->
        schema
        |> limit(^limit)
        |> select([e], e.metadata)
        |> Gamend.Repo.all()
        |> Enum.filter(&is_map/1)
        |> Enum.reject(&(map_size(&1) == 0))

      :error ->
        []
    end
  rescue
    _ -> []
  end

  defp check_kv(opts, limit) do
    %{exact: exact, prefixes: prefixes} = KvSchemas.all()

    contracts =
      Enum.map(exact, fn {key, mod} -> {key, mod, :exact} end) ++
        Enum.map(prefixes, fn {prefix, mod} -> {prefix, mod, :prefix} end)

    contracts =
      case opts[:key] do
        nil -> contracts
        wanted -> Enum.filter(contracts, fn {pattern, _mod, _kind} -> pattern == wanted end)
      end

    if contracts == [] do
      Mix.shell().info("No KV schemas are registered. Nothing to check.")
    end

    Enum.map(contracts, fn {pattern, mod, kind} -> check_contract(pattern, mod, kind, limit) end)
  end

  defp check_contract(pattern, mod, kind, limit) do
    summarise(pattern, mod, sample_values(pattern, kind, limit))
  end

  defp summarise(name, mod, values) do
    failures =
      values
      |> Enum.map(&{&1, encode_failure(&1, mod)})
      |> Enum.filter(fn {_value, reason} -> reason != nil end)

    %{
      name: name,
      module: mod,
      sampled: length(values),
      failed: length(failures),
      unknown_keys: unknown_keys(failures, mod),
      errors: failures |> Enum.map(fn {_v, reason} -> reason end) |> Enum.uniq() |> Enum.take(3)
    }
  end

  defp sample_values(pattern, kind, limit) do
    import Ecto.Query

    query =
      case kind do
        :exact -> from(e in Gamend.KV.Entry, where: e.key == ^pattern)
        :prefix -> from(e in Gamend.KV.Entry, where: like(e.key, ^(pattern <> "%")))
      end

    query
    |> limit(^limit)
    |> select([e], e.value)
    |> Gamend.Repo.all()
    |> Enum.filter(&is_map/1)
  rescue
    error -> Mix.raise("could not read kv_entries: #{Exception.message(error)}")
  end

  # ── one captured payload ─────────────────────────────────────────────────

  defp check_file(path, message) do
    unless File.exists?(path), do: Mix.raise("no such file: #{path}")
    mod = resolve_module(message)

    value =
      path
      |> File.read!()
      |> Jason.decode!()

    unless is_map(value), do: Mix.raise("#{path} is not a JSON object")

    reason = encode_failure(value, mod)

    %{
      name: Path.basename(path),
      module: mod,
      sampled: 1,
      failed: if(reason, do: 1, else: 0),
      unknown_keys: unknown_keys(if(reason, do: [{value, reason}], else: []), mod),
      errors: if(reason, do: [reason], else: [])
    }
  end

  defp resolve_module(name) do
    mod = Module.concat([name])

    if Code.ensure_loaded?(mod) and function_exported?(mod, :__message_props__, 0) do
      mod
    else
      Mix.raise("#{name} is not a loaded protobuf message module")
    end
  end

  # ── the check itself ─────────────────────────────────────────────────────

  # Deliberately the same two steps the encoder takes, in the same order, so a
  # value this task passes is a value that really does encode. Re-deriving the
  # rule here would let the two drift, which is the whole failure mode.
  defp encode_failure(value, mod) do
    if keys_known?(value, mod) do
      from_decoded_failure(value, mod)
    else
      :unknown_keys
    end
  end

  defp from_decoded_failure(value, mod) do
    case Protobuf.JSON.from_decoded(value, mod) do
      {:ok, _struct} -> nil
      {:error, reason} -> {:encode_error, truncate(inspect(reason))}
    end
  rescue
    error -> {:encode_error, truncate(Exception.message(error))}
  end

  defp keys_known?(map, mod) when is_map(map) do
    Enum.all?(Map.keys(map), &MapSet.member?(field_names(mod), to_string(&1)))
  end

  defp keys_known?(_map, _mod), do: false

  defp field_names(mod) do
    mod.__message_props__().field_props
    |> Map.values()
    |> Enum.flat_map(&[&1.name, &1.json_name])
    |> MapSet.new()
  end

  defp unknown_keys(failures, mod) do
    known = field_names(mod)

    failures
    |> Enum.flat_map(fn {value, _reason} -> Map.keys(value) end)
    |> Enum.map(&to_string/1)
    |> Enum.reject(&MapSet.member?(known, &1))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp truncate(text), do: String.slice(text, 0, 120)

  # ── reporting ────────────────────────────────────────────────────────────

  defp report(results, cov) do
    Mix.shell().info("")
    Mix.shell().info("  PROTOBUF SCHEMA CHECK")
    Mix.shell().info("  " <> String.duplicate("-", 72))

    if results == [] do
      Mix.shell().info("  no schemas are registered")
    else
      Enum.each(results, &report_one/1)
    end

    report_coverage(cov)

    Mix.shell().info("  " <> String.duplicate("-", 72))
    broken = Enum.filter(results, &(&1.failed > 0))

    if broken == [] do
      Mix.shell().info("  every sampled value encodes as protobuf")
      :ok
    else
      names = Enum.map_join(broken, ", ", & &1.name)
      Mix.shell().error("  falling back to JSON: #{names}")
      exit({:shutdown, 1})
    end
  end

  # Never an error and never affects exit status: not having a schema is the
  # supported default, and most of these should stay that way. It is printed
  # because it is the only place the choice is visible at all.
  defp report_coverage(nil), do: :ok

  defp report_coverage(cov) do
    Mix.shell().info("")
    Mix.shell().info("  NOT TYPED - still encoded as JSON  (informational)")

    coverage_line("kv keys", Enum.map(cov.kv, &describe_kv_pattern/1))

    coverage_line(
      @metadata,
      Enum.map(cov.metadata, fn {e, n} -> "#{e} (#{plural(n, "row")})" end)
    )

    coverage_line(@hooks, Enum.map(cov.hooks, fn {plugin, fun} -> "#{plugin}.#{fun}" end))

    if cov.kv != [] do
      Mix.shell().info("        register these from the plugin's kv_schemas/0;")
      Mix.shell().info("        a trailing :* is a prefix and matches every key under it")
    end

    if cov.hooks != [] do
      Mix.shell().info("        a hook with no <Fn>Request/<Fn>Reply pair cannot be")
      Mix.shell().info("        called over a protobuf DataChannel at all")
    end
  end

  defp describe_kv_pattern({pattern, rows, 1}), do: "#{pattern} (#{plural(rows, "row")})"

  defp describe_kv_pattern({pattern, rows, keys}),
    do: "#{pattern} (#{plural(rows, "row")}, #{plural(keys, @key)})"

  defp plural(1, noun), do: "1 #{noun}"
  defp plural(n, noun), do: "#{n} #{noun}s"

  defp coverage_line(_label, []), do: :ok

  defp coverage_line(label, entries) do
    shown = Enum.take(entries, @coverage_shown)
    more = length(entries) - length(shown)
    suffix = if more > 0, do: " (+#{more} more)", else: ""
    Mix.shell().info("  #{pad(label)}#{Enum.join(shown, ", ")}#{suffix}")
  end

  defp report_one(%{sampled: 0} = r) do
    Mix.shell().info("  ----  #{pad(r.name)}  no values stored  (#{inspect(r.module)})")
  end

  defp report_one(%{failed: 0} = r) do
    Mix.shell().info("  ok    #{pad(r.name)}  #{r.sampled}/#{r.sampled} encode")
  end

  defp report_one(r) do
    Mix.shell().error("  FAIL  #{pad(r.name)}  #{r.failed}/#{r.sampled} fall back to JSON")

    if r.unknown_keys != [] do
      Mix.shell().error("          unknown keys: #{Enum.join(r.unknown_keys, ", ")}")
      Mix.shell().error("          add them to the .proto, then: mix host.proto.gen")
    end

    for {:encode_error, message} <- r.errors do
      Mix.shell().error("          encode error: #{message}")
    end
  end

  defp pad(name), do: String.pad_trailing(to_string(name), 24)
end
