defmodule Gamend.Hooks.DefaultsTest do
  @moduledoc """
  `use Gamend.Hooks` is the same in the SDK, which a Mix-built plugin compiles
  against, and in the engine, which an in-process build compiles against: the
  SDK's `Gamend.Hooks.Defaults` is this module's source, written by
  `mix gen.sdk`.
  """
  use ExUnit.Case, async: true

  @sdk_copy Path.expand("../../../../../sdk/lib/gamend/hooks/defaults.ex", __DIR__)
  @source Path.expand("../../../lib/gamend/hooks/defaults.ex", __DIR__)

  @tag skip: not File.exists?(@sdk_copy) && "no sdk/ in this checkout"
  test "the SDK carries the engine's defaults, as `mix gen.sdk` last wrote them" do
    [_generated_header, copy] = @sdk_copy |> File.read!() |> String.split("\n", parts: 2)

    assert copy == File.read!(@source), "run `mix gen.sdk`"
  end

  test "a module using it gets every overridable default" do
    {:module, module, _, _} =
      Module.create(
        Module.concat(__MODULE__, "Plugin#{System.unique_integer([:positive])}"),
        quote do
          use Gamend.Hooks

          @impl true
          def after_user_register(_user), do: :mine
        end,
        __ENV__
      )

    assert Gamend.Hooks in Keyword.get(module.module_info(:attributes), :behaviour, [])
    assert module.after_user_register(nil) == :mine
    assert module.before_lobby_create(%{a: 1}) == {:ok, %{a: 1}}
    assert module.before_kv_get("k", []) == :public
    assert module.validate_username("x") == :default
  end
end
