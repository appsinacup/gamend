defmodule Gamend.HooksInvokeTest do
  @moduledoc """
  `Gamend.Hooks.invoke/2` — what `Gamend.Jobs.HookWorker` runs a scheduled or
  enqueued hook through — reaches every lifecycle module, not only the one
  `:hooks_module` names.

  A plugin `PluginManager` loads never sets `:hooks_module`, so resolving
  through `module/0` alone answered `Default` for its hooks, and a host's
  nightly jobs were discarded as `:not_found` every night for a week
  (2026-10-08). The seam here is `:host_hook_modules`, which joins the same
  `lifecycle_modules/0` list a loaded plugin's module does.
  """
  use ExUnit.Case, async: false

  alias Gamend.Hooks

  defmodule NightlyHooks do
    def on_nightly_sweep(%{"mark" => mark}), do: {:ok, {:swept, mark}}
    def on_nightly_sweep(_args), do: :ok

    # A standard callback `Hooks.Default` also exports (as a no-op): the real
    # implementation must win over the no-op.
    def after_user_register(_user), do: {:ok, :registered_here}
  end

  setup do
    original = Application.get_env(:gamend_core, :host_hook_modules)
    Application.put_env(:gamend_core, :host_hook_modules, [NightlyHooks])

    on_exit(fn ->
      if original,
        do: Application.put_env(:gamend_core, :host_hook_modules, original),
        else: Application.delete_env(:gamend_core, :host_hook_modules)
    end)

    :ok
  end

  test "a hook only a lifecycle module exports is found and run" do
    assert Hooks.invoke(:on_nightly_sweep, [%{"mark" => 1}]) == {:ok, {:swept, 1}}
    assert Hooks.invoke(:on_nightly_sweep, [%{}]) == :ok
  end

  test "a module that is not Default wins over Default's no-op" do
    assert Hooks.invoke(:after_user_register, [%{}]) == {:ok, :registered_here}
  end

  test "a hook nobody exports is :not_found, naming the base module" do
    assert {:error, {:not_found, {_mod, :on_nothing_like_this, 1}}} =
             Hooks.invoke(:on_nothing_like_this, [%{}])
  end
end
