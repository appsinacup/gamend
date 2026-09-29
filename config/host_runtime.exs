import Config

# config/runtime.exs is executed for all environments, including during
# releases. It runs after compilation and before the system starts, so it is
# used to load production configuration and secrets from environment
# variables or elsewhere. Do not define any compile-time configuration here.

# RELEASE_ROOT is exported by the release's own boot script and is unset under
# Mix.
release? = System.get_env("RELEASE_ROOT") != nil

# .env is already loaded by host_config.exs during config evaluation in dev;
# this is kept as a safety net for hosts whose compile-time config doesn't load
# it. (Code.require_file is a no-op when the file was already required.) A
# release reads the .env in the directory it is started from, the same file
# `mix phx.server` reads in dev, so a downloaded release is configured the way
# a checkout is. Real environment variables still win over its entries.
cond do
  config_env() == :dev ->
    Code.require_file("dotenv.exs", __DIR__)
    Gamend.Dotenv.load(Path.expand("../.env", __DIR__))

  release? ->
    Code.require_file("dotenv.exs", __DIR__)
    Gamend.Dotenv.load(Path.join(File.cwd!(), ".env"))

  true ->
    :ok
end

# Every runtime derivation — declared settings read from the environment plus
# the translation into the shapes Phoenix, Ecto, Bandit, Swoosh and Pigeon
# expect — ships with GamendWeb.HostRuntime so host repos share one
# implementation instead of forking this file. Host-specific runtime config
# goes below the loop.
# Under Mix this file sits in config/, so the host root is one level up. A
# release anchors the host-relative defaults (db/, data/) to the directory it
# is started from, where every other relative path (theme/, modules/plugins,
# priv/storage, the markdown content) already resolves: one folder then holds
# a deployment's data and its customisations, wherever the release itself was
# unpacked. The Docker image starts the release from its own root, so nothing
# moves there.
host_root = if release?, do: File.cwd!(), else: Path.expand("..", __DIR__)

for entry <- GamendWeb.HostRuntime.config(config_env(), host_root: host_root) do
  case entry do
    {app, opts} -> config app, opts
    {app, key, value} -> config app, key, value
  end
end

# host_config.exs points the theme at this checkout's theme/config.json by
# absolute path, resolved on the build machine and baked into the release.
# From a release, read it relative to the working directory like the rest of
# the content; GAMEND_CONTENT_THEME_CONFIG still overrides both.
if release? do
  config :gamend_core, Gamend.Theme.JSONConfig, default_config_path: "theme/config.json"
end
