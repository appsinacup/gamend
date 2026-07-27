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
      env: [hooks_module: GameServer.Modules.WebRTCLobbyHook]
    ]
  end

  # NOTE: This example lives inside the main server repo, so we depend on the
  # in-repo SDK via a path dependency.
  defp deps do
    [
      {:game_server_sdk, path: "../../../sdk", runtime: false, optional: true},
      {:game_server_plugin_tools, path: "../../../sdk_tools", runtime: false},
      {:bunt, "~> 1.0"},
      {:phoenix, "~> 1.8.3"},
    ]
  end
end
