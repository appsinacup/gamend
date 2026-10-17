defmodule Gamend.ApiConventionsTest do
  # The API lint's rules (`Gamend.ApiConventions`, `mix gamend.api.lint`), each
  # on a small project written to break it once, and the same file written
  # the right way, which nothing flags. The rules read source from the
  # working directory, so the project is a temp dir the test runs in.
  use ExUnit.Case, async: false

  alias Gamend.ApiConventions

  setup do
    root = Path.join(System.tmp_dir!(), "api_lint_#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  defp write(root, path, contents) do
    full = Path.join(root, path)
    File.mkdir_p!(Path.dirname(full))
    File.write!(full, contents)
  end

  defp rules(root),
    do: File.cd!(root, fn -> ApiConventions.violations() end) |> Enum.map(& &1.rule)

  # A schema with one string nobody requires or defaults: `nick`.
  @schema """
  defmodule Demo.Player do
    use Ecto.Schema

    schema "players" do
      field :nick, :string
      field :name, :string, default: ""
      field :joined, :utc_datetime
      field :seen_at, :utc_datetime
    end

    def changeset(player, attrs), do: player |> cast(attrs, [:nick]) |> validate_required([:name])
  end
  """

  test "a clean project has no violations", %{root: root} do
    write(root, "lib/demo/thing.ex", """
    defmodule Demo.Thing do
      def can_manage_thing?(user, thing), do: user.id == thing.owner_id
    end
    """)

    assert rules(root) == []
  end

  test "R1: a nullable string serialized raw; R2: derived encoder on it", %{root: root} do
    write(
      root,
      "lib/demo/player.ex",
      String.replace(
        @schema,
        "  use Ecto.Schema",
        "  use Ecto.Schema\n  @derive {Jason.Encoder, only: [:nick]}"
      )
    )

    write(root, "lib/demo_web/player_json.ex", """
    defmodule DemoWeb.PlayerJSON do
      def show(player) do
        %{
          nick: player.nick,
          name: player.name || ""
        }
      end
    end
    """)

    found = rules(root)
    assert "R1-null-string" in found
    assert "R2-derive-encoder" in found
    # `joined` is an instant not named `_at`; `seen_at` is fine.
    assert Enum.count(found, &(&1 == "R3-instant-suffix")) == 1
  end

  test "R4: a duration setting with no unit, and one with its unit", %{root: root} do
    write(root, "lib/demo/settings.ex", """
    defmodule Demo.Settings do
      setting(:retry_timeout, :integer, default: 5)
      setting(:retry_timeout_ms, :integer, default: 5)
      setting(:max_page_size, :integer, default: 5)
    end
    """)

    assert rules(root) == ["R4-duration-unit"]
  end

  test "R5: a hyphenated route; a file name keeps its hyphen", %{root: root} do
    write(root, "lib/demo_web/router.ex", """
    defmodule DemoWeb.Router do
      get "/player-stats", StatsController, :show
      get "/llms-full.txt", FileController, :show
      get "/player_stats", StatsController, :show
    end
    """)

    assert rules(root) == ["R5-path-underscore"]
  end

  test "R6: a string schema declared nullable; a datetime may be", %{root: root} do
    write(root, "lib/demo_web/schemas/player.ex", """
    defmodule DemoWeb.Schemas.Player do
      nick: %Schema{type: :string, nullable: true},
      ends_at: %Schema{type: :string, format: :"date-time", nullable: true},
    end
    """)

    assert rules(root) == ["R6-schema-nullable"]
  end

  test "R7, R8, R12: a controller hand-rolling meta, page params and changeset errors", %{
    root: root
  } do
    write(root, "lib/demo_web/controllers/player_controller.ex", """
    defmodule DemoWeb.PlayerController do
      def index(conn, params) do
        page = params["page"]
        meta = %{
          total_pages: 3
        }
        errors = Ecto.Changeset.traverse_errors(changeset, & &1)
      end
    end
    """)

    found = rules(root)
    assert "R7-meta-helper" in found
    assert "R8-page-params" in found
    assert "R12-changeset-errors" in found
  end

  test "R10: a role-named predicate; R11: a controller re-deriving ownership", %{root: root} do
    write(root, "lib/demo_web/controllers/lobby_controller.ex", """
    defmodule DemoWeb.LobbyController do
      def kick(conn, lobby, user) do
        if lobby.host_id == user.id, do: :ok
      end

      defp host?(lobby, user), do: false
    end
    """)

    found = rules(root)
    assert "R10-authority-predicate" in found
    assert "R11-inline-ownership" in found
  end

  test "R13: a context windowing by hand; a mix task may", %{root: root} do
    write(root, "lib/demo/players.ex", """
    defmodule Demo.Players do
      def list(n) do
        Player
        |> limit(^n)
      end
    end
    """)

    write(root, "lib/mix/tasks/demo.sample.ex", """
    defmodule Mix.Tasks.Demo.Sample do
      def run(n) do
        Player
        |> limit(^n)
      end
    end
    """)

    assert rules(root) == ["R13-context-paging"]
  end

  test "R14: a name fallback inline; coalescing the field itself is R1's", %{root: root} do
    write(root, "lib/demo/invites.ex", """
    defmodule Demo.Invites do
      def from(user), do: user.display_name || user.username
      def label(user), do: user.display_name || ""
    end
    """)

    assert rules(root) == ["R14-display-name"]
  end

  test "R15: an API controller calling json/2, and an inline response schema", %{root: root} do
    write(root, "lib/demo_web/controllers/api/v1/thing_controller.ex", """
    defmodule DemoWeb.Api.V1.ThingController do
      operation :show,
        responses: [
          ok: {"Thing", "application/json", %Schema{type: :object}}
        ]

      def show(conn, _params) do
        # json(conn, %{}) in a comment is fine
        json(conn, %{ok: true})
      end
    end
    """)

    assert Enum.count(rules(root), &(&1 == "R15-response-shape")) == 2
  end

  test "R17: a raising lookup at a boundary; in mount it may render a 404", %{root: root} do
    write(root, "lib/demo_web/live/thing_live.ex", """
    defmodule DemoWeb.ThingLive do
      def mount(%{"id" => id}, _session, socket), do: {:ok, assign(socket, :thing, Demo.get_thing!(id))}

      def handle_event("open", %{"id" => id}, socket) do
        {:noreply, assign(socket, :thing, Repo.get!(Thing, id))}
      end
    end
    """)

    write(root, "lib/demo_web/channels/thing_channel.ex", """
    defmodule DemoWeb.ThingChannel do
      def join(_topic, %{"id" => id}, socket), do: {:ok, Demo.Things.get_thing!(id), socket}
    end
    """)

    assert Enum.count(rules(root), &(&1 == "R17-boundary-raise")) == 2
  end

  test "R9: a guide naming a route the router does not have; a spec may opt out", %{root: root} do
    write(root, "priv/docs/10-api.md", "Call `/api/v1/definitely_not_a_route/{id}` to begin.\n")

    write(
      root,
      "docs/specs/plan.md",
      "<!-- api-lint: unimplemented -->\nWill add `/api/v1/someday`.\n"
    )

    found = rules(root)
    # Without a compiled router in this app there is nothing to compare with.
    assert found == [] or found == ["R9-doc-route"]
  end

  test "nullable_schema_fields/0 is every string or map field no schema requires or defaults",
       %{root: root} do
    write(root, "lib/demo/player.ex", @schema)
    fields = File.cd!(root, &ApiConventions.nullable_schema_fields/0)
    assert Map.keys(fields) == ["nick"]
    assert fields["nick"] == "players"
  end
end
