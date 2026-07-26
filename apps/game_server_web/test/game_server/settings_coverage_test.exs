defmodule GameServer.SettingsCoverageTest do
  @moduledoc """
  Exercises **every declared setting**, one generated test each, so a failure
  names the exact setting rather than "something in the config layer".

  `settings_test.exs` covers the machinery against a sample provider; this
  covers the 200-odd real declarations, which is where a typo actually lands:
  a default that does not match its declared type, a name that collides with
  another setting, or a value that cannot survive the trip from an environment
  variable back to `Settings.get/2`.

  What this does *not* prove is that the consuming code reads the value — that
  a smaller `max_lobby_users` really caps a lobby. Those live with the features
  they belong to.
  """

  use ExUnit.Case, async: false

  alias GameServer.Settings

  @definitions Settings.all()

  test "there is at least one declaration to check" do
    assert length(@definitions) > 200
  end

  describe "declaration integrity" do
    test "every environment variable name is unique" do
      duplicates =
        @definitions
        |> Enum.group_by(& &1.env)
        |> Enum.filter(fn {_env, defs} -> length(defs) > 1 end)
        |> Enum.map(fn {env, defs} ->
          {env, Enum.map(defs, &"#{inspect(&1.module)}.#{&1.key}")}
        end)

      assert duplicates == [],
             "two settings would read the same variable: #{inspect(duplicates)}"
    end

    test "every name derives from its group and key, without exception" do
      wrong =
        for definition <- @definitions,
            expected = expected_name(definition),
            definition.env != expected,
            do: {definition.env, expected}

      assert wrong == [], "names not following the convention: #{inspect(wrong)}"
    end

    test "the declaration offers no way to pin a name" do
      # `env:` and `external:` were removed so an exception cannot come back.
      assert_raise ArgumentError, ~r/unknown option\(s\) \[:env\]/, fn ->
        defmodule PinnedName do
          use GameServer.Settings.Provider, app: :game_server_core, group: :pinned
          setting(:thing, :string, env: "LEGACY_NAME")
        end
      end
    end

    test "every group has a display label" do
      for definition <- @definitions do
        assert is_binary(definition.label) and definition.label != "",
               "#{definition.group}.#{definition.key} has no label"
      end
    end
  end

  # One test per setting: the value an operator would set has to survive
  # casting and come back out of `Settings.get/2` unchanged.
  for definition <- @definitions do
    @definition definition

    test "#{definition.env} (#{inspect(definition.module)}.#{definition.key})" do
      assert_default_matches_type(@definition)
      assert_round_trips(@definition)
      assert_describable(@definition)
    end
  end

  defp assert_default_matches_type(%{default: nil}), do: :ok

  defp assert_default_matches_type(definition) do
    %{default: default, type: type} = definition

    ok? =
      case type do
        :string -> is_binary(default)
        :integer -> is_integer(default)
        :float -> is_float(default)
        :boolean -> is_boolean(default)
        :atom -> is_atom(default)
        :list -> is_list(default)
        :log_level -> default in [:debug, :info, :warning, :error, false]
      end

    assert ok?, "default #{inspect(default)} is not a #{type}"
  end

  defp assert_round_trips(definition) do
    {raw, expected} = sample(definition)
    previous = System.get_env(definition.env)
    System.put_env(definition.env, raw)

    try do
      resolved =
        Settings.from_env()
        |> Enum.find_value(fn
          {_app, module, opts} when module == definition.module ->
            Keyword.fetch(opts, definition.key)

          _ ->
            nil
        end)

      assert resolved == {:ok, expected},
             "#{definition.env}=#{raw} resolved to #{inspect(resolved)}, expected #{inspect(expected)}"

      # resolve/0 is what config/runtime.exs reads; it must agree.
      assert Settings.resolve()[{definition.module, definition.key}] == expected
    after
      if previous,
        do: System.put_env(definition.env, previous),
        else: System.delete_env(definition.env)
    end
  end

  defp assert_describable(definition) do
    described = Settings.describe(definition)

    assert described.source in [:config, :default]
    assert Map.has_key?(described, :value)
    assert is_boolean(described.satisfied)
  end

  # A value an operator could plausibly set, distinct from the default so the
  # assertion cannot pass by accident.
  defp sample(%{type: :string}), do: {"sample-value", "sample-value"}
  defp sample(%{type: :integer}), do: {"4242", 4242}
  defp sample(%{type: :float}), do: {"1.5", 1.5}
  defp sample(%{type: :atom}), do: {"sample", :sample}
  defp sample(%{type: :list}), do: {"alpha, beta", ["alpha", "beta"]}
  defp sample(%{type: :log_level}), do: {"warning", :warning}
  defp sample(%{type: :boolean, default: true}), do: {"false", false}
  defp sample(%{type: :boolean}), do: {"true", true}

  defp expected_name(%{group: group, key: key, module: module}) do
    root = if module |> Module.split() |> hd() == "PolyglotHook", do: "POLYGLOT", else: "GAMEND"
    Enum.map_join([root, to_string(group), to_string(key)], "_", &String.upcase/1)
  end
end
