defmodule Mix.Tasks.Gen.SdkPlaceholderTest do
  @moduledoc """
  The value a `gamend_sdk` stub answers in `:placeholder` mode has the shape
  its `@spec` promises, decided by the outermost type: `[map()]` used to match
  `map()` inside it and answer `%{}`.
  """
  use ExUnit.Case, async: true

  import Mix.Tasks.Gen.Sdk, only: [placeholder_expr_for_return_type: 1]

  test "a list answers a list, whatever it holds" do
    assert placeholder_expr_for_return_type("[map()]") == "[]"
    assert placeholder_expr_for_return_type("[String.t()]") == "[]"
    assert placeholder_expr_for_return_type("[integer()]") == "[]"
    assert placeholder_expr_for_return_type("list(map())") == "[]"
    assert placeholder_expr_for_return_type("keyword()") == "[]"
  end

  test "a map answers a map, whatever it holds" do
    assert placeholder_expr_for_return_type("%{ok: boolean()}") == "%{}"
    assert placeholder_expr_for_return_type("%{String.t() => integer()}") == "%{}"
    assert placeholder_expr_for_return_type("map()") == "%{}"
  end

  test "primitives and nil unions keep their placeholders" do
    assert placeholder_expr_for_return_type("integer()") == "0"
    assert placeholder_expr_for_return_type("String.t()") == ~s("")
    assert placeholder_expr_for_return_type(":ok") == ":ok"
    assert placeholder_expr_for_return_type("map() | nil") == "nil"
    assert placeholder_expr_for_return_type("{:ok, map()} | {:error, term()}") == "{:ok, nil}"
  end
end
