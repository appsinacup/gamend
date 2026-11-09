defmodule Gamend.NamesTest.Status do
  use Gamend.Names, ~w(running failed)

  defmacro down, do: @all -- ["running"]
end

defmodule Gamend.NamesTest.Scope do
  use Gamend.Names, ~w(all mine)
end

defmodule Gamend.NamesTest do
  use ExUnit.Case, async: true

  require Gamend.NamesTest.Scope, as: Scope
  require Gamend.NamesTest.Status, as: Status

  defp up?(Status.running()), do: true
  defp up?(_status), do: false

  defp down?(status) when status in Status.down(), do: true
  defp down?(_status), do: false

  test "a value's macro stands in a pattern, and `@all` stays for a part of the set" do
    assert up?("running")
    refute up?("failed")
    assert down?("failed")
    refute down?("running")
  end

  test "all/0 is every value, in order" do
    assert Status.all() == ["running", "failed"]
  end

  test "a set holding \"all\" keeps that name for the value" do
    assert Scope.all() == "all"
    assert Scope.mine() == "mine"
  end
end
