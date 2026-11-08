defmodule Gamend.LiteralLintTest do
  use ExUnit.Case, async: true

  alias Gamend.LiteralLint

  defp literals(source) do
    source |> LiteralLint.occurrences_in("x.ex") |> Enum.map(& &1.literal) |> Enum.sort()
  end

  defp at(literal, module), do: %{literal: literal, file: "x.ex", line: 1, module: module}

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
  end

  describe "what does not" do
    test "the value of an attribute, documentation included" do
      assert literals("""
             defmodule M do
               @moduledoc "failed"
               @failed "failed"
               def a, do: @failed
             end
             """) == []
    end

    test "a function that is nothing but its value, and only that" do
      assert literals("""
             defmodule M do
               defmacro failed, do: "failed"
               def running(), do: "running"
               def with_arg(_x), do: "creating"
             end
             """) == ["creating"]
    end

    test "text: gettext, Logger, raise, and anything with a space" do
      assert literals("""
             defmodule M do
               def a, do: gettext("failed")
               def b, do: Logger.info("failed")
               def c, do: raise("failed")
               def d, do: "it failed"
             end
             """) == []
    end

    test "a template, and any sigil but a string ~w" do
      assert literals(~S|
             defmodule M do
               def a(assigns), do: ~H"<b :if={@s == "failed"}>x</b>"
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
  end

  describe "the baseline" do
    setup do
      found =
        for literal <- ["failed", "gamend.db"], module <- ["A", "B"], do: at(literal, module)

      {:ok, offenders: LiteralLint.offenders(found)}
    end

    test "a count within it passes, and one past it does not", %{offenders: offenders} do
      assert LiteralLint.new_offenders(offenders, %{"failed" => 2, "gamend.db" => 2}) == []

      assert [%{literal: "failed"}] =
               LiteralLint.new_offenders(offenders, %{"failed" => 1, "gamend.db" => 2})
    end

    test "a string it does not know is new", %{offenders: offenders} do
      assert [_, _] = LiteralLint.new_offenders(offenders, %{})
    end

    test "reads back what it wrote, comments aside", %{offenders: offenders} do
      assert offenders |> LiteralLint.format_baseline() |> LiteralLint.parse_baseline() ==
               %{"failed" => 2, "gamend.db" => 2}
    end
  end
end
