defmodule Mix.Tasks.Gamend.Settings.Guide do
  @shortdoc "Regenerates the Settings guide from the declared settings"

  @moduledoc """
  Writes the public Settings guide from `GameServer.Settings.all/0`.

      mix gamend.settings.guide          # write the guide
      mix gamend.settings.guide --check  # fail if it is out of date
      mix gamend.settings.guide -o PATH  # write somewhere else

  Sibling of `mix gamend.settings.env_example`, for the same reason: the
  guides used to hand-list environment variables, and every rename left them
  describing variables the server no longer read. A declared setting is now
  documented for readers of the docs site the moment it exists.

  **Only for hosts that have a docs site.** When `priv/docs/60-operations`
  does not exist the task says so and does nothing, including under `--check`
  — a game built on this server has its own docs, or none, and should not have
  a `priv/docs` tree conjured for it. Pass `-o PATH` to write somewhere else
  deliberately; an explicit path is always honoured.
  """

  use Mix.Task

  alias GameServer.Settings

  @default_path "priv/docs/60-operations/40-settings.md"

  @impl true
  def run(argv) do
    Mix.Task.run("app.config")

    {opts, _rest} =
      OptionParser.parse!(argv, strict: [check: :boolean, output: :string], aliases: [o: :output])

    path = Keyword.get(opts, :output, @default_path)
    explicit? = Keyword.has_key?(opts, :output)
    generated = render()

    cond do
      not explicit? and not File.dir?(Path.dirname(path)) ->
        # A host without a docs site has nowhere to put this. Skipping beats
        # conjuring a priv/docs tree it never asked for — game_server ships the
        # guide, a game built on it does not have to.
        Mix.shell().info("no #{Path.dirname(path)} directory - skipping the settings guide")

      Keyword.get(opts, :check, false) ->
        check(path, generated)

      true ->
        File.write!(path, generated)
        Mix.shell().info("wrote #{path} (#{length(Settings.all())} settings)")
    end
  end

  defp check(path, generated) do
    case File.read(path) do
      {:ok, ^generated} -> Mix.shell().info("#{path} is up to date")
      {:ok, _stale} -> Mix.raise("#{path} is out of date. Run: mix gamend.settings.guide")
      {:error, _} -> Mix.raise("#{path} does not exist. Run: mix gamend.settings.guide")
    end
  end

  defp render do
    groups =
      Settings.all()
      |> Enum.group_by(& &1.group)
      |> Enum.sort_by(fn {group, _} -> to_string(group) end)

    """
    ---
    icon: hero-adjustments-horizontal
    generated: by `mix gamend.settings.guide` - do not edit by hand; edit the
      declaration in the module that owns the setting
    ---

    # Settings

    Every setting the server has, with the environment variable that sets it.
    #{length(Settings.all())} settings across #{length(groups)} groups.

    A setting is declared in the module that owns it, so this page and
    `.env.example` are generated from the same source the server reads. The
    variable name is derived from the declaration rather than written by hand.

    Environment variables are one *input method*. A host can configure the
    ordinary Elixir way instead, and everything ends at `Application` config:

    ```elixir
    config :game_server_core, GameServer.Retention, chat_messages_days: 90
    ```

    To feed the variables below in, a host adds one line to
    `config/runtime.exs`:

    ```elixir
    for {app, module, opts} <- GameServer.Settings.from_env() do
      config app, module, opts
    end
    ```

    Live values, and where each one came from, are on the
    [admin settings page](/admin/settings).

    #{Enum.map_join(groups, "\n", &render_group/1)}
    """
  end

  defp render_group({_group, definitions}) do
    rows =
      definitions
      |> Enum.sort_by(& &1.env)
      |> Enum.map_join("\n", &render_row/1)

    """

    ## #{group_label(definitions)}

    | Variable | Type | Default | Notes |
    |---|---|---|---|
    #{rows}
    """
  end

  defp render_row(d) do
    notes =
      [d.doc, required_note(d), secret_note(d)]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join(" ")
      |> String.replace("|", "\\|")

    "| `#{d.env}` | #{d.type} | #{format_default(d)} | #{notes} |"
  end

  defp required_note(%{required: :prod}), do: "**Required in production.**"
  defp required_note(%{required: :warn}), do: "Warns when unset."
  defp required_note(_), do: nil

  defp secret_note(%{secret: true}), do: "Secret - never log or commit it."
  defp secret_note(_), do: nil

  defp format_default(%{secret: true, default: d}) when d not in [nil, ""], do: "_(set)_"
  defp format_default(%{default: nil}), do: "-"
  defp format_default(%{default: ""}), do: "-"

  defp format_default(%{default: default}) when is_list(default),
    do: "`#{Enum.join(default, ",")}`"

  defp format_default(%{default: default}), do: "`#{inspect(default)}`"

  # The label the declaration carries, so this page, the admin page and the
  # generated .env.example all name a group the same way.
  defp group_label([%{label: label} | _rest]), do: label
end
