defmodule Gamend.Hooks.HostModulesTest.Deletions do
  def after_user_deleted(user) do
    send(:persistent_term.get({__MODULE__, :test_pid}), {:host_saw, user.id})
    :ok
  end
end

defmodule Gamend.Hooks.HostModulesTest do
  use ExUnit.Case, async: false

  alias Gamend.Hooks
  alias Gamend.Hooks.HostModulesTest.Deletions

  setup do
    original = Application.get_env(:gamend_core, :host_hook_modules)
    :persistent_term.put({Deletions, :test_pid}, self())

    on_exit(fn ->
      :persistent_term.erase({Deletions, :test_pid})

      if original,
        do: Application.put_env(:gamend_core, :host_hook_modules, original),
        else: Application.delete_env(:gamend_core, :host_hook_modules)
    end)
  end

  test "a host module hears the event it implements, beside the hooks module" do
    Application.put_env(:gamend_core, :host_hook_modules, [Deletions])

    Hooks.internal_call(:after_user_deleted, [%{id: "u1"}])

    assert_receive {:host_saw, "u1"}, 1_000
    # The hooks module stays the one `Gamend.Hooks.call/3` reaches.
    assert Hooks.module() != Deletions
  end

  test "is not called for what it does not implement, and nothing changes unset" do
    Application.put_env(:gamend_core, :host_hook_modules, [Deletions])
    assert {:ok, %{"name" => "x"}} = Hooks.internal_call(:before_lobby_create, [%{"name" => "x"}])

    Application.delete_env(:gamend_core, :host_hook_modules)
    Hooks.internal_call(:after_user_deleted, [%{id: "u2"}])
    refute_receive {:host_saw, "u2"}, 200
  end
end
