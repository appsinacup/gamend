defmodule Gamend.Release.Metadata do
  @moduledoc """
  What a release declares, written into its image as it is built, so a host
  that runs the image from outside reads it without booting it. Gamend Cloud
  reads a server's after each build, where it asked the running server over
  `bin/<release> rpc`.

  The file is `gamend-metadata.json` in the release's directory, which is the
  image's working directory. Gamend's generated Dockerfile writes it as the
  last step of its release build (`mix gamend.gen.dockerfile`):

      bin/gamend_host eval 'Gamend.Release.Metadata.write()'

  It is JSON:

    * `format`: 1, raised only by a change a reader of an older one would
      misread;
    * `gamend_version`: core's version;
    * `settings`: `Gamend.Settings.declared/0`, with every plugin in the
      plugins directory loaded and none started
      (`Gamend.Hooks.PluginManager.load_declarations/0`).

  A host reads it with `decode/1`. Nothing in it is secret: a setting's
  declared default, never a value an environment sets.
  """

  alias Gamend.Hooks.PluginManager

  @file_name "gamend-metadata.json"
  @format 1

  @doc "The file's name, in the release's directory."
  @spec file_name() :: String.t()
  def file_name, do: @file_name

  @doc """
  The metadata of the release this node runs, as a map with string keys.
  Loads the plugins' code (none started), so it is for a node that only
  reads declarations: an `eval`, never a running server.
  """
  @spec build() :: map()
  def build do
    _ = Application.load(:gamend_core)
    _ = PluginManager.load_declarations()

    %{
      "format" => @format,
      "gamend_version" => to_string(Application.spec(:gamend_core, :vsn)),
      "settings" => Gamend.Settings.declared()
    }
  end

  @doc "Write `build/0` as JSON to `path`, the release's directory's `#{@file_name}` by default."
  @spec write(Path.t()) :: :ok
  def write(path \\ @file_name) do
    File.write!(path, Jason.encode_to_iodata!(build(), pretty: true))
    IO.puts("wrote #{path}")
  end

  @doc """
  Read a metadata file's content: core's version (nil when blank) and the
  declared settings, each a map with string keys as `Gamend.Settings.declared/0`
  describes them. `{:error, :invalid_metadata}` for anything else, a newer
  `format` included.
  """
  @spec decode(binary()) ::
          {:ok, %{version: String.t() | nil, settings: [map()]}} | {:error, :invalid_metadata}
  def decode(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, %{"format" => format, "settings" => settings} = metadata}
      when is_integer(format) and format <= @format and is_list(settings) ->
        {:ok, %{version: version(metadata["gamend_version"]), settings: settings}}

      _ ->
        {:error, :invalid_metadata}
    end
  end

  defp version(version) when is_binary(version) and version != "", do: version
  defp version(_version), do: nil
end
