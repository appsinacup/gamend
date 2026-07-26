defmodule GameServerWeb.Http do
  @moduledoc """
  How the endpoint is addressed and who may call it from a browser.

  `PORT` is inherited: every PaaS injects it and renaming it would break
  every such deployment.
  """

  use GameServer.Settings.Provider,
    app: :game_server_web,
    group: :http,
    label: "Server & HTTP"

  setting(:port, :integer,
    default: 4000,
    doc: "TCP port the HTTP listener binds."
  )

  setting(:host, :string,
    default: "localhost",
    doc: "Public hostname, used to build URLs and OAuth redirect URIs."
  )

  setting(:scheme, :string,
    doc: "http or https. Defaults to http for localhost, https otherwise."
  )

  setting(:server, :boolean,
    default: false,
    doc: "Start the HTTP listener. Only needed when running as a release."
  )

  # Structured as a list so an entry never has to be parsed out of one string.
  setting(:allowed_origins, :list,
    default: [],
    doc:
      "Browser CORS/WebSocket origin allowlist. Empty allows any origin. Prefix an entry with `regex:` for a pattern."
  )
end
