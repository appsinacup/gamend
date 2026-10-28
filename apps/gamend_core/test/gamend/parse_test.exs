defmodule Gamend.ParseTest do
  use ExUnit.Case, async: true

  alias Gamend.Parse

  describe "integer/1" do
    test "accepts integers and exact integer strings" do
      assert Parse.integer(42) == 42
      assert Parse.integer("42") == 42
      assert Parse.integer("-7") == -7
      assert Parse.integer("  42 ") == 42
    end

    # The whole reason this is strict: a stored value must not become the
    # prefix of whatever was sent.
    test "rejects partial numbers instead of keeping the prefix" do
      assert Parse.integer("12abc") == nil
      assert Parse.integer("1.5") == nil
    end

    test "rejects everything that is not an integer, without raising" do
      for value <- ["abc", "", nil, 1.5, %{}, [], :atom] do
        assert Parse.integer(value) == nil, "#{inspect(value)} should not parse"
      end
    end
  end

  test "integer/2 substitutes the default only when parsing fails" do
    assert Parse.integer("9", 1) == 9
    assert Parse.integer("x", 1) == 1
    assert Parse.integer(0, 1) == 0
  end

  describe "uuid/1" do
    test "takes the hyphenated form, in either case" do
      id = Ecto.UUID.generate()
      assert Parse.uuid(id) == id
      assert Parse.uuid(String.upcase(id)) == id
    end

    # Ecto.UUID.cast/1 reads any 16 bytes as a raw UUID.
    test "refuses a 16-character string and anything else" do
      assert Parse.uuid("weekend-gauntlet") == nil
      assert Parse.uuid("not-a-uuid") == nil
      assert Parse.uuid(nil) == nil
      assert Parse.uuid(42) == nil
    end
  end

  describe "string_keys/1" do
    test "stringifies atom keys at the top level only" do
      assert Parse.string_keys(%{"b" => 2, a: 1, c: %{d: 3}}) == %{
               "a" => 1,
               "b" => 2,
               "c" => %{d: 3}
             }
    end
  end

  describe "string_keys_deep/1" do
    test "stringifies nested maps and maps inside lists" do
      assert Parse.string_keys_deep(%{a: %{b: [%{c: 1}]}}) == %{"a" => %{"b" => [%{"c" => 1}]}}
    end

    # The provider copy it replaced turned a struct into a plain string-keyed map.
    test "leaves structs intact" do
      at = ~U[2026-09-16 10:00:00Z]
      assert Parse.string_keys_deep(%{at: at}) == %{"at" => at}
    end
  end
end
