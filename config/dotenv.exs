# Shared .env loader, used both at compile time (host_config.exs, so .env can
# select compile-time settings like the database adapter) and at runtime
# (host_runtime.exs). Loaded via Code.require_file — requiring the same path
# twice is a no-op, so the module is defined once per VM.
defmodule Gamend.Dotenv do
  @moduledoc false

  # Parses KEY=VALUE lines — comments, "quoted values", multiline quoted
  # values, and \n and \\n escapes — and puts them into the System environment.
  # Real environment variables always win over .env entries.
  def load(env_path) do
    if File.exists?(env_path) do
      env_path
      |> File.read!()
      |> parse()
      |> Enum.each(fn {key, value} ->
        if is_nil(System.get_env(key)) do
          System.put_env(key, value)
        end
      end)
    end

    :ok
  end

  defp parse(contents) do
    contents
    |> String.split("\n")
    |> Enum.reduce({nil, []}, &parse_line/2)
    |> elem(1)
    |> Enum.reverse()
  end

  # Inside a multiline quoted value: accumulate until a line ends with a quote.
  defp parse_line(line, {{key, value_lines}, entries}) do
    trimmed = String.trim_trailing(line)

    if String.ends_with?(trimmed, "\"") do
      value =
        [String.trim_trailing(trimmed, "\"") | value_lines]
        |> Enum.reverse()
        |> Enum.join("\n")

      {nil, [{key, value} | entries]}
    else
      {{key, [line | value_lines]}, entries}
    end
  end

  defp parse_line(line, {nil, entries}) do
    if String.trim(line) == "" or String.starts_with?(String.trim_leading(line), "#") do
      {nil, entries}
    else
      case String.split(line, "=", parts: 2) do
        [key, value] -> parse_entry(String.trim(key), String.trim(value), entries)
        _ -> {nil, entries}
      end
    end
  end

  defp parse_entry("", _value, entries), do: {nil, entries}

  defp parse_entry(key, value, entries) do
    if String.starts_with?(value, "\"") and not String.ends_with?(value, "\"") do
      # Opening quote without a closing one — start of a multiline value.
      {{key, [String.trim_leading(value, "\"")]}, entries}
    else
      value =
        value
        |> String.trim_leading("\"")
        |> String.trim_trailing("\"")
        |> unescape()

      {nil, [{key, value} | entries]}
    end
  end

  # `\n` is a line break. `\\n` keeps a backslash and an n, which a JSON key
  # file's `private_key` needs: a real line break inside a JSON string is invalid.
  defp unescape(value) do
    String.replace(value, ["\\\\n", "\\n"], fn
      "\\n" -> "\n"
      "\\\\n" -> "\\n"
    end)
  end
end
