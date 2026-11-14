defmodule Gamend.Export.Convert do
  @moduledoc """
  Another Gamend's rows, copied into this one's database: how a host moves
  from a Postgres of its own to a SQLite file, or the other way.

  The database adapter is chosen when a release is compiled, and a migration
  branches on it, so the copy runs in a build of the adapter it copies *to*,
  on a database that build has migrated and nothing has written to. The
  source is read through a second repo (`Source`) of the other adapter: both
  drivers are in every build.

  ## What is copied, and as what

  Every table both databases have, row for row, each value loaded by the
  source's adapter and dumped by this one's through the type its Ecto schema
  declares. That is the whole point of going through the schemas: a
  timestamp, a UUID, a map and a boolean are each stored differently by the
  two, and only the type says how. A table no schema describes is copied by
  its columns' own types, and named in the result.

  Left out: `schema_migrations` (this database has its own, and the two
  must agree before anything is copied) and Oban's tables, whose jobs belong
  to the node that queued them. Stop the source's application first: a job
  still queued there is not carried over.

  ## However it ends

  One transaction on each side: the source is read as it was when the copy
  began, and this database holds every row or none. Foreign keys are checked
  once, at the end, since tables are copied in name order and a row may name
  one not copied yet. Then each table's rows are counted on both sides.
  """

  import Ecto.Query, only: [from: 2]

  # Every query goes through the repo's own functions, never
  # `Ecto.Adapters.SQL` with the module: those follow a dynamic repo, which
  # is how a test (and a host with more than one database) names this one.

  alias Ecto.Adapters.SQL
  alias Gamend.Repo

  defmodule Source do
    @moduledoc false
    # Postgres: what a compose deploy runs, and the only source a release is
    # asked for. A test reads a second SQLite file through a repo of its own.
    use Ecto.Repo, otp_app: :gamend_core, adapter: Ecto.Adapters.Postgres
  end

  @migrations "schema_migrations"

  # Postgres' own names for its types, as its catalogue spells them
  # (`udt_name`): a `timestamptz` and a `jsonb` begin with theirs.
  @pg_uuid "uuid"
  @pg_bool "bool"
  @pg_bytea "bytea"
  @pg_numeric "numeric"
  @pg_date "date"
  @pg_json "json"
  @pg_timestamp "timestamp"
  @skipped_prefixes ~w(oban_ sqlite_)
  @batch 100

  @type summary :: %{
          tables: [{String.t(), non_neg_integer()}],
          by_column_type: [String.t()],
          not_in_schema: [{String.t(), [String.t()]}],
          gone_migrations: [String.t()]
        }

  @doc """
  Copies every row of `source`, a started repo of another Gamend's database,
  into this one's.

  `skip:` names tables to leave behind. Answers what it copied:
  `tables`, each with its rows; `by_column_type`, the tables no schema
  describes; `not_in_schema`, columns of the source a schema has no field
  for, which are left at their default; `gone_migrations`, versions the
  source ran that this release no longer has.

  Refuses, with nothing written:

    * `{:error, {:migrations_differ, only_source, only_here}}` — the source
      is behind this release's migrations, or ahead of them. Deploy this
      version on the source first.
    * `{:error, {:not_empty, table}}` — this database already has rows.
    * `{:error, {:no_table, table, rows}}` — the source has rows in a table
      this database does not have. `skip:` it to leave them.
    * `{:error, {:foreign_keys, violations}}` and
      `{:error, {:rows_differ, table, source, here}}` — the copy is not the
      source, and was rolled back.
  """
  @spec run(module(), keyword()) :: {:ok, summary()} | {:error, term()}
  def run(source, opts \\ []) do
    skip = Keyword.get(opts, :skip, [])

    # The source as it is now, for the length of the copy.
    result =
      source.transaction(
        fn ->
          snapshot(source)

          with {:ok, gone} <- same_migrations(source),
               {:ok, tables} <- tables(source, skip),
               {:ok, summary} <- copy_all(source, tables) do
            Map.put(summary, :gone_migrations, gone)
          else
            {:error, reason} -> source.rollback(reason)
          end
        end,
        timeout: :infinity
      )

    with {:ok, summary} <- result, :ok <- after_copy(summary), do: {:ok, summary}
  end

  defp snapshot(source) do
    if postgres?(source),
      do: source.query!("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ", [])
  end

  # ── What to copy ────────────────────────────────────────────────────────

  # The source must have run every migration this database has, and none
  # newer than its newest: behind, its rows lack what a migration would have
  # written; ahead, they hold what this release cannot read. One it ran and
  # this release no longer has, older than that, is a migration since
  # deleted: what it left is a column or a table the checks below name.
  defp same_migrations(source) do
    there = versions(source)
    here = versions(Repo)
    newest = List.last(here)

    case {there -- here, here -- there} do
      {gone, []} ->
        if Enum.all?(gone, &(&1 < newest)),
          do: {:ok, gone},
          else: {:error, {:migrations_differ, gone, []}}

      {only_source, only_here} ->
        {:error, {:migrations_differ, only_source, only_here}}
    end
  end

  defp versions(repo) do
    %{rows: rows} = repo.query!(~s(SELECT version FROM "#{@migrations}"), [])
    rows |> Enum.map(fn [version] -> to_string(version) end) |> Enum.sort()
  end

  # The source's tables this database has too, in name order. One it lacks
  # is fine while it is empty.
  defp tables(source, skip) do
    here = table_names(Repo)

    source
    |> table_names()
    |> Enum.reject(&(&1 in skip or skipped?(&1)))
    |> Enum.reduce_while({:ok, []}, fn table, {:ok, found} ->
      cond do
        table in here -> {:cont, {:ok, [table | found]}}
        count(source, table) == 0 -> {:cont, {:ok, found}}
        true -> {:halt, {:error, {:no_table, table, count(source, table)}}}
      end
    end)
    |> case do
      {:ok, found} -> {:ok, Enum.reverse(found)}
      error -> error
    end
  end

  defp skipped?(table),
    do: table == @migrations or Enum.any?(@skipped_prefixes, &String.starts_with?(table, &1))

  defp table_names(repo) do
    sql =
      if postgres?(repo),
        do: "SELECT tablename FROM pg_tables WHERE schemaname = current_schema()",
        else: "SELECT name FROM sqlite_master WHERE type = 'table'"

    %{rows: rows} = repo.query!(sql, [])
    rows |> Enum.map(fn [name] -> name end) |> Enum.sort()
  end

  # A column's name and, on Postgres, its type as the catalogue spells it.
  defp columns(repo, table) do
    {sql, params} =
      if postgres?(repo) do
        {"SELECT column_name, udt_name FROM information_schema.columns " <>
           "WHERE table_schema = current_schema() AND table_name = $1", [table]}
      else
        {"SELECT name, type FROM pragma_table_info(?1)", [table]}
      end

    %{rows: rows} = repo.query!(sql, params)
    Map.new(rows, fn [name, type] -> {name, type} end)
  end

  defp count(repo, table) do
    %{rows: [[rows]]} = repo.query!(~s|SELECT count(*) FROM "#{table}"|, [])
    rows
  end

  # ── The copy ────────────────────────────────────────────────────────────

  defp copy_all(source, tables) do
    schemas = schemas()

    Repo.transaction(
      fn ->
        defer_foreign_keys()

        with :ok <- all_empty(tables),
             {:ok, copied} <- copy_tables(source, tables, schemas),
             :ok <- foreign_keys(),
             :ok <- same_rows(source, copied) do
          summary(copied)
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end,
      timeout: :infinity
    )
  end

  defp all_empty(tables) do
    case Enum.find(tables, &(count(Repo, &1) > 0)) do
      nil -> :ok
      table -> {:error, {:not_empty, table}}
    end
  end

  defp copy_tables(source, tables, schemas) do
    copied =
      Enum.map(tables, fn table ->
        there = columns(source, table)
        here = columns(Repo, table)

        case Map.get(schemas, table) do
          nil -> by_column_type(source, table, there, here)
          schema -> by_schema(source, table, schema, there, here)
        end
      end)

    {:ok, copied}
  end

  # Through the schema: loaded by the source's adapter into what the
  # application sees, dumped by this one's into what it stores.
  defp by_schema(source, table, schema, there, here) do
    fields =
      for field <- schema.__schema__(:fields),
          column = to_string(schema.__schema__(:field_source, field)),
          Map.has_key?(there, column) and Map.has_key?(here, column),
          do: {field, column, schema.__schema__(:type, field)}

    names = Enum.map(fields, fn {field, _column, _type} -> field end)
    query = from(row in {table, schema}, select: map(row, ^names))

    rows =
      query
      |> source.stream(max_rows: @batch)
      |> Stream.map(fn row ->
        Map.new(fields, fn {field, column, type} ->
          {String.to_atom(column), dump!(table, column, type, Map.fetch!(row, field))}
        end)
      end)
      |> insert(table)

    columns = Enum.map(fields, fn {_field, column, _type} -> column end)
    %{table: table, rows: rows, schema?: true, left: Map.keys(there) -- columns}
  end

  # NULL stays NULL, whatever the type: an insert leaves a nil field out, and
  # the SQLite adapter, asked to dump one, would store a map's as the text
  # `null`.
  defp dump!(_table, _column, _type, nil), do: nil

  defp dump!(table, column, type, value) do
    case Ecto.Type.adapter_dump(Repo.__adapter__(), type, value) do
      {:ok, dumped} -> dumped
      :error -> raise ArgumentError, "#{table}.#{column}: cannot store #{inspect(value)}"
    end
  end

  # No schema says what a column is, so its own type does: what the source's
  # driver hands back, as this adapter stores a value of that kind.
  defp by_column_type(source, table, there, here) do
    columns = for {column, _type} <- there, Map.has_key?(here, column), do: column
    list = Enum.map_join(columns, ", ", &~s("#{&1}"))
    types = Enum.map(columns, &Map.fetch!(there, &1))

    rows =
      source.get_dynamic_repo()
      |> SQL.stream(~s(SELECT #{list} FROM "#{table}"), [], max_rows: @batch)
      |> Stream.flat_map(& &1.rows)
      |> Stream.map(fn row ->
        [columns, types, row]
        |> Enum.zip()
        |> Map.new(fn {column, type, value} ->
          {String.to_atom(column), convert(postgres?(source), type, value)}
        end)
      end)
      |> insert(table)

    %{table: table, rows: rows, schema?: false, left: Map.keys(there) -- columns}
  end

  # Postgres to SQLite, by the catalogue's name for the type. Every other
  # pairing is passed as the driver gave it.
  defp convert(_from_postgres?, _type, nil), do: nil

  defp convert(true, type, value) do
    if postgres?(Repo), do: value, else: to_sqlite(type, value)
  end

  defp convert(false, _type, value), do: value

  # JSON as text, an array as JSON; the rest as the Ecto type of that kind
  # is stored.
  defp to_sqlite(@pg_json <> _b, value), do: Jason.encode!(value)
  defp to_sqlite("_" <> _element, value), do: Jason.encode!(value)

  defp to_sqlite(type, value) do
    case ecto_type(type, value) do
      nil -> value
      {ecto_type, value} -> dump!("a table with no schema", type, ecto_type, value)
    end
  end

  defp ecto_type(@pg_uuid, value), do: {Ecto.UUID, Ecto.UUID.load!(value)}
  defp ecto_type(@pg_bool, value), do: {:boolean, value}
  defp ecto_type(@pg_bytea, value), do: {:binary, value}
  defp ecto_type(@pg_numeric, value), do: {:decimal, value}
  defp ecto_type(@pg_date, value), do: {:date, value}

  # Stored as UTC, as every schema here declares its own.
  defp ecto_type(@pg_timestamp <> _tz, %NaiveDateTime{} = value),
    do: ecto_type(@pg_timestamp, DateTime.from_naive!(value, "Etc/UTC"))

  defp ecto_type(@pg_timestamp <> _tz, %DateTime{microsecond: {_usec, 0}} = value),
    do: {:utc_datetime, value}

  defp ecto_type(@pg_timestamp <> _tz, %DateTime{} = value), do: {:utc_datetime_usec, value}
  defp ecto_type(_type, _value), do: nil

  # In batches, so a table is never in memory whole. Answers the rows.
  defp insert(rows, table) do
    rows
    |> Stream.chunk_every(@batch)
    |> Enum.reduce(0, fn batch, total ->
      {inserted, nil} = Repo.insert_all(table, batch)
      total + inserted
    end)
  end

  # ── Checks ──────────────────────────────────────────────────────────────

  # Until the commit on SQLite. On Postgres, where a foreign key is checked
  # at each row unless it was declared deferrable, off for this transaction:
  # the role must be a superuser's.
  defp defer_foreign_keys do
    sql =
      if postgres?(Repo),
        do: "SET LOCAL session_replication_role = replica",
        else: "PRAGMA defer_foreign_keys = ON"

    Repo.query!(sql, [])
  end

  # SQLite names each row that points nowhere. Postgres checked nothing in
  # this transaction, and the row counts below are what it has.
  defp foreign_keys do
    if postgres?(Repo) do
      :ok
    else
      case Repo.query!("PRAGMA foreign_key_check", []) do
        %{rows: []} -> :ok
        %{rows: rows} -> {:error, {:foreign_keys, Enum.take(rows, 20)}}
      end
    end
  end

  defp same_rows(source, copied) do
    Enum.find_value(copied, :ok, fn %{table: table} ->
      there = count(source, table)
      here = count(Repo, table)
      if there != here, do: {:error, {:rows_differ, table, there, here}}
    end)
  end

  defp summary(copied) do
    %{
      tables: Enum.map(copied, &{&1.table, &1.rows}),
      by_column_type:
        for(%{schema?: false, rows: rows, table: table} <- copied, rows > 0, do: table),
      not_in_schema:
        for(%{schema?: true, left: [_ | _] = left, table: table} <- copied, do: {table, left})
    }
  end

  # A serial column's sequence is behind the rows just put in.
  defp after_copy(%{tables: tables}) do
    if postgres?(Repo) do
      for {table, rows} <- tables, rows > 0, {column, sequence} <- sequences(table) do
        Repo.query!(
          ~s|SELECT setval($1::regclass, (SELECT max("#{column}") FROM "#{table}"))|,
          [sequence]
        )
      end
    end

    :ok
  end

  defp sequences(table) do
    %{rows: rows} =
      Repo.query!(
        "SELECT column_name::text, pg_get_serial_sequence($1::text, column_name::text) " <>
          "FROM information_schema.columns " <>
          "WHERE table_schema = current_schema() AND table_name = $1::text",
        [table]
      )

    for [column, sequence] <- rows, sequence != nil, do: {column, sequence}
  end

  # ── Schemas ─────────────────────────────────────────────────────────────

  # Each table's schema, among the modules of core and of every loaded
  # application built on it: the web application and the host. The one with
  # the most fields, where two describe one table.
  defp schemas do
    for {app, _description, _version} <- Application.loaded_applications(),
        gamend?(app),
        module <- Application.spec(app, :modules) || [],
        source = schema_source(module),
        reduce: %{} do
      found ->
        Map.update(found, source, module, fn other ->
          if length(module.__schema__(:fields)) > length(other.__schema__(:fields)),
            do: module,
            else: other
        end)
    end
  end

  defp gamend?(:gamend_core), do: true
  defp gamend?(app), do: :gamend_core in (Application.spec(app, :applications) || [])

  # `__schema__/2` is what a schema has and `Ecto.Schema` itself does not.
  defp schema_source(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :__schema__, 2),
      do: module.__schema__(:source)
  end

  defp postgres?(repo), do: repo.__adapter__() == Ecto.Adapters.Postgres
end
