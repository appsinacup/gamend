defmodule Gamend.LiteralLintTest do
  use ExUnit.Case, async: true

  alias Gamend.LiteralLint

  defp literals(source) do
    source |> LiteralLint.occurrences_in("x.ex") |> Enum.map(& &1.literal) |> Enum.sort()
  end

  defp at(literal, module, as \\ nil) do
    %{literal: literal, file: "x.ex", line: 1, module: module, as: as}
  end

  describe "what counts" do
    test "a name in a function head, a comparison, a value and a call" do
      assert literals("""
             defmodule M do
               def run("create", server), do: enqueue(server, "start")
               def up?(server), do: server.status == "running"
               def row, do: %{"action" => "move_in"}
             end
             """) == ["create", "move_in", "running", "start"]
    end

    test "each word of a string ~w, and none of an atom one" do
      assert literals(~S|
             defmodule M do
               def slow?(a), do: a in ~w(create deploy)
               def kinds, do: ~w(one two)a
             end
             |) == ["create", "deploy"]
    end

    test "it says where" do
      assert [%{line: 2, module: "M.N", file: "x.ex"}] =
               LiteralLint.occurrences_in(
                 """
                 defmodule M.N do
                   def a(_x), do: "failed"
                 end
                 """,
                 "x.ex"
               )
    end

    test "an attribute and a private function: each names it for one module" do
      assert literals("""
             defmodule M do
               @failed "failed"
               defp running, do: "running"
               defmacrop creating, do: "creating"
             end
             """) == ["creating", "failed", "running"]
    end

    test "a comparison in a template, either way round" do
      assert literals(~S|
             defmodule M do
               def a(assigns), do: ~H'<b :if={@s == "failed"} class={"gone" != @t}>x</b>'
             end
             |) == ["failed", "gone"]
    end

    test "where a template's comparison stands" do
      source = ~S|
             defmodule M do
               def a(assigns) do
                 ~H"""
                 <i>x</i>
                 <b :if={@s == "failed"}>x</b>
                 """
               end
             end
             |

      assert [%{literal: "failed", line: 6}] = LiteralLint.occurrences_in(source, "x.ex")
    end

    test "a .heex file is a template, and its own module" do
      assert [%{literal: "failed", line: 2, module: "a/x.heex"}] =
               LiteralLint.occurrences_in(
                 ~s|<i>x</i>\n<b :if={@s == "failed"}>x</b>\n|,
                 "a/x.heex"
               )
    end
  end

  describe "what does not" do
    test "documentation" do
      assert literals("""
             defmodule M do
               @moduledoc "failed"
               @doc "failed"
               def a, do: 1
             end
             """) == []
    end

    test "a public function that is nothing but its value, and only that" do
      assert literals("""
             defmodule M do
               defmacro failed, do: "failed"
               def running(), do: "running"
               def with_arg(_x), do: "creating"
             end
             """) == ["creating"]
    end

    test "what an owner declares" do
      assert literals(~S|
             defmodule M do
               use Gamend.Names, ~w(running failed)
             end
             |) == []
    end

    test "text: gettext, Logger, raise, and anything with a space" do
      assert literals("""
             defmodule M do
               def a, do: {gettext("failed"), gettext_noop("failed"), pgettext_noop("x", "failed")}
               def b, do: Logger.info("failed")
               def c, do: raise("failed")
               def d, do: "it failed"
             end
             """) == []
    end

    test "a template's markup, and any other sigil but a string ~w" do
      assert literals(~S|
             defmodule M do
               def a(assigns), do: ~H'<b class="failed" id={"gone"}>x</b>'
               def b, do: ~r/failed/
             end
             |) == []
    end

    test "a key, however it is read" do
      assert literals("""
             defmodule M do
               def a(m), do: {m["id"], Map.get(m, "id"), m |> Map.get("id"), get_in(m, ["id"])}
               def b(%{"id" => id}), do: id
               def c(m), do: %{m | "id" => 1}
               def d(m), do: {Map.take(m, ["id"]), m |> Map.drop(["id"]), Map.split(m, ["id"])}
             end
             """) == []
    end

    test "a LiveView event's name and a header's, but not what they carry" do
      assert literals("""
             defmodule M do
               def handle_event("save", _params, socket), do: {:noreply, assign(socket, :s, "saved")}
               def a(conn), do: put_resp_header(conn, "cache-control", "no-store")
             end
             """) == ["saved"]
    end

    test "an API error's code, which the API lint reads as a literal" do
      assert literals("""
             defmodule M do
               def a(conn), do: reply_error(conn, :not_found, "not_found")
             end
             """) == []
    end

    test "the shared CSS vocabulary, booleans, and a prefix" do
      assert literals("""
             defmodule M do
               def a, do: ["badge-error", "true", "gc-", "x"]
             end
             """) == []
    end
  end

  describe "the marker" do
    test "on the line, or the line above" do
      assert literals("""
             defmodule M do
               # literal-ok: Stripe's name
               def a(_x), do: "invoice.paid"
               def b(_x), do: "invoice.lost" # literal-ok: Stripe's name
               def c(_x), do: "failed"
             end
             """) == ["failed"]
    end

    test "in a template, as a HEEx comment" do
      source = ~s|<%!-- literal-ok: the browser's --%>\n<b :if={@s == "submit"}>x</b>\n|
      assert LiteralLint.occurrences_in(source, "x.heex") == []
    end
  end

  describe "offenders/1" do
    test "a string in one module, a few times, is that module's business" do
      assert LiteralLint.offenders(for _ <- 1..4, do: at("failed", "A")) == []
    end

    test "a string in two modules is a name" do
      assert [%{literal: "failed", count: 2, modules: 2}] =
               LiteralLint.offenders([at("failed", "A"), at("failed", "B")])
    end

    test "so is a string used over and over in one" do
      assert [%{literal: "failed", count: 5, modules: 1}] =
               LiteralLint.offenders(for _ <- 1..5, do: at("failed", "A"))
    end

    test "most used first" do
      found = [at("a1", "A"), at("a1", "B"), at("b1", "A"), at("b1", "B"), at("b1", "C")]
      assert [%{literal: "b1"}, %{literal: "a1"}] = LiteralLint.offenders(found)
    end

    test "an attribute is its module's own name" do
      assert LiteralLint.offenders([at("ebin", "Gamend.Hooks.A", :ebin)]) == []
    end

    test "the same name twice in one context has two homes" do
      assert [%{literal: "ebin", count: 2, modules: 2}] =
               LiteralLint.offenders([
                 at("ebin", "Gamend.Hooks.A", :ebin),
                 at("ebin", "Gamend.Hooks.B", :ebin)
               ])
    end

    test "across contexts it is a coincidence, and so is another name" do
      assert LiteralLint.offenders([
               at("page", "Gamend.Accounts.A", :page),
               at("page", "GamendWeb.Schemas.B", :page)
             ]) == []

      assert LiteralLint.offenders([
               at("page", "Gamend.Hooks.A", :page),
               at("page", "Gamend.Hooks.B", :seed)
             ]) == []
    end

    test "a local name does not add to a string typed out elsewhere" do
      assert LiteralLint.offenders([at("failed", "A"), at("failed", "B.C", :failed)]) == []
    end
  end
end
