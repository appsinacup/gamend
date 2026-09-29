defmodule HandleWebRTC.WebRTCLobbyHook do
  use Mix.Project

  def project do
    [
      app: :webrtc_lobby_hook,
      version: "0.1.1",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      env: [hooks_module: Gamend.Modules.WebRTCLobbyHook]
    ]
  end

  # NOTE: This example lives inside the main server repo, so we depend on the
  # in-repo SDK via a path dependency.
  defp deps do
    [
      shared_dep(:gamend_sdk, "../../../sdk"),
      shared_dep(:gamend_plugin_tools, "../../../sdk_tools"),
      # Only what the engine ships, so a release can build this plugin
      # in-process (Gamend.Hooks.PluginBuilder), with no Hex to fetch from.
      {:phoenix, "~> 1.8.3"}
    ]
  end

  defp shared_dep(app, local_path) do
    if File.dir?(local_path) do
      {app, path: local_path, runtime: false}
    else
      {app, github: "appsinacup/gamend", override: true, runtime: false}
    end
  end
end
