defmodule Mix.Tasks.Gamend.Settings.Guide do
  @shortdoc "Regenerates the Settings guide from the declared settings"

  @moduledoc """
  Writes the public Settings guide from `Gamend.Settings.all/0`.

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

  alias Gamend.Settings

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
        # conjuring a priv/docs tree it never asked for — gamend ships the
        # guide, a game built on it does not have to.
        Mix.shell().info("no #{Path.dirname(path)} directory - skipping the settings guide")

      Keyword.get(opts, :check, false) ->
        Gamend.Codegen.check!(path, generated, "gamend.settings.guide")

      true ->
        File.write!(path, generated)
        Mix.shell().info("wrote #{path} (#{length(Settings.all())} settings)")
    end
  end

  defp render do
    # By label, like the admin page (`Settings.groups/0`) — sorting by the
    # group atom filed "Public features" (`:features`) under D.
    groups =
      Settings.all()
      |> Enum.group_by(& &1.group)
      |> Enum.sort_by(fn {_group, definitions} -> group_label(definitions) end)

    """
    ---
    icon: hero-adjustments-horizontal-solid
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
    config :gamend_core, Gamend.Retention, chat_messages_days: 90
    ```

    To feed the variables below in, a host's `config/runtime.exs` runs one loop
    over `GamendWeb.HostRuntime.config/2`. It folds in
    `Gamend.Settings.from_env/0` and also derives the Repo, Endpoint, mailer and
    push configuration from these settings, so a loop over `from_env/0` alone
    boots a production server with no Repo or Endpoint configuration:

    ```elixir
    host_root = System.get_env("RELEASE_ROOT") || Path.expand("..", __DIR__)

    for entry <- GamendWeb.HostRuntime.config(config_env(), host_root: host_root) do
      case entry do
        {app, opts} -> config app, opts
        {app, key, value} -> config app, key, value
      end
    end
    ```

    Live values, and where each one came from, are on the
    [admin settings page](/admin/settings).

    ## Your own settings

    A game built on Gamend declares its own groups the same way core does. They
    are not on Gamend's own docs site: they appear on your admin settings page,
    in boot validation, in your `.env.example` (`mix gamend.settings.env_example`)
    and in this guide when you generate it in your repo
    (`mix gamend.settings.guide`).

    ```elixir
    defmodule MyGame.UGC do
      use Gamend.Settings.Provider,
        app: :my_game,
        group: :ugc,
        label: "User-generated content"

      setting :max_uploads, :integer, default: 10, doc: "Uploads a player may keep."
    end
    ```

    That declares `GAMEND_UGC_MAX_UPLOADS`, read with
    `Gamend.Settings.get(MyGame.UGC, :max_uploads)`.

    - `group:` and each key are lowercase snake_case atoms, since they become
      the variable name. The display name, spaces and all, goes in `label:`.
    - A variable nothing declares does nothing. Writing `GAMEND_UGC_*` lines in
      `.env` does not make a group.
    - Gamend reads providers from `:gamend_core`, `:gamend_web`, your host app
      (`config :gamend_web, host_static_app: :my_game`) and any app listed in
      `config :gamend_core, Gamend.Settings, apps: [...]`. A provider in any
      other app is never found: no admin row, no validation, and its variables
      are ignored.
    - A plugin declares its settings on its hook module, usually with its own
      `root: "MY_PLUGIN"`, and they register when the plugin loads.

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

  defp required_note(%{required: :prod} = d), do: "**Required in production#{gate_text(d)}.**"
  defp required_note(%{required: :warn} = d), do: "Warns if unset#{gate_text(d)}."
  defp required_note(_), do: nil

  # The gate a requirement waits on, as `Gamend.Settings.validate/1` applies it
  # and the admin settings page words it: `when:` ties it to another setting's
  # value, `with:` makes it apply only once a sibling is set. Named by env var,
  # since that is how this page names every setting.
  defp gate_text(d) do
    case Enum.reject([when_text(d.when), with_text(d)], &is_nil/1) do
      [] -> ""
      parts -> " " <> Enum.join(parts, " and ")
    end
  end

  defp when_text(nil), do: nil
  defp when_text({_path, _value} = condition), do: when_text([condition])

  defp when_text(conditions) when is_list(conditions) do
    "when " <>
      Enum.map_join(conditions, " and ", fn {[group, key], value} ->
        "`#{when_env(group, key)}` is `#{format_value(value)}`"
      end)
  end

  defp with_text(%{with: siblings, module: module, key: key}) do
    case Enum.reject(siblings, &(&1 == key)) do
      [] -> nil
      others -> "once " <> join_or(Enum.map(others, &"`#{module_env(module, &1)}`")) <> " is set"
    end
  end

  defp when_env(group, key) do
    case Enum.find(Settings.group(group), &(&1.key == key)) do
      nil -> "#{group}.#{key}"
      definition -> definition.env
    end
  end

  defp module_env(module, key) do
    case Enum.find(Settings.all(), &(&1.module == module and &1.key == key)) do
      nil -> to_string(key)
      definition -> definition.env
    end
  end

  defp format_value(value) when is_atom(value), do: to_string(value)
  defp format_value(value), do: inspect(value)

  defp join_or([one]), do: one

  defp join_or(items) do
    {init, [last]} = Enum.split(items, -1)
    Enum.join(init, ", ") <> " or " <> last
  end

  defp secret_note(%{secret: true}), do: "Secret - never log or commit it."
  defp secret_note(_), do: nil

  defp format_default(%{secret: true, default: d}) when d not in [nil, ""], do: "_(set)_"
  defp format_default(%{default: nil}), do: "-"
  defp format_default(%{default: ""}), do: "-"
  # An empty list would otherwise join to an empty code span.
  defp format_default(%{default: []}), do: "-"

  defp format_default(%{default: default}) when is_list(default),
    do: "`#{Enum.join(default, ",")}`"

  defp format_default(%{default: default}), do: "`#{inspect(default)}`"

  # The label the declaration carries, so this page, the admin page and the
  # generated .env.example all name a group the same way.
  defp group_label([%{label: label} | _rest]), do: label
end
