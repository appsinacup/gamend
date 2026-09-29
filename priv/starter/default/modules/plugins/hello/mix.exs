defmodule Hello.MixProject do
  use Mix.Project

  # `gamend plugin.bundle` builds this plugin from scripts/*.gd without Mix,
  # reading the values below as written. With Elixir installed, the same
  # project builds with `mix deps.get && mix bundle`.
  def project do
    [
      app: :hello,
      version: "0.1.0",
      elixir: "~> 1.20",
      elixirc_paths: ["gen"],
      deps: deps(),
      aliases: [bundle: ["gamend.gdscript.compile", "plugin.bundle"]]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      env: [hooks_module: Gamend.Modules.Hello]
    ]
  end

  defp deps do
    [
      {:gamend_sdk, "~> 1.0", runtime: false, optional: true},
      {:gamend_plugin_tools, "~> 1.0", runtime: false}
    ]
  end
end
