defmodule Gamend.Hooks.PluginBuilderTest do
  # Manipulates PATH, which is process-global.
  use ExUnit.Case, async: false

  alias Gamend.Hooks.PluginBuilder

  # System.find_executable/1 resolves a bare name through PATH, so emptying it
  # is enough to stand in for a release image that ships no `mix` — no stubbing
  # seam in the production module required.
  defp without_mix_on_path(fun) do
    original = System.get_env("PATH")

    try do
      System.put_env("PATH", "")
      fun.()
    after
      System.put_env("PATH", original || "")
    end
  end

  describe "available?/0 and mode/0" do
    test "builds with mix when a mix executable is reachable" do
      assert PluginBuilder.available?()
      assert PluginBuilder.mode() == :mix
    end

    # A release ships the compiler but no mix: it builds in-process.
    test "builds in-process when it is not" do
      without_mix_on_path(fn ->
        assert PluginBuilder.available?()
        assert PluginBuilder.mode() == :in_process
      end)
    end
  end

  describe "build/1" do
    test "refuses a forced mix build up front when mix is unavailable" do
      # Without the guard this reaches System.cmd/3, which raises :enoent and
      # surfaces in the admin UI as an opaque build failure. The caller needs
      # to distinguish "this image cannot build" from "this build broke".
      without_mix_on_path(fn ->
        assert PluginBuilder.build("anything", mode: :mix) == {:error, :mix_unavailable}
        assert PluginBuilder.build("anything") == {:error, {:unknown_plugin, "anything"}}
      end)
    end

    test "refuses a name that is not one of the buildable plugins" do
      assert PluginBuilder.build("definitely-not-a-plugin") ==
               {:error, {:unknown_plugin, "definitely-not-a-plugin"}}
    end

    # `mix compile` evaluates the mix.exs in its working directory, so the
    # directory is code, not a parameter. The name is reduced to a basename and
    # must name a plugin we actually ship.
    test "cannot be steered out of the sources directory" do
      assert {:error, {:unknown_plugin, _}} = PluginBuilder.build("../../../../tmp/evil")
      assert {:error, {:unknown_plugin, _}} = PluginBuilder.build("/etc")

      assert {:error, {:unknown_plugin, _}} =
               PluginBuilder.build("../../../../tmp/evil", mode: :in_process)
    end
  end

  describe "list_buildable_plugins/0" do
    test "returns a sorted list and never raises on a missing sources dir" do
      plugins = PluginBuilder.list_buildable_plugins()

      assert is_list(plugins)
      assert plugins == Enum.sort(plugins)
    end
  end
end
