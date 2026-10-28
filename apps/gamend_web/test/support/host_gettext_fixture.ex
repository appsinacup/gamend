defmodule GamendWeb.HostGettextFixture do
  @moduledoc false
  # A host's backend over a one-file catalogue, for `GamendWeb.HostGettextTest`.
  use GamendWeb.HostGettext,
    otp_app: :gamend_web,
    priv: "test/support/fixtures/host_gettext"
end
