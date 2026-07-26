defmodule GameServerWeb.Tls do
  @moduledoc """
  Native HTTPS, served directly by Bandit.

  Erlang's `:ssl` reloads certificate files from disk, so a renewed cert is
  picked up without a restart. The cert and key are declared as a pair: naming
  one without the other is a misconfiguration worth a warning, while naming
  neither simply means plain HTTP.

  Files that do not exist *yet* are a separate, expected case — certbot has to
  complete its first challenge before they appear — so that degrades to HTTP
  with a log line rather than tripping this check.
  """

  use GameServer.Settings.Provider,
    app: :game_server_web,
    group: :tls,
    label: "TLS & certificates"

  @pair [:certfile, :keyfile]

  setting(:certfile, :string,
    required: :warn,
    with: @pair,
    doc: "Path to fullchain.pem (certificate + CA chain)."
  )

  setting(:keyfile, :string,
    required: :warn,
    with: @pair,
    doc: "Path to privkey.pem."
  )

  setting(:port, :integer,
    default: 443,
    doc: "HTTPS listen port."
  )

  setting(:force, :boolean,
    doc: "Redirect HTTP to HTTPS and send HSTS. Defaults to on once certs are readable."
  )

  setting(:acme_webroot, :string,
    doc: "Webroot for Let's Encrypt HTTP-01 challenge files. Defaults to /var/www/acme."
  )
end
