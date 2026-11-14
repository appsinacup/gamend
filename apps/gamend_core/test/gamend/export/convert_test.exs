defmodule Gamend.Export.ConvertTest do
  # async: false: it points Gamend.Repo at databases of its own.
  use ExUnit.Case, async: false

  alias Gamend.Accounts.LoginLockout
  alias Gamend.Export.Convert
  alias Gamend.Leaderboards.Leaderboard
  alias Gamend.Quests.Quest
  alias Gamend.Repo
  alias Gamend.Secrets.Secret

  # Both databases are SQLite here, so every step but Postgres' own loaders
  # runs: which tables, which columns, the dump through each schema's types,
  # the checks. With a Postgres source it was proven by hand, both ways
  # round: a host's SQLite rows into Postgres and back came out the same.
  unless Gamend.Export.database?(), do: @moduletag(:skip)

  defmodule Other do
    use Ecto.Repo, otp_app: :gamend_core, adapter: Ecto.Adapters.SQLite3
  end

  # The test database's own tables, emptied, once: every test starts from
  # two copies of it. Not migrated again here, which would compile every
  # migration a second time.
  setup_all do
    dir = Path.join(System.tmp_dir!(), "gamend-convert-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)

    template = Path.join(dir, "template.db")
    {:ok, migrated} = Repo.start_link(repo_options(Repo.config()[:database]))
    Repo.put_dynamic_repo(migrated)
    Repo.query!("VACUUM INTO ?1", [template])
    Supervisor.stop(migrated)

    # No write-ahead log: the file is copied as it is, and what a log held
    # would stay behind.
    {:ok, copy} =
      Repo.start_link([foreign_keys: :off, journal_mode: :delete] ++ repo_options(template))

    Repo.put_dynamic_repo(copy)

    %{rows: tables} =
      Repo.query!(
        "SELECT name FROM sqlite_master WHERE type = 'table' " <>
          "AND name != 'schema_migrations' AND name NOT LIKE 'sqlite_%'"
      )

    for [table] <- tables, do: Repo.query!(~s|DELETE FROM "#{table}"|)
    Supervisor.stop(copy)

    {:ok, template: template}
  end

  setup %{template: template} do
    dir = Path.join(Path.dirname(template), "#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    there = Path.join(dir, "there.db")
    here = Path.join(dir, "here.db")
    File.cp!(template, there)
    File.cp!(template, here)

    {:ok, there: there, here: here}
  end

  # Rows written as the application writes them, then the file handed to
  # the other repo, as a source is another Gamend's database.
  defp seeded(there, here, seed) do
    seeder = start_supervised!({Repo, repo_options(there)}, id: :seeder)
    Repo.put_dynamic_repo(seeder)
    seed.()
    stop_supervised!(:seeder)

    start_supervised!({Other, database: there, pool_size: 1})
    target = start_supervised!({Repo, repo_options(here)}, id: :target)
    Repo.put_dynamic_repo(target)
    :ok
  end

  defp repo_options(path),
    do: [name: nil, database: path, pool: DBConnection.ConnectionPool, pool_size: 1]

  defp stored(repo, table) do
    %{rows: rows} = repo.query!(~s|SELECT * FROM "#{table}" ORDER BY id|, [])
    rows
  end

  defp seed_every_type do
    now = DateTime.utc_now()

    Repo.insert!(%Secret{
      scope: "project",
      scope_id: Ecto.UUID.generate(),
      name: "keystore",
      ciphertext: <<0, 255, 1, 254, 128>>,
      iv: :crypto.strong_rand_bytes(12),
      tag: :crypto.strong_rand_bytes(16),
      key_id: "v1",
      expires_at: now
    })

    Repo.insert!(%Leaderboard{
      slug: "weekly",
      title: "Weekly é \"quoted\"",
      sort_order: :asc,
      operator: :best,
      hidden: true,
      starts_at: DateTime.truncate(now, :second),
      metadata: %{"zeta" => 1, "alpha" => %{"list" => [1, 2.5, "three", nil, true]}}
    })

    objective = Quest.__schema__(:embed, :objectives).related

    Repo.insert!(%Quest{
      key: "first",
      title: "First",
      objectives: [struct(objective, event: "win", target: 3, params: %{"mode" => "ranked"})]
    })

    Repo.insert!(%LoginLockout{
      key_hash: :crypto.strong_rand_bytes(32),
      failures: 2,
      window_started_at: DateTime.truncate(now, :second)
    })
  end

  @tables ~w(secrets leaderboards quests login_lockouts)

  test "every row arrives as the adapter stores it", %{there: there, here: here} do
    seeded(there, here, &seed_every_type/0)

    assert {:ok, summary} = Convert.run(Other)

    for table <- @tables do
      assert {table, 1} in summary.tables
      assert stored(Repo, table) == stored(Other, table)
    end

    # And as the application reads it: a binary, an enum, an embed.
    assert [%Secret{ciphertext: <<0, 255, 1, 254, 128>>}] = Repo.all(Secret)
    assert [%Leaderboard{sort_order: :asc, hidden: true}] = Repo.all(Leaderboard)
    assert [%Quest{objectives: [%{event: "win", target: 3}]}] = Repo.all(Quest)

    assert summary.by_column_type == []
  end

  test "a database that already has rows is refused, and keeps them", %{there: there, here: here} do
    seeded(there, here, &seed_every_type/0)
    assert {:ok, _summary} = Convert.run(Other)

    assert {:error, {:not_empty, _table}} = Convert.run(Other)
    assert length(stored(Repo, "secrets")) == 1
  end

  test "two databases on different migrations are refused", %{there: there, here: here} do
    seeded(there, here, fn ->
      Repo.query!(
        "DELETE FROM schema_migrations WHERE version = (SELECT max(version) FROM schema_migrations)"
      )
    end)

    assert {:error, {:migrations_differ, [], [_version]}} = Convert.run(Other)
    assert stored(Repo, "secrets") == []
  end

  test "a migration the source ran and this release no longer has is named, not refused",
       %{there: there, here: here} do
    seeded(there, here, fn ->
      seed_every_type()

      Repo.query!(
        "INSERT INTO schema_migrations (version, inserted_at) VALUES (20200101000000, '2020-01-01T00:00:00')"
      )
    end)

    assert {:ok, summary} = Convert.run(Other)
    assert summary.gone_migrations == ["20200101000000"]
    assert {"secrets", 1} in summary.tables
  end

  test "a source ahead of this release's migrations is refused", %{there: there, here: here} do
    seeded(there, here, fn ->
      Repo.query!(
        "INSERT INTO schema_migrations (version, inserted_at) VALUES (29990101000000, '2020-01-01T00:00:00')"
      )
    end)

    assert {:error, {:migrations_differ, ["29990101000000"], []}} = Convert.run(Other)
  end

  test "rows in a table this database lacks stop the copy, unless it is skipped",
       %{there: there, here: here} do
    seeded(there, here, fn ->
      seed_every_type()
      Repo.query!("CREATE TABLE extras (id INTEGER PRIMARY KEY, name TEXT)")
      Repo.query!("INSERT INTO extras (name) VALUES ('one')")
    end)

    assert {:error, {:no_table, "extras", 1}} = Convert.run(Other)
    assert stored(Repo, "secrets") == []

    assert {:ok, summary} = Convert.run(Other, skip: ["extras"])
    assert {"secrets", 1} in summary.tables
  end

  test "a table no schema describes is copied by its columns, and named",
       %{there: there, here: here} do
    seeded(there, here, fn ->
      Repo.query!("CREATE TABLE extras (id INTEGER PRIMARY KEY, name TEXT, at TEXT)")
      Repo.query!("INSERT INTO extras (name, at) VALUES ('one', '2026-11-14T10:00:00Z')")
    end)

    Repo.query!("CREATE TABLE extras (id INTEGER PRIMARY KEY, name TEXT, at TEXT)")

    assert {:ok, summary} = Convert.run(Other)
    assert summary.by_column_type == ["extras"]
    assert stored(Repo, "extras") == [[1, "one", "2026-11-14T10:00:00Z"]]
  end
end
