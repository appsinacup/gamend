# The server's deployment environment is the host's `:gamend_web` key, and a
# few core readers — the Google RTDN webhook's fail-closed check among them —
# default it to `:prod` when unset. The web app sets it from `config_env()`;
# the core suite runs without the web app, so it says `:test` itself. Put here,
# not in config/test.exs: Mix warns about config for an app it cannot find.
Application.put_env(:gamend_web, :environment, :test)

Gamend.TestSupport.Runtime.start_suite()
