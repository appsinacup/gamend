defmodule Gamend.Settings.EnvFile do
  @moduledoc """
  Every declared setting and plugin variable as a `.env` file, with the values
  this server runs on: what `/admin/settings` hands an admin to move a
  deployment or compare two.

  Secrets are written in the clear. The file exists to bring a server back, and
  whoever can download it is already an admin of this one.

  A setting on its default is commented out, so the active lines are what this
  server overrides and the rest keep following the defaults of later releases.
  `config/dotenv.exs` reads a file written here back byte for byte, and
  `Gamend.Settings.EnvFileTest` holds the two together.
  """

  alias Gamend.Hooks.Declarations
  alias Gamend.Settings

  @header """
  # Every setting of this server, with the values it was running on.
  # Holds its secrets in the clear: keep this file out of version control.
  # A commented line is a setting on its default.
  """

  @doc "The whole file."
  @spec render() :: String.t()
  def render do
    sections =
      for {group, label} <- Settings.groups() do
        section(label, Enum.map(Settings.group(group), &Settings.describe/1))
      end

    IO.iodata_to_binary([@header, sections, plugin_sections()])
  end

  defp section(label, rows), do: ["\n# ", label, "\n", Enum.map(rows, &entry/1)]

  # The variables the settings page lists beside the settings. A plugin reads
  # its own, so their values are only in the environment.
  defp plugin_sections do
    known = MapSet.new(Settings.all(), & &1.env)

    Declarations.env_vars()
    |> Enum.reject(&MapSet.member?(known, &1.name))
    |> Enum.group_by(& &1.plugin)
    |> Enum.map(fn {plugin, vars} ->
      section("Plugin: #{plugin}", Enum.map(vars, &plugin_row/1))
    end)
  end

  defp plugin_row(%{name: name, default: default}) do
    case System.get_env(name) do
      nil -> %{env: name, value: default, source: :default}
      value -> %{env: name, value: value, source: :config}
    end
  end

  defp entry(%{env: env, value: value, source: source}) do
    text = raw(value)

    cond do
      not carried?(text) -> ["# ", env, " holds text a .env file cannot carry: set it by hand\n"]
      source == :default or text == "" -> ["# ", env, "=", encode(text), "\n"]
      true -> [env, "=", encode(text), "\n"]
    end
  end

  # As its variable is written: `Gamend.Settings.cast/3` reads this back.
  defp raw(value) when is_binary(value), do: value
  defp raw(value) when is_list(value), do: Enum.map_join(value, ",", &raw/1)
  defp raw(value) when is_atom(value) or is_number(value), do: to_string(value)
  defp raw(value), do: inspect(value)

  # The loader strips every quote at either end of a value, and has no escape
  # for a backslash before a line break.
  defp carried?(text) do
    not (String.starts_with?(text, "\"") or String.ends_with?(text, "\"") or
           String.contains?(text, "\\\n"))
  end

  # Quoted only when it has to be: Docker's `--env-file` keeps the quotes.
  defp encode(text) do
    escaped = text |> String.replace("\\n", "\\\\n") |> String.replace("\n", "\\n")

    if escaped == text and text == String.trim(text),
      do: text,
      else: ["\"", escaped, "\""]
  end
end
