defmodule GameServer.Mail do
  @moduledoc """
  Outbound email transport.

  With no password set, `GameServer.Mailer` uses Swoosh's local adapter and
  mail lands in the in-browser mailbox at `/dev/mailbox` — the whole flow works
  with zero credentials. Setting a password means you intended to send real
  mail, so the relay and username are expected alongside it.
  """

  use GameServer.Settings.Provider,
    app: :game_server_core,
    group: :mail,
    label: "Email"

  @credentials [:smtp_password, :smtp_relay, :smtp_username]

  setting(:smtp_password, :string,
    secret: true,
    required: :warn,
    with: @credentials,
    doc: "SMTP password, or the provider's API key."
  )

  setting(:smtp_relay, :string,
    required: :warn,
    with: @credentials,
    doc: "SMTP host, e.g. smtp.resend.com."
  )

  setting(:smtp_username, :string,
    required: :warn,
    with: @credentials
  )

  setting(:smtp_port, :integer, default: 465)
  setting(:smtp_ssl, :boolean, default: true)

  setting(:smtp_tls, :atom,
    default: :never,
    doc: "STARTTLS policy: never | if_available | always."
  )

  setting(:smtp_sni, :string, doc: "TLS server name indication. Defaults to the relay host.")

  # Providers reject or spam-file mail from an unverified sender domain, so
  # these matter more than they look.
  setting(:smtp_from_name, :string, default: "Game Server")
  setting(:smtp_from_email, :string)
end
