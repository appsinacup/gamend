defmodule Mix.Tasks.Gen.SdkPlaceholderTest do
  @moduledoc """
  The value a `gamend_sdk` stub answers in `:placeholder` mode has the shape
  its `@spec` promises, decided by the outermost type: `[map()]` used to match
  `map()` inside it and answer `%{}`.
  """
  use ExUnit.Case, async: true

  import Mix.Tasks.Gen.Sdk, only: [default_expr_for_arg: 1, placeholder_expr_for_return_type: 1]

  test "a default naming a module only the engine has becomes nil" do
    assert default_expr_for_arg(~S|reason \\ CheckReason.cancelled()|) == "nil"
    assert default_expr_for_arg(~S|kind \\ Gamend.Quests.QuestStatus.active()|) == "nil"
  end

  test "a default the SDK can compile is copied as written" do
    assert default_expr_for_arg(~S|now \\ DateTime.utc_now()|) == "DateTime.utc_now()"
    assert default_expr_for_arg(~S|opts \\ []|) == "[]"
    assert default_expr_for_arg("id") == nil
  end

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
