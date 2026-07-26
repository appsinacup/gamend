defmodule GameServerWeb.RuntimeIntrospectionTest do
  @moduledoc """
  The providers behind /admin/runtime. Everything is reflection, so the tests
  pin the *shape* and cross-check counts against the sources of truth rather
  than asserting specific content.
  """
  use GameServer.DataCase, async: false

  alias GameServerWeb.RuntimeIntrospection, as: Introspection

  test "hooks cover every declared callback, with kind and searchable docs" do
    hooks = Introspection.hooks()

    assert length(hooks) == length(GameServer.Hooks.behaviour_info(:callbacks))
    assert Enum.all?(hooks, &(&1.kind in ["pipeline", "fanout"]))

    join = Enum.find(hooks, &(&1.name == "before_matchmaking_join"))
    assert join.kind == "pipeline"
    assert join.summary =~ "matchmaking"

    cancel = Enum.find(hooks, &(&1.name == "after_matchmaking_cancel"))
    assert cancel.kind == "fanout"
  end

  test "env vars include every limit, and unset rows carry their default" do
    rows = Introspection.env_vars()
    by_name = Map.new(rows, &{&1.name, &1})

    for key <- Map.keys(GameServer.Limits.defaults()) do
      name = "GAMEND_LIMITS_#{key |> Atom.to_string() |> String.upcase()}"
      assert Map.has_key?(by_name, name), "limit #{name} missing from env grid"
    end

    # A limit nobody sets in tests shows its compiled default.
    row = by_name["GAMEND_LIMITS_MAX_MATCHMAKING_PLAYERS"]
    refute row.set
    assert row.default == "64"
  end

  test "env vars mask secret-looking values" do
    System.put_env("GAMEND_AUTH_SECRET_KEY_BASE", "super-sensitive")

    row = Introspection.env_vars() |> Enum.find(&(&1.name == "GAMEND_AUTH_SECRET_KEY_BASE"))

    if row do
      assert row.value == "••••••••"
      refute row.search =~ "sensitive"
    end
  after
    System.delete_env("GAMEND_AUTH_SECRET_KEY_BASE")
  end

  test "protobuf and data model attribute rows to the plugin that owns them" do
    # Both providers scan PluginManager.list/0, so a plugin's messages and
    # schemas appear without any registration step. The example plugin ships
    # protobuf messages; every row is attributed to its owner.
    proto = Introspection.protobuf_messages()
    model = Introspection.data_model()

    assert Enum.all?(proto, &is_binary(&1.source))
    assert Enum.all?(model, &is_binary(&1.source))

    # Server-owned rows are labelled "server"; anything else is a plugin name.
    assert Enum.any?(proto, &(&1.source == "server"))
    assert Enum.all?(model, &(&1.source == "server")), "no plugin ships Ecto schemas yet"

    for row <- model, row.source != "server" do
      assert row.domain == row.source, "plugin tables group under the plugin name"
    end
  end

  test "protobuf messages include the realtime schema with numbered fields" do
    rows = Introspection.protobuf_messages()

    lobby = Enum.find(rows, &(&1.module == "Gamend.Realtime.V1.Lobby"))
    assert lobby.source == "server"
    assert lobby.syntax == "proto3"
    assert lobby.field_count > 10
    assert %{tag: 1, name: "id", type: "string"} = hd(lobby.fields)
  end

  test "channels mirror the socket registry" do
    channels = Introspection.channels()

    assert length(channels) == length(GameServerWeb.UserSocket.__channels__())
    assert Enum.any?(channels, &(&1.pattern == "user:*"))
  end

  test "data model covers every core schema, with typed fields and associations" do
    rows = Introspection.data_model()
    tables = Enum.map(rows, & &1.table)

    assert "users" in tables
    assert "matchmaking_tickets" in tables

    tickets = Enum.find(rows, &(&1.table == "matchmaking_tickets"))
    assert Enum.any?(tickets.assocs, &(&1.name == "party" and &1.related_table == "parties"))
    assert Enum.any?(tickets.fields, &(&1.name == "status" and &1.type == "string"))
    assert tickets.domain == "Matchmaking"
  end

  test "the domain flowchart boxes every domain and marks cross-domain edges" do
    rows = Introspection.data_model()
    chart = Introspection.mermaid_domain_flowchart()

    assert String.starts_with?(chart, "flowchart")

    for domain <- rows |> Enum.map(& &1.domain) |> Enum.uniq() do
      assert chart =~ ~s(subgraph dom_#{domain}["#{domain}"]),
             "domain #{domain} has no subgraph box"
    end

    for row <- rows do
      assert chart =~ "#{row.table}[", "table #{row.table} missing from the flowchart"

      # Nodes list every field, not just a count.
      for f <- row.fields do
        assert chart =~ "#{f.name} : #{f.type}",
               "field #{row.table}.#{f.name} missing from the flowchart"
      end
    end

    # matchmaking_tickets -> users crosses a domain boundary (==>), while
    # tournament_entries -> tournaments stays inside one (-->).
    assert chart =~ ~r/matchmaking_tickets ==>\|user_id\| users/
    assert chart =~ ~r/tournament_entries -->\|tournament_id\| tournaments/
  end

  test "advisory locks expose the namespace registry" do
    locks = Introspection.advisory_locks()

    assert Enum.any?(locks, &(&1.name == "matchmaking_sweep"))
    assert Enum.map(locks, & &1.namespace_id) == Enum.sort(Enum.map(locks, & &1.namespace_id))
  end

  test "migrations report applied status" do
    migrations = Introspection.migrations()

    assert migrations != []
    assert Enum.all?(migrations, &(&1.status in ["up", "down"]))
  end

  test "rows carry the field their tab's facet filters on" do
    # The runtime page derives each dropdown's options from these fields, so a
    # provider dropping one silently empties its filter.
    for row <- Introspection.hooks(),
        do: assert(row.implemented in ["implemented", "not implemented"])

    for row <- Introspection.env_vars(), do: assert(row.state in ["set", "unset"])
    for row <- Introspection.protobuf_messages(), do: assert(is_binary(row.source))
    for row <- Introspection.events(), do: assert(is_binary(row.source))
    for row <- Introspection.notification_types(), do: assert(is_binary(row.source))
    for row <- Introspection.data_model(), do: assert(is_binary(row.source))
    for row <- Introspection.dynamic_rpcs(), do: assert(is_binary(row.plugin))
    for row <- Introspection.migrations(), do: assert(is_binary(row.status))
  end

  test "hook implemented flag agrees with its implementers list" do
    for row <- Introspection.hooks() do
      expected = if row.implementers == [], do: "not implemented", else: "implemented"
      assert row.implemented == expected
    end
  end

  test "every provider row has the search blob the grid filters on" do
    providers = [
      Introspection.hooks(),
      Introspection.env_vars(),
      Introspection.protobuf_messages(),
      Introspection.channels(),
      Introspection.events(),
      Introspection.data_model(),
      Introspection.plugins(),
      Introspection.dynamic_rpcs(),
      Introspection.scheduled_jobs(),
      Introspection.advisory_locks(),
      Introspection.migrations()
    ]

    for rows <- providers, row <- rows do
      assert is_binary(row.search)
      assert row.search == String.downcase(row.search)
      assert is_binary(row.id) or is_integer(row.id)
    end
  end
end
