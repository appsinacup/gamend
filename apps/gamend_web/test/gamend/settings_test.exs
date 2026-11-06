defmodule Gamend.SettingsTest do
  use ExUnit.Case, async: false

  alias Gamend.Settings

  defmodule Sample do
    use Gamend.Settings.Provider,
      app: :gamend_core,
      group: :sample,
      label: "Sample"

    setting(:chat_days, :integer, default: 0, doc: "Days of chat kept.")
    setting(:adapter, :atom, default: :local)
    setting(:api_token, :string, secret: true)

    setting(:bucket, :string, required: :prod, when: {[:sample, :adapter], :s3})

    setting(:key_id, :string, required: :warn, with: [:team_id])
    setting(:team_id, :string, required: :warn, with: [:key_id])
  end

  setup do
    Settings.add_provider(Sample)

    on_exit(fn ->
      Application.delete_env(:gamend_core, Sample)
      Settings.remove_provider(Sample)
    end)

    :ok
  end

  defp put(key, value) do
    config = Application.get_env(:gamend_core, Sample, [])
    Application.put_env(:gamend_core, Sample, Keyword.put(config, key, value))
  end

  describe "apps/0" do
    # A host that declares settings and is never scanned fails silently:
    # get/2 keeps answering with the compiled default, so its env vars do
    # nothing and say nothing. The host is derived here rather than registered
    # at boot so the mix tasks see it too — they run app.config without
    # starting the application, and would otherwise generate .env.example and
    # the settings guide with core's settings and none of the host's.
    setup do
      original = Application.get_env(:gamend_web, :host_static_app)

      on_exit(fn ->
        if original do
          Application.put_env(:gamend_web, :host_static_app, original)
        else
          Application.delete_env(:gamend_web, :host_static_app)
        end
      end)

      :ok
    end

    test "includes core's own apps" do
      assert :gamend_core in Settings.apps()
      assert :gamend_web in Settings.apps()
    end

    test "includes the host app named by :host_static_app" do
      Application.put_env(:gamend_web, :host_static_app, :my_game)

      assert :my_game in Settings.apps()
    end

    test "an unconfigured host adds nothing" do
      Application.delete_env(:gamend_web, :host_static_app)

      assert Enum.sort(Settings.apps()) == Enum.sort(Enum.uniq(Settings.apps()))
      assert :gamend_web in Settings.apps()
    end

    test "never lists an app twice" do
      Application.put_env(:gamend_web, :host_static_app, :gamend_core)

      apps = Settings.apps()

      assert Enum.count(apps, &(&1 == :gamend_core)) == 1
    end
  end

  describe "env name derivation" do
    test "derives <ROOT>_<GROUP>_<KEY>" do
      definition = definition(:chat_days)
      assert definition.env == "GAMEND_SAMPLE_CHAT_DAYS"
    end

    test "a name cannot be pinned — derivation is the only path" do
      assert_raise ArgumentError, ~r/unknown option\(s\) \[:env\]/, fn ->
        defmodule Pinned do
          use Gamend.Settings.Provider, app: :gamend_core, group: :pinned
          setting(:thing, :string, env: "LEGACY")
        end
      end
    end
  end

  describe "get/2" do
    test "falls back to the compiled default" do
      assert Settings.get(Sample, :chat_days) == 0
    end

    test "the host's Application config wins" do
      put(:chat_days, 90)
      assert Settings.get(Sample, :chat_days) == 90
    end

    test "raises for an undeclared key" do
      assert_raise ArgumentError, ~r/declares no setting :nope/, fn ->
        Settings.get(Sample, :nope)
      end
    end
  end

  describe "cast/2" do
    test "integers, floats and booleans" do
      assert Settings.cast("42", :integer) == {:ok, 42}
      assert Settings.cast(" 42 ", :integer) == {:ok, 42}
      assert Settings.cast("4.5", :float) == {:ok, 4.5}
      assert Settings.cast("nope", :integer) == :error

      for truthy <- ~w(true 1 yes y on TRUE),
          do: assert(Settings.cast(truthy, :boolean) == {:ok, true})

      for falsy <- ~w(false 0 no n off none),
          do: assert(Settings.cast(falsy, :boolean) == {:ok, false})

      assert Settings.cast("maybe", :boolean) == :error
    end

    test "log levels, including the off forms" do
      assert Settings.cast("warn", :log_level) == {:ok, :warning}
      assert Settings.cast("error", :log_level) == {:ok, :error}
      assert Settings.cast("off", :log_level) == {:ok, false}
      assert Settings.cast("chatty", :log_level) == :error
    end

    test "lists split on commas and drop trailing shell comments" do
      assert Settings.cast("a, b ,c", :list) == {:ok, ~w(a b c)}
      assert Settings.cast("cargo # a note", :list) == {:ok, ["cargo"]}
      assert Settings.cast("", :list) == {:ok, []}
    end
  end

  describe "cast/3 for :atom with declared values" do
    # The regression this guards: with no declared values the cast falls back
    # to `String.to_existing_atom/1`, so a legal choice is rejected unless some
    # unrelated module happens to name that atom. `:sandbox` was named nowhere
    # outside the test suite, so `GAMEND_PAYMENTS_ENVIRONMENT=sandbox` cast as
    # :error and silently fell back to the default — `:production`.
    test "accepts a declared value whose atom nothing else mentions" do
      values = [:production, :zzz_never_mentioned_anywhere_else]

      assert Settings.cast("zzz_never_mentioned_anywhere_else", :atom, values) ==
               {:ok, :zzz_never_mentioned_anywhere_else}
    end

    test "matches case-insensitively and trims" do
      assert Settings.cast("  SandBox ", :atom, [:production, :sandbox]) == {:ok, :sandbox}
    end

    test "rejects a value outside the declared set" do
      assert Settings.cast("sandbocks", :atom, [:production, :sandbox]) == :error
    end

    test "without declared values, falls back to to_existing_atom" do
      assert Settings.cast("production", :atom, []) == {:ok, :production}
      assert Settings.cast("production", :atom) == {:ok, :production}
    end
  end

  describe "the :values declaration" do
    test "every documented choice of every :atom setting actually casts" do
      # Each of these was documented in its own `doc:` string and in
      # .env.example, and three of them could not be set at all.
      for {module, key, choices} <- [
            {Gamend.Payments.Settings, :environment, ~w(production sandbox)},
            {Gamend.Push, :apns_env, ~w(production sandbox)},
            {Gamend.Push, :adapter, ~w(auto log)},
            {Gamend.Mail, :smtp_tls, ~w(never if_available always)},
            {Gamend.Storage, :adapter, ~w(local s3)},
            {Gamend.Database, :adapter, ~w(sqlite postgres)},
            {Gamend.Database, :sqlite_synchronous, ~w(off normal full extra)},
            {Gamend.Database, :postgres_synchronous_commit,
             ~w(on off local remote_write remote_apply)},
            {Gamend.Cache.Settings, :mode, ~w(single multi)},
            {Gamend.Cache.Settings, :l2, ~w(redis partitioned)},
            {GamendWeb.RateLimit, :backend, ~w(ets redis)}
          ],
          choice <- choices do
        definition = Enum.find(module.__settings__(), &(&1.key == key))

        assert definition, "#{inspect(module)} declares no setting #{inspect(key)}"

        assert definition.values != [],
               "#{inspect(module)}.#{key} is an :atom setting without :values"

        assert {:ok, _} = Settings.cast(choice, :atom, definition.values),
               "#{definition.env}=#{choice} is documented but does not cast"
      end
    end

    test "rejects a default outside the declared values" do
      assert_raise ArgumentError, ~r/not in :values/, fn ->
        defmodule BadDefault do
          use Gamend.Settings.Provider, app: :gamend_core, group: :baddefault
          setting(:mode, :atom, values: [:a, :b], default: :c)
        end
      end
    end

    test "rejects :values on a non-atom setting" do
      assert_raise ArgumentError, ~r/applies to :atom only/, fn ->
        defmodule BadType do
          use Gamend.Settings.Provider, app: :gamend_core, group: :badtype
          setting(:mode, :string, values: [:a, :b])
        end
      end
    end
  end

  describe "from_env/0" do
    test "only set variables contribute, cast to their declared type" do
      System.put_env("GAMEND_SAMPLE_CHAT_DAYS", "30")
      on_exit(fn -> System.delete_env("GAMEND_SAMPLE_CHAT_DAYS") end)

      opts = sample_opts(Settings.from_env())

      assert opts[:chat_days] == 30
      refute Keyword.has_key?(opts, :adapter)
    end

    test "an unparseable value is skipped rather than fatal" do
      System.put_env("GAMEND_SAMPLE_CHAT_DAYS", "soon")
      on_exit(fn -> System.delete_env("GAMEND_SAMPLE_CHAT_DAYS") end)

      opts = sample_opts(Settings.from_env())

      refute Keyword.has_key?(opts, :chat_days)
    end
  end

  describe "validate/1 severity" do
    test "a :prod requirement fails in prod, warns in dev, is silent in test" do
      put(:adapter, :s3)

      assert {[failure], []} = sample_validate(:prod)
      assert failure =~ "GAMEND_SAMPLE_BUCKET"
      assert failure =~ "sample.adapter"

      assert {[], [warning]} = sample_validate(:dev)
      assert warning =~ "GAMEND_SAMPLE_BUCKET"

      assert {[], []} = sample_validate(:test)
    end

    test "a :warn requirement warns in prod and is silent in dev" do
      put(:key_id, "abc")

      assert {[], [warning]} = sample_validate(:prod)
      assert warning =~ "GAMEND_SAMPLE_TEAM_ID"

      assert {[], []} = sample_validate(:dev)
    end
  end

  describe "validate/1 gates" do
    test "a when: gate that does not hold raises no requirement" do
      assert {[], []} = sample_validate(:prod)
    end

    test "a with: group is silent when every member is unset" do
      refute Enum.any?(elem(sample_validate(:prod), 1), &(&1 =~ "SAMPLE_KEY_ID"))
      refute Enum.any?(elem(sample_validate(:prod), 1), &(&1 =~ "SAMPLE_TEAM_ID"))
    end

    test "a with: group is satisfied when every member is set" do
      put(:key_id, "abc")
      put(:team_id, "def")

      assert {[], []} = sample_validate(:prod)
    end
  end

  describe "validate!/1" do
    test "raises listing every failure" do
      put(:adapter, :s3)

      assert_raise RuntimeError, ~r/Missing required configuration.*GAMEND_SAMPLE_BUCKET/s, fn ->
        Settings.validate!(:prod)
      end
    end

    test "returns :ok when nothing is fatal" do
      assert Settings.validate!(:prod) == :ok
    end
  end

  describe "describe/1" do
    test "reports the value and where it came from" do
      assert %{value: 0, source: :default} = Settings.describe(definition(:chat_days))

      put(:chat_days, 7)
      assert %{value: 7, source: :config} = Settings.describe(definition(:chat_days))
    end
  end

  describe "declaration errors" do
    test "an unknown type is a compile error" do
      assert_raise ArgumentError, ~r/unknown type :wat/, fn ->
        defmodule BadType do
          use Gamend.Settings.Provider, app: :gamend_core, group: :bad
          setting(:thing, :wat)
        end
      end
    end

    test "a with: naming an undeclared sibling is a compile error" do
      assert_raise ArgumentError, ~r/lists :ghost in :with/, fn ->
        defmodule BadWith do
          use Gamend.Settings.Provider, app: :gamend_core, group: :bad
          setting(:thing, :string, with: [:ghost])
        end
      end
    end

    test "a group that is not a snake_case atom is a compile error" do
      assert_raise ArgumentError, ~r/group :"user-generated content" is not a lowercase/, fn ->
        defmodule BadGroup do
          use Gamend.Settings.Provider,
            app: :gamend_core,
            group: :"user-generated content",
            label: "User-generated content"

          setting(:thing, :string)
        end
      end

      assert_raise ArgumentError, ~r/group "ugc" is not a lowercase/, fn ->
        defmodule StringGroup do
          use Gamend.Settings.Provider, app: :gamend_core, group: "ugc"
          setting(:thing, :string)
        end
      end
    end

    test "a key that is not a snake_case atom is a compile error" do
      assert_raise ArgumentError, ~r/setting :MaxUploads is not a lowercase/, fn ->
        defmodule BadKey do
          use Gamend.Settings.Provider, app: :gamend_core, group: :bad
          setting(:MaxUploads, :integer)
        end
      end
    end

    test "a root a shell cannot set is a compile error" do
      assert_raise ArgumentError, ~r/root "MY-GAME" must be letters/, fn ->
        defmodule BadRoot do
          use Gamend.Settings.Provider, app: :gamend_core, group: :bad, root: "MY-GAME"
          setting(:thing, :string)
        end
      end
    end

    test "a free-text label is fine" do
      defmodule LabelledGroup do
        use Gamend.Settings.Provider,
          app: :gamend_core,
          group: :ugc,
          label: "User-generated content"

        setting(:max_uploads, :integer, default: 10)
      end

      assert [%{env: "GAMEND_UGC_MAX_UPLOADS", label: "User-generated content"}] =
               LabelledGroup.__settings__()
    end

    test "a duplicate key is a compile error" do
      assert_raise ArgumentError, ~r/duplicate setting\(s\) \[:thing\]/, fn ->
        defmodule BadDupe do
          use Gamend.Settings.Provider, app: :gamend_core, group: :bad
          setting(:thing, :string)
          setting(:thing, :integer)
        end
      end
    end
  end

  describe "the real Storage providers" do
    setup do
      previous = Application.get_env(:gamend_core, Gamend.Storage)

      on_exit(fn ->
        if previous,
          do: Application.put_env(:gamend_core, Gamend.Storage, previous),
          else: Application.delete_env(:gamend_core, Gamend.Storage)
      end)

      :ok
    end

    test "on local disk, S3 credentials are not required" do
      Application.put_env(:gamend_core, Gamend.Storage, adapter: :local)

      {failures, _warnings} = Settings.validate(:prod)
      refute Enum.any?(failures, &(&1 =~ "GAMEND_STORAGE_"))
      assert Gamend.Storage.adapter() == Gamend.Storage.Local
    end

    test "selecting s3 without credentials fails the boot in prod" do
      Application.put_env(:gamend_core, Gamend.Storage, adapter: :s3)

      {failures, _warnings} = Settings.validate(:prod)

      assert Enum.any?(failures, &(&1 =~ "GAMEND_STORAGE_BUCKET"))
      assert Enum.any?(failures, &(&1 =~ "GAMEND_STORAGE_ACCESS_KEY_ID"))
      assert Enum.any?(failures, &(&1 =~ "GAMEND_STORAGE_SECRET_ACCESS_KEY"))
      assert Enum.all?(failures, &(&1 =~ ~s(storage.adapter is :s3)))
    end

    test "the same misconfiguration only warns in dev, so local work is never blocked" do
      Application.put_env(:gamend_core, Gamend.Storage, adapter: :s3)

      {_failures, warnings} = Settings.validate(:dev)
      assert Enum.any?(warnings, &(&1 =~ "GAMEND_STORAGE_BUCKET"))
    end

    test "one public URL serves whichever backend is behind it" do
      urls = Enum.filter(Settings.all(), &(&1.key == :public_url and &1.group == :storage))

      assert [%{module: Gamend.Storage, env: "GAMEND_STORAGE_PUBLIC_URL"}] = urls
    end
  end

  describe "the real Retention provider" do
    test "declares its keys with the current env names" do
      chat = Enum.find(Gamend.Retention.__settings__(), &(&1.key == :chat_messages_days))

      assert chat.env == "GAMEND_RETENTION_CHAT_MESSAGES_DAYS"
      assert chat.default == 0
      assert chat.group == :retention
    end

    test "reads through Settings with its documented defaults" do
      assert Settings.get(Gamend.Retention, :push_tokens_days) == 270
      assert Settings.get(Gamend.Retention, :results_days) == 0
    end
  end

  defp definition(key), do: Enum.find(Sample.__settings__(), &(&1.key == key))

  # Real providers contribute warnings of their own, so every assertion here
  # looks only at the lines this test's provider produced.
  defp sample_validate(env) do
    {failures, warnings} = Settings.validate(env)
    {Enum.filter(failures, &mine?/1), Enum.filter(warnings, &mine?/1)}
  end

  defp mine?(line), do: String.contains?(line, "GAMEND_SAMPLE_")

  defp sample_opts(from_env) do
    Enum.find_value(from_env, [], fn
      {_app, Sample, opts} -> opts
      _ -> nil
    end)
  end
end
