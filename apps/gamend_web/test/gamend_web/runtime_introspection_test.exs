defmodule GamendWeb.RuntimeIntrospectionTest do
  @moduledoc """
  The providers behind /admin/runtime. Everything is reflection, so the tests
  pin the *shape* and cross-check counts against the sources of truth rather
  than asserting specific content.
  """
  use Gamend.DataCase, async: false

  alias Gamend.Hooks.Declarations
  alias GamendWeb.RuntimeIntrospection, as: Introspection

  test "hooks cover every declared callback, with kind and searchable docs" do
    hooks = Introspection.hooks()

    assert length(hooks) == length(Gamend.Hooks.behaviour_info(:callbacks))
    assert Enum.all?(hooks, &(&1.kind in ["pipeline", "fanout"]))

    join = Enum.find(hooks, &(&1.name == "before_matchmaking_join"))
    assert join.kind == "pipeline"
    assert join.summary =~ "matchmaking"

    cancel = Enum.find(hooks, &(&1.name == "after_matchmaking_cancel"))
    assert cancel.kind == "fanout"
  end

  describe "plugin_env_vars/0" do
    defmodule VarsPlugin do
      def env_vars do
        [
          %{name: "MYGAME_MAX_BOTS", default: 8, description: "Bots per match"},
          %{name: "MYGAME_REGION", default: "eu", description: "Region"},
          %{name: "MYGAME_API_TOKEN", default: "", description: "Named like a secret"},
          %{name: "MYGAME_HIDDEN", default: "", description: "Declared one", secret: true},
          %{name: "GAMEND_LIMITS_MAX_PAGE_SIZE", default: 3, description: "Already a setting"}
        ]
      end
    end

    setup do
      Declarations.refresh([
        %{name: "my_game", status: :ok, hooks_module: VarsPlugin, modules: []}
      ])

      on_exit(fn ->
        Declarations.refresh([])
        Enum.each(~w(MYGAME_REGION MYGAME_API_TOKEN MYGAME_HIDDEN), &System.delete_env/1)
      end)
    end

    defp plugin_var(name), do: Enum.find(Introspection.plugin_env_vars(), &(&1.env == name))

    test "an unset variable carries its default, and comes from it" do
      assert %{value: 8, default: 8, source: :default, label: "Plugin: my_game"} =
               plugin_var("MYGAME_MAX_BOTS")
    end

    test "a set one carries what the environment holds" do
      System.put_env("MYGAME_REGION", "us")

      assert %{value: "us", default: "eu", source: :config, secret: false} =
               plugin_var("MYGAME_REGION")
    end

    test "a value is masked when declared secret or named like one" do
      System.put_env("MYGAME_API_TOKEN", "super-sensitive")
      System.put_env("MYGAME_HIDDEN", "also-sensitive")

      assert %{value: "••••••••", secret: true} = plugin_var("MYGAME_API_TOKEN")
      assert %{value: "••••••••", secret: true} = plugin_var("MYGAME_HIDDEN")
    end

    test "a variable that is a setting is left to the setting" do
      refute plugin_var("GAMEND_LIMITS_MAX_PAGE_SIZE")
    end
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

    assert length(channels) == length(GamendWeb.UserSocket.__channels__())
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

    for row <- Introspection.protobuf_messages(), do: assert(is_binary(row.source))
    for row <- Introspection.events(), do: assert(is_binary(row.source))
    for row <- Introspection.notification_types(), do: assert(is_binary(row.source))
    for row <- Introspection.data_model(), do: assert(is_binary(row.source))
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
      Introspection.protobuf_messages(),
      Introspection.channels(),
      Introspection.events(),
      Introspection.data_model(),
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
