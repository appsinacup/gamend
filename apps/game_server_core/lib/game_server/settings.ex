defmodule GameServer.Settings do
  @moduledoc """
  The declared configuration surface: every setting core, the host and its
  plugins expose, with its type, default, group, env var name and required
  level.

  Settings are declared with `GameServer.Settings.Provider` and read with
  `get/2`, which checks `Application.get_env(app, module)` and falls back to
  the compiled default. That means a host configures the ordinary Elixir way:

      config :game_server_core, GameServer.Retention, chat_messages_days: 90

  Environment variables are one *input method* into that, not a second source.
  A host that wants them writes one line in `config/runtime.exs`:

      for {app, module, opts} <- GameServer.Settings.from_env() do
        config app, module, opts
      end

  A host that prefers a JSON file, or plain Elixir, writes its own equivalent.
  Every route ends at `Application` config, so no two sources compete.

  ## Discovery

  Providers are found by scanning the modules of `apps/0` for `__settings__/0`
  and cached in `:persistent_term`. Plugins load after config is resolved, so
  `GameServer.Hooks.PluginManager` registers theirs on load via `add_app/1`.
  """

  alias GameServer.Settings.Provider

  require Logger

  @pt_key {__MODULE__, :providers}

  @core_apps [:game_server_core, :game_server_web]

  @type definition :: %{
          key: atom(),
          module: module(),
          app: atom(),
          group: atom(),
          label: String.t(),
          type: atom(),
          default: term(),
          env: String.t(),
          doc: String.t(),
          secret: boolean(),
          external: boolean(),
          required: :prod | :warn | nil,
          when: {[atom()], term()} | nil,
          with: [atom()]
        }

  # ── Reading ─────────────────────────────────────────────────────────────

  @doc """
  The current value of a setting: the host's `Application` config if it set
  one, otherwise the compiled default.

  Raises for a key the module does not declare — an undeclared read is a bug,
  not a runtime condition.
  """
  @spec get(module(), atom()) :: term()
  def get(module, key) when is_atom(module) and is_atom(key) do
    definition = definition!(module, key)

    case Keyword.fetch(Application.get_env(definition.app, module, []), key) do
      {:ok, value} -> value
      :error -> definition.default
    end
  end

  @doc "Every declared setting, across every registered app."
  @spec all() :: [definition()]
  def all do
    providers()
    |> Enum.flat_map(& &1.__settings__())
    |> Enum.sort_by(&{&1.group, &1.key})
  end

  @doc "Declared settings for one group."
  @spec group(atom()) :: [definition()]
  def group(name) when is_atom(name), do: Enum.filter(all(), &(&1.group == name))

  @doc "Every group, as `{group, label}`, in display order."
  @spec groups() :: [{atom(), String.t()}]
  def groups do
    all()
    |> Enum.map(&{&1.group, &1.label})
    |> Enum.uniq()
    |> Enum.sort_by(&elem(&1, 1))
  end

  @doc """
  A setting's declaration, with its effective value and where that came from:
  `:config` when the host set one, `:default` otherwise.

  The admin viewer renders this; `:env` never appears as a source because env
  vars are resolved into `Application` config at boot rather than read live.
  """
  @spec describe(definition()) :: map()
  def describe(definition) do
    {value, source} =
      case Keyword.fetch(
             Application.get_env(definition.app, definition.module, []),
             definition.key
           ) do
        {:ok, value} -> {value, :config}
        :error -> {definition.default, :default}
      end

    definition
    |> Map.put(:value, value)
    |> Map.put(:source, source)
    |> Map.put(:satisfied, satisfied?(definition, value))
  end

  # ── Env input ───────────────────────────────────────────────────────────

  @doc """
  Reads every declared setting from the environment, as `{app, module, opts}`
  ready to splat into `config/2`.

  Only variables that are actually set contribute; the rest fall through to
  the compiled default. A value that does not parse as its declared type is
  skipped with a warning rather than taking the boot down.
  """
  @spec from_env() :: [{atom(), module(), keyword()}]
  def from_env do
    all()
    |> Enum.reduce(%{}, fn definition, acc ->
      case read_env(definition) do
        :unset ->
          acc

        {:ok, value} ->
          Map.update(
            acc,
            {definition.app, definition.module},
            [{definition.key, value}],
            &[{definition.key, value} | &1]
          )
      end
    end)
    |> Enum.map(fn {{app, module}, opts} -> {app, module, Enum.reverse(opts)} end)
  end

  @doc """
  Every setting's resolved value, keyed by `{module, key}`: the environment
  when it is set, the compiled default otherwise.

  For `config/runtime.exs`, which needs values *while* it is still building the
  configuration. `config/2` only applies after the whole file is evaluated, so
  `get/2` cannot see what `from_env/0` just contributed — this can.
  """
  @spec resolve() :: %{{module(), atom()} => term()}
  def resolve do
    Map.new(all(), fn definition ->
      value =
        case read_env(definition) do
          {:ok, value} -> value
          :unset -> definition.default
        end

      {{definition.module, definition.key}, value}
    end)
  end

  defp read_env(definition) do
    case System.get_env(definition.env) do
      nil ->
        :unset

      "" ->
        :unset

      raw ->
        case cast(raw, definition.type) do
          {:ok, value} ->
            {:ok, value}

          :error ->
            Logger.warning(
              "#{definition.env}=#{inspect(raw)} is not a valid #{definition.type}; " <>
                "using #{inspect(definition.default)}"
            )

            :unset
        end
    end
  end

  @doc """
  Casts a raw string to a declared type. Returns `:error` when it does not
  parse, so the caller decides whether that is fatal.
  """
  @spec cast(String.t(), atom()) :: {:ok, term()} | :error
  def cast(raw, :string), do: {:ok, raw}
  # Downcased: every atom-valued setting is a lowercase choice (`s3`, `redis`,
  # `log`), and `STORAGE_ADAPTER=S3` should not silently miss.
  def cast(raw, :atom), do: {:ok, raw |> String.trim() |> String.downcase() |> String.to_atom()}

  def cast(raw, :integer) do
    case Integer.parse(String.trim(raw)) do
      {int, ""} -> {:ok, int}
      _ -> :error
    end
  end

  def cast(raw, :float) do
    case Float.parse(String.trim(raw)) do
      {float, ""} -> {:ok, float}
      _ -> :error
    end
  end

  def cast(raw, :boolean) do
    case raw |> String.trim() |> String.downcase() do
      truthy when truthy in ~w(true 1 yes y on) -> {:ok, true}
      falsy when falsy in ~w(false 0 no n off none) -> {:ok, false}
      _ -> :error
    end
  end

  def cast(raw, :log_level) do
    case raw |> String.trim() |> String.downcase() do
      level when level in ~w(debug info warning error) -> {:ok, String.to_existing_atom(level)}
      "warn" -> {:ok, :warning}
      off when off in ~w(false 0 off none) -> {:ok, false}
      _ -> :error
    end
  end

  # Values arrive from a shell or a .env file, where `KEY=a,b # note` keeps the
  # comment as part of the value. Trimming it here costs one ignored entry
  # instead of a list that silently matches nothing.
  def cast(raw, :list) do
    entries =
      raw
      |> String.split(",", trim: true)
      |> Enum.map(&(&1 |> String.split("#", parts: 2) |> hd() |> String.trim()))
      |> Enum.reject(&(&1 == ""))

    {:ok, entries}
  end

  # ── Validation ──────────────────────────────────────────────────────────

  @doc """
  Checks every declared requirement against the resolved configuration.

  Returns `{failures, warnings}`, each a list of human-readable lines. Nothing
  is raised here — `validate!/1` decides what is fatal, so a caller that wants
  to render the state instead (the admin viewer) can.

  Severity by environment:

  | Level | `:prod` | `:dev` | `:test` |
  | --- | --- | --- | --- |
  | `required: :prod` | failure | warning | silent |
  | `required: :warn` | warning | silent | silent |

  The dev warning on a prod requirement is deliberate: it says the deployment
  will not boot in production while the developer is still at the keyboard.
  Test is silent because the suite boots hundreds of times.
  """
  @spec validate(atom()) :: {[String.t()], [String.t()]}
  def validate(env) when env in [:prod, :dev, :test] do
    all()
    |> Enum.filter(&unsatisfied?/1)
    |> Enum.reduce({[], []}, fn definition, {failures, warnings} ->
      case severity(definition.required, env) do
        :error -> {[message(definition) | failures], warnings}
        :warn -> {failures, [message(definition) | warnings]}
        :silent -> {failures, warnings}
      end
    end)
    |> then(fn {failures, warnings} -> {Enum.reverse(failures), Enum.reverse(warnings)} end)
  end

  @doc """
  Runs `validate/1`, logging warnings and raising on failures.

  Called once at boot. Returns `:ok` when nothing is fatal.
  """
  @spec validate!(atom()) :: :ok
  def validate!(env) do
    {failures, warnings} = validate(env)

    for warning <- warnings, do: Logger.warning("[settings] #{warning}")

    if failures != [] do
      raise """
      Missing required configuration:

      #{Enum.map_join(failures, "\n", &("  - " <> &1))}

      See the Settings page in /admin for every setting and its current value.
      """
    end

    :ok
  end

  defp severity(:prod, :prod), do: :error
  defp severity(:prod, :dev), do: :warn
  defp severity(:warn, :prod), do: :warn
  defp severity(_required, _env), do: :silent

  # A requirement only applies when its gate holds: `when:` ties it to another
  # setting's value, `with:` makes the group complete-or-empty, so a feature
  # nobody configured stays silent.
  defp unsatisfied?(%{required: nil}), do: false

  defp unsatisfied?(definition) do
    gate_open?(definition) and group_started?(definition) and
      not satisfied?(definition, get(definition.module, definition.key))
  end

  defp gate_open?(%{when: nil}), do: true

  defp gate_open?(%{when: conditions} = definition) when is_list(conditions) do
    Enum.all?(conditions, fn {path, expected} -> resolve_path(definition, path) == expected end)
  end

  defp gate_open?(%{when: {path, expected}} = definition) do
    resolve_path(definition, path) == expected
  end

  defp group_started?(%{with: []}), do: true

  defp group_started?(%{with: siblings} = definition) do
    Enum.any?(siblings, fn sibling ->
      satisfied?(definition, get(definition.module, sibling))
    end)
  end

  defp satisfied?(_definition, nil), do: false
  defp satisfied?(_definition, ""), do: false
  defp satisfied?(_definition, []), do: false
  defp satisfied?(_definition, _value), do: true

  # A `when:` path is `[:group, :key]`, so a gate can point at a setting in
  # another provider. An unresolvable path leaves the gate shut rather than
  # inventing a requirement.
  defp resolve_path(_definition, [group_name, key]) do
    case Enum.find(group(group_name), &(&1.key == key)) do
      nil -> nil
      target -> get(target.module, target.key)
    end
  end

  defp message(definition) do
    gate =
      case definition.when do
        {[group_name, key], expected} ->
          " (required when #{group_name}.#{key} is #{inspect(expected)})"

        _ ->
          ""
      end

    "#{definition.env} is not set#{gate}"
  end

  # ── Discovery ───────────────────────────────────────────────────────────

  @doc "Apps scanned for providers."
  @spec apps() :: [atom()]
  def apps do
    extra = Application.get_env(:game_server_core, __MODULE__, []) |> Keyword.get(:apps, [])
    Enum.uniq(@core_apps ++ extra)
  end

  @doc """
  Registers another app's providers — the host application, or a plugin loaded
  after boot. Clears the cache so the next read picks them up.
  """
  @spec add_app(atom()) :: :ok
  def add_app(app) when is_atom(app), do: register(:apps, app)

  @doc """
  Registers one provider module directly, for code that is not in a scanned
  app's module list — a plugin compiled at runtime, or a test.
  """
  @spec add_provider(module()) :: :ok
  def add_provider(module) when is_atom(module), do: register(:providers, module)

  @doc "Undoes `add_provider/1`."
  @spec remove_provider(module()) :: :ok
  def remove_provider(module) when is_atom(module) do
    config = Application.get_env(:game_server_core, __MODULE__, [])
    kept = config |> Keyword.get(:providers, []) |> List.delete(module)

    Application.put_env(:game_server_core, __MODULE__, Keyword.put(config, :providers, kept))
    reload()
  end

  defp register(kind, value) do
    config = Application.get_env(:game_server_core, __MODULE__, [])
    existing = Keyword.get(config, kind, [])

    # Registration order does not matter: `all/0` sorts by group and key.
    unless value in existing do
      Application.put_env(
        :game_server_core,
        __MODULE__,
        Keyword.put(config, kind, [value | existing])
      )
    end

    reload()
  end

  @doc "Drops the cached provider list. Call after loading code that declares settings."
  @spec reload() :: :ok
  def reload do
    :persistent_term.erase(@pt_key)
    :ok
  end

  @doc "Provider modules, discovered once and cached."
  @spec providers() :: [module()]
  def providers do
    case :persistent_term.get(@pt_key, nil) do
      nil ->
        discovered = discover()
        :persistent_term.put(@pt_key, discovered)
        discovered

      cached ->
        cached
    end
  end

  defp discover do
    scanned =
      for app <- apps(),
          module <- app_modules(app),
          Code.ensure_loaded?(module),
          function_exported?(module, :__settings__, 0),
          do: module

    explicit =
      Application.get_env(:game_server_core, __MODULE__, [])
      |> Keyword.get(:providers, [])
      |> Enum.filter(&(Code.ensure_loaded?(&1) and function_exported?(&1, :__settings__, 0)))

    Enum.uniq(scanned ++ explicit)
  end

  # `runtime.exs` runs before applications start, so the app may be loaded but
  # not started — load it rather than returning nothing.
  defp app_modules(app) do
    case :application.get_key(app, :modules) do
      {:ok, modules} ->
        modules

      :undefined ->
        case Application.load(app) do
          result when result in [:ok, {:error, {:already_loaded, app}}] ->
            case :application.get_key(app, :modules) do
              {:ok, modules} -> modules
              :undefined -> []
            end

          _ ->
            []
        end
    end
  end

  defp definition!(module, key) do
    unless function_exported?(module, :__settings__, 0) or Code.ensure_loaded?(module) do
      raise ArgumentError, "#{inspect(module)} does not declare settings"
    end

    case Enum.find(module.__settings__(), &(&1.key == key)) do
      nil ->
        raise ArgumentError,
              "#{inspect(module)} declares no setting #{inspect(key)}; " <>
                "declared: #{inspect(Enum.map(module.__settings__(), & &1.key))}"

      definition ->
        definition
    end
  end

  @doc """
  The env var name a group/key derives to. Exposed for docs and the
  `.env.example` generator.
  """
  @spec env_name(String.t(), atom(), atom()) :: String.t()
  defdelegate env_name(root, group, key), to: Provider, as: :derive_env
end
