defmodule GameServer.SettingsTest do
  use ExUnit.Case, async: false

  alias GameServer.Settings

  defmodule Sample do
    use GameServer.Settings.Provider,
      app: :game_server_core,
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
      Application.delete_env(:game_server_core, Sample)
      Settings.remove_provider(Sample)
    end)

    :ok
  end

  defp put(key, value) do
    config = Application.get_env(:game_server_core, Sample, [])
    Application.put_env(:game_server_core, Sample, Keyword.put(config, key, value))
  end

  describe "env name derivation" do
    test "derives <ROOT>_<GROUP>_<KEY>" do
      definition = definition(:chat_days)
      assert definition.env == "GAMEND_SAMPLE_CHAT_DAYS"
    end

    test "a name cannot be pinned — derivation is the only path" do
      assert_raise ArgumentError, ~r/unknown option\(s\) \[:env\]/, fn ->
        defmodule Pinned do
          use GameServer.Settings.Provider, app: :game_server_core, group: :pinned
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
          use GameServer.Settings.Provider, app: :game_server_core, group: :bad
          setting(:thing, :wat)
        end
      end
    end

    test "a with: naming an undeclared sibling is a compile error" do
      assert_raise ArgumentError, ~r/lists :ghost in :with/, fn ->
        defmodule BadWith do
          use GameServer.Settings.Provider, app: :game_server_core, group: :bad
          setting(:thing, :string, with: [:ghost])
        end
      end
    end

    test "a duplicate key is a compile error" do
      assert_raise ArgumentError, ~r/duplicate setting\(s\) \[:thing\]/, fn ->
        defmodule BadDupe do
          use GameServer.Settings.Provider, app: :game_server_core, group: :bad
          setting(:thing, :string)
          setting(:thing, :integer)
        end
      end
    end
  end

  describe "the real Storage providers" do
    setup do
      previous = Application.get_env(:game_server_core, GameServer.Storage)

      on_exit(fn ->
        if previous,
          do: Application.put_env(:game_server_core, GameServer.Storage, previous),
          else: Application.delete_env(:game_server_core, GameServer.Storage)
      end)

      :ok
    end

    test "on local disk, S3 credentials are not required" do
      Application.put_env(:game_server_core, GameServer.Storage, adapter: :local)

      {failures, _warnings} = Settings.validate(:prod)
      refute Enum.any?(failures, &(&1 =~ "GAMEND_STORAGE_"))
      assert GameServer.Storage.adapter() == GameServer.Storage.Local
    end

    test "selecting s3 without credentials fails the boot in prod" do
      Application.put_env(:game_server_core, GameServer.Storage, adapter: :s3)

      {failures, _warnings} = Settings.validate(:prod)

      assert Enum.any?(failures, &(&1 =~ "GAMEND_STORAGE_BUCKET"))
      assert Enum.any?(failures, &(&1 =~ "GAMEND_STORAGE_ACCESS_KEY_ID"))
      assert Enum.any?(failures, &(&1 =~ "GAMEND_STORAGE_SECRET_ACCESS_KEY"))
      assert Enum.all?(failures, &(&1 =~ ~s(storage.adapter is :s3)))
    end

    test "the same misconfiguration only warns in dev, so local work is never blocked" do
      Application.put_env(:game_server_core, GameServer.Storage, adapter: :s3)

      {_failures, warnings} = Settings.validate(:dev)
      assert Enum.any?(warnings, &(&1 =~ "GAMEND_STORAGE_BUCKET"))
    end

    test "one public URL serves whichever backend is behind it" do
      urls = Enum.filter(Settings.all(), &(&1.key == :public_url and &1.group == :storage))

      assert [%{module: GameServer.Storage, env: "GAMEND_STORAGE_PUBLIC_URL"}] = urls
    end
  end

  describe "the real Retention provider" do
    test "declares its keys with the current env names" do
      chat = Enum.find(GameServer.Retention.__settings__(), &(&1.key == :chat_messages_days))

      assert chat.env == "GAMEND_RETENTION_CHAT_MESSAGES_DAYS"
      assert chat.default == 0
      assert chat.group == :retention
    end

    test "reads through Settings with its documented defaults" do
      assert Settings.get(GameServer.Retention, :push_tokens_days) == 270
      assert Settings.get(GameServer.Retention, :lobby_snapshots_days) == 30
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
