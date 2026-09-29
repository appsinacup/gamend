defmodule Gamend.ContentSettings do
  @moduledoc """
  Where the server finds host-supplied content: the theme config, hook plugins,
  project static files, and the GeoIP database.
  """

  use Gamend.Settings.Provider,
    app: :gamend_core,
    group: :content,
    label: "Content & plugins"

  setting(:theme_config, :string,
    doc:
      "Path to the theme JSON. A single file serves every locale; its text is translated via the gettext `theme` domain."
  )

  setting(:plugins_dir, :string,
    default: "modules/plugins",
    doc: "Directory containing OTP hook plugins."
  )

  setting(:static_dirs, :list,
    default: ["static", "priv/static"],
    doc:
      "Directories of static files served ahead of the built-in ones (images/, game/, favicon.ico, robots.txt, theme.css), relative to the working directory and searched in order. Each is used when it exists."
  )

  setting(:geoip_db_path, :string,
    doc: "MaxMind mmdb file. Defaults to data/GeoLite2-Country.mmdb when present."
  )

  setting(:app_version, :string, doc: "Version reported in the OpenAPI spec and admin pages.")
end
