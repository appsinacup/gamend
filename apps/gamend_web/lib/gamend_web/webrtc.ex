defmodule GamendWeb.WebRTC do
  @moduledoc """
  The ICE servers the server's own WebRTC peer (`GamendWeb.WebRTCPeer`) uses.

  STUN finds the server's public address; TURN relays traffic when no direct
  path exists, which a server behind NAT or a UDP-hostile network needs. Both
  are settings, so a deployment adds a TURN relay with env vars alone.

  A host that sets `config :gamend_web, :webrtc, ice_servers: [...]` keeps full
  control: that list is used as given and these settings are ignored.
  """

  use Gamend.Settings.Provider,
    app: :gamend_web,
    group: :webrtc,
    label: "WebRTC"

  setting(:stun_urls, :list,
    default: ["stun:stun.l.google.com:19302"],
    doc: "Comma-separated STUN server URLs. Empty uses none."
  )

  setting(:turn_urls, :list,
    default: [],
    doc:
      "Comma-separated TURN server URLs (turn:host:3478, turns:host:5349). Empty uses none. " <>
        "Only needed when the server itself is behind NAT or UDP is filtered."
  )

  # Complete-or-empty: one without the other warns in prod.
  setting(:turn_username, :string,
    required: :warn,
    with: [:turn_credential],
    doc: "Username for the TURN servers."
  )

  setting(:turn_credential, :string,
    secret: true,
    required: :warn,
    with: [:turn_username],
    doc: "Credential for the TURN servers."
  )

  @doc "The ICE servers for a new peer connection, in `ExWebRTC` shape."
  @spec ice_servers() :: [map()]
  def ice_servers do
    case Keyword.fetch(Application.get_env(:gamend_web, :webrtc, []), :ice_servers) do
      {:ok, servers} -> servers
      :error -> declared_servers()
    end
  end

  defp declared_servers do
    stun = Gamend.Settings.get(__MODULE__, :stun_urls) || []
    turn = Gamend.Settings.get(__MODULE__, :turn_urls) || []

    stun_servers = if stun == [], do: [], else: [%{urls: stun}]
    turn_servers = if turn == [], do: [], else: [turn_server(turn)]
    stun_servers ++ turn_servers
  end

  defp turn_server(urls) do
    %{
      urls: urls,
      username: Gamend.Settings.get(__MODULE__, :turn_username),
      credential: Gamend.Settings.get(__MODULE__, :turn_credential)
    }
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end
end
