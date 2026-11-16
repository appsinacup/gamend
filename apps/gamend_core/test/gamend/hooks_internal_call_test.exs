defmodule Gamend.Hooks.InternalCallTest.ReturnOkTuple do
  def before_lobby_create(attrs), do: {:ok, Map.put(attrs, "x", 1)}
end

defmodule Gamend.Hooks.InternalCallTest.ReturnRaw do
  def before_lobby_create(attrs), do: Map.put(attrs, "raw", true)
end

defmodule Gamend.Hooks.InternalCallTest.NoCallbacks do
  # intentionally missing before_lobby_create
end

defmodule Gamend.Hooks.InternalCallTest do
  use ExUnit.Case, async: false
  alias Gamend.Hooks
  alias Gamend.Hooks.InternalCallTest.{NoCallbacks, ReturnOkTuple, ReturnRaw}

  setup do
    # preserve original config and restore after
    original = Application.get_env(:gamend_core, :hooks_module)

    on_exit(fn ->
      if original do
        Application.put_env(:gamend_core, :hooks_module, original)
      else
        Application.delete_env(:gamend_core, :hooks_module)
      end
    end)

    :ok
  end

  test "internal_call unwraps hook returning {:\:ok, value} (no double wrap)" do
    Application.put_env(:gamend_core, :hooks_module, ReturnOkTuple)

    assert {:ok, %{"name" => "t1", "x" => 1}} =
             Hooks.internal_call(:before_lobby_create, [%{name: "t1"}])
  end

  test "internal_call unwraps hook returning raw value and wraps it in {:ok, value}" do
    Application.put_env(:gamend_core, :hooks_module, ReturnRaw)

    # raw return should be normalized to {:ok, value}
    assert {:ok, %{"name" => "t2", "raw" => true}} =
             Hooks.internal_call(:before_lobby_create, [%{name: "t2"}])
  end

  test "internal_call returns sensible default when callback missing" do
    Application.put_env(:gamend_core, :hooks_module, NoCallbacks)

    assert {:ok, %{"name" => "t3"}} =
             Hooks.internal_call(:before_lobby_create, [%{name: "t3"}])
  end
end
