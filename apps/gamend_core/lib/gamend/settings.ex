defmodule Gamend.Settings do
  @moduledoc """
  The declared configuration surface: every setting core, the host and its
  plugins expose, with its type, default, group, env var name and required
  level.

  Settings are declared with `Gamend.Settings.Provider` and read with
  `get/2`, which checks `Application.get_env(app, module)` and falls back to
  the compiled default. That means a host configures the ordinary Elixir way:

      config :gamend_core, Gamend.Retention, chat_messages_days: 90

  Environment variables are one *input method* into that, not a second source.
  `GamendWeb.HostRuntime.config/2` folds `from_env/0` in with the Repo,
  Endpoint and mailer derivations, so a host's runtime config loops over that
  and nothing else. Looping over `from_env/0` alone leaves prod with no Repo or
  Endpoint configuration — see the `GamendWeb.HostRuntime` moduledoc.

  A host that prefers a JSON file, or plain Elixir, writes its own equivalent.
  Every route ends at `Application` config, so no two sources compete.

  ## Discovery

  Providers are found by scanning the modules of `apps/0` for `__settings__/0`
  and cached in `:persistent_term`. Plugins load after config is resolved, so
  `Gamend.Hooks.PluginManager` registers theirs on load via `add_app/1`.
  """

  alias Gamend.Hooks.Declarations
  alias Gamend.Settings.Provider

  require Logger

  @falsy_short ~w(false 0 off none)
  @warn "warn"
  @log_levels ~w(debug info warning error)
  @falsy ~w(false 0 no n off none)
  @truthy ~w(true 1 yes y on)

  @pt_key {__MODULE__, :providers}

  @core_apps [:gamend_core, :gamend_web]

  @type definition :: %{
          key: atom(),
          module: module(),
          app: atom(),
          group: atom(),
          label: String.t(),
          section: String.t() | nil,
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
  Every declared setting, then every variable a loaded plugin declares that
  is not one (`Gamend.Hooks.Declarations.env_vars/0`), as plain data a JSON
  encoder takes: what a host that runs this server from outside, and cannot
  load its code, reads to offer them. Gamend's builder writes it beside a
  release it stages (`Gamend.Release.Metadata`), where Gamend Cloud's
  Settings tab reads it from the image. It is never a client's: no route or
  hook RPC answers it.

  Each is `%{env:, app:, group:, label:, type:, default:, doc:, secret:,
  values:, plugin:}`. `app`, `group` and `type` are strings; `default` is a
  string, a number, a boolean or nil, a list joined with commas as its
  variable is written, any other term `inspect/1`ed; `values` is the strings
  an `:atom` takes. A plugin's variable has `app` and `group` nil and
  `plugin` its plugin's name; a setting has `plugin` nil.
  """
  @spec declared() :: [map()]
  def declared do
    settings = all()
    known = MapSet.new(settings, & &1.env)

    Enum.map(settings, &declared_setting/1) ++
      for var <- Declarations.env_vars(),
          not MapSet.member?(known, var.name),
          do: declared_variable(var)
  end

  defp declared_setting(definition) do
    %{
      env: definition.env,
      app: Atom.to_string(definition.app),
      group: Atom.to_string(definition.group),
      label: definition.label,
      type: Atom.to_string(definition.type),
      default: plain(definition.default),
      doc: definition.doc,
      secret: definition.secret,
      values: Enum.map(Map.get(definition, :values) || [], &plain_item/1),
      plugin: nil
    }
  end

  defp declared_variable(var) do
    %{
      env: var.name,
      app: nil,
      group: nil,
      label: to_string(var.plugin),
      type: to_string(var.type),
      default: plain(var.default),
      doc: var.description,
      secret: Map.get(var, :secret, false),
      values: [],
      plugin: to_string(var.plugin)
    }
  end

  defp plain(value)
       when is_nil(value) or is_binary(value) or is_number(value) or is_boolean(value),
       do: value

  defp plain(value) when is_atom(value), do: Atom.to_string(value)
  defp plain(value) when is_list(value), do: Enum.map_join(value, ",", &plain_item/1)
  defp plain(value), do: inspect(value)

  defp plain_item(item) when is_binary(item), do: item
  defp plain_item(item) when is_atom(item) or is_number(item), do: to_string(item)
  defp plain_item(item), do: inspect(item)

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
        case cast(raw, definition.type, Map.get(definition, :values, [])) do
          {:ok, value} ->
            {:ok, value}

          :error ->
            # Never echo the value of a setting declared `secret: true`. Core
            # secrets are all `:string`, which never fails to cast, but a plugin
            # is free to declare a secret as `:integer` or `:boolean` — and one
            # typo would then print it in cleartext into the rotating log and
            # the admin log buffer.
            shown = if definition.secret, do: "[redacted]", else: inspect(raw)

            Logger.warning(
              "#{definition.env}=#{shown} is not a valid #{definition.type}; " <>
                "using #{inspect(definition.default)}"
            )

            :unset
        end
    end
  end

  @doc """
  Casts a raw string to a declared type. Returns `:error` when it does not
  parse, so the caller decides whether that is fatal.

  `values` is the declared `:values` of an `:atom` setting. Pass it whenever
  you have it — see `cast/3`.
  """
  @spec cast(String.t(), atom()) :: {:ok, term()} | :error
  def cast(raw, type), do: cast(raw, type, [])

  @doc """
  Casts a raw string against a declared type and, for `:atom`, its allowed
  `values`.

  With `values` the choice is matched against the declaration itself, so a
  legal value is accepted whether or not any other compiled code happens to
  name that atom. Without it there is nothing to match against and the cast
  falls back to `String.to_existing_atom/1`, which rejects exactly those atoms
  nothing else mentions — `GAMEND_PAYMENTS_ENVIRONMENT=sandbox` was rejected
  that way and silently became `:production`. Declare `:values` on every
  `:atom` setting; the fallback exists for plugins compiled before it did.
  """
  @spec cast(String.t(), atom(), [atom()]) :: {:ok, term()} | :error
  def cast(raw, :string, _values), do: {:ok, raw}

  # Downcased: every atom-valued setting is a lowercase choice (`s3`, `redis`,
  # `log`), and `STORAGE_ADAPTER=S3` should not silently miss.
  def cast(raw, :atom, [_ | _] = values) do
    normalized = raw |> String.trim() |> String.downcase()

    case Enum.find(values, &(Atom.to_string(&1) == normalized)) do
      nil -> :error
      value -> {:ok, value}
    end
  end

  def cast(raw, :atom, []) do
    {:ok, raw |> String.trim() |> String.downcase() |> String.to_existing_atom()}
  rescue
    ArgumentError -> :error
  end

  def cast(raw, :integer, _values) do
    case Integer.parse(String.trim(raw)) do
      {int, ""} -> {:ok, int}
      _ -> :error
    end
  end

  def cast(raw, :float, _values) do
    case Float.parse(String.trim(raw)) do
      {float, ""} -> {:ok, float}
      _ -> :error
    end
  end

  def cast(raw, :boolean, _values) do
    case raw |> String.trim() |> String.downcase() do
      truthy when truthy in @truthy -> {:ok, true}
      falsy when falsy in @falsy -> {:ok, false}
      _ -> :error
    end
  end

  def cast(raw, :log_level, _values) do
    case raw |> String.trim() |> String.downcase() do
      level when level in @log_levels -> {:ok, String.to_existing_atom(level)}
      @warn -> {:ok, :warning}
      off when off in @falsy_short -> {:ok, false}
      _ -> :error
    end
  end

  # Values arrive from a shell or a .env file, where `KEY=a,b # note` keeps the
  # comment as part of the value. Trimming it here costs one ignored entry
  # instead of a list that silently matches nothing.
  def cast(raw, :list, _values) do
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

  @doc """
  Apps scanned for providers.

  Core's two, the host application, and anything `add_app/1` registered.

  The host is derived rather than registered because the alternative is silence:
  a host that declares settings and is never scanned gets no boot validation, no
  row on the admin Settings page and nothing in `.env.example`, while `get/2`
  keeps answering with the compiled default — so its env vars do nothing and say
  nothing. Deriving it here rather than in the boot path also covers the mix
  tasks, which run `app.config` without starting the application and so never
  reach `GamendWeb.HostSupervision.init_runtime/1`; `mix gamend.settings.guide`
  and `mix gamend.settings.env_example` would otherwise document core's settings
  and quietly omit the host's.

  `:host_static_app` is the key a host already sets to name its own OTP app, and
  reading it is a lookup, not a dependency — core does not compile against
  `gamend_web`. It defaults to `:gamend_web`, which is scanned anyway, so an
  unconfigured deployment sees no change.
  """
  @spec apps() :: [atom()]
  def apps do
    extra = Application.get_env(:gamend_core, __MODULE__, []) |> Keyword.get(:apps, [])
    host = Application.get_env(:gamend_web, :host_static_app, :gamend_web)

    Enum.uniq(@core_apps ++ [host] ++ extra)
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
    config = Application.get_env(:gamend_core, __MODULE__, [])
    kept = config |> Keyword.get(:providers, []) |> List.delete(module)

    Application.put_env(:gamend_core, __MODULE__, Keyword.put(config, :providers, kept))
    reload()
  end

  defp register(kind, value) do
    config = Application.get_env(:gamend_core, __MODULE__, [])
    existing = Keyword.get(config, kind, [])

    # Registration order does not matter: `all/0` sorts by group and key.
    unless value in existing do
      Application.put_env(
        :gamend_core,
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
      Application.get_env(:gamend_core, __MODULE__, [])
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
