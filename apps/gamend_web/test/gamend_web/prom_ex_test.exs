defmodule GamendWeb.PromExTest do
  @moduledoc """
  A host's own PromEx plugins ride on core's (`GamendWeb.PromEx.plugins/0`)
  through `config :gamend_web, :host_prom_ex_plugins`, the way its plugs ride
  on the endpoint through `:host_plugs`.
  """
  # App env is process-wide.
  use ExUnit.Case, async: false

  # No `alias GamendWeb.PromEx` here: it would make `use PromEx.Plugin`
  # below resolve to `GamendWeb.PromEx.Plugin`.
  defmodule HostPlugin do
    @moduledoc false
    use PromEx.Plugin
  end

  setup do
    before = Application.get_env(:gamend_web, :host_prom_ex_plugins)

    on_exit(fn ->
      if before == nil,
        do: Application.delete_env(:gamend_web, :host_prom_ex_plugins),
        else: Application.put_env(:gamend_web, :host_prom_ex_plugins, before)
    end)

    :ok
  end

  test "core's plugins come first, the host's are appended, none when unset" do
    Application.delete_env(:gamend_web, :host_prom_ex_plugins)
    core = GamendWeb.PromEx.plugins()
    assert PromEx.Plugins.Beam in core
    assert GamendWeb.PromEx.CachePlugin in core

    Application.put_env(:gamend_web, :host_prom_ex_plugins, [HostPlugin])
    plugins = GamendWeb.PromEx.plugins()
    assert List.last(plugins) == HostPlugin
    assert plugins -- [HostPlugin] == core
  end
end
