defmodule Gamend.JobsObanConfigTest do
  @moduledoc """
  Queue concurrency is written for Postgres. SQLite serializes every writer
  behind one database-wide lock, so the same numbers turn into contention and
  "database is locked" crashes (Oban.Stager is the usual casualty). The config
  has to scale itself down for the Lite engine and leave Postgres alone.
  """
  use ExUnit.Case, async: false

  alias Gamend.Jobs

  defp with_adapter(adapter, fun) do
    repo_config = Application.get_env(:gamend_core, Gamend.Repo)
    oban_config = Application.get_env(:gamend_core, Oban)

    Application.put_env(
      :gamend_core,
      Gamend.Repo,
      Keyword.put(repo_config, :adapter, adapter)
    )

    Application.put_env(
      :gamend_core,
      Oban,
      Keyword.merge(oban_config, queues: [default: 10, hooks: 20, mailers: 5])
    )

    try do
      fun.()
    after
      Application.put_env(:gamend_core, Gamend.Repo, repo_config)
      Application.put_env(:gamend_core, Oban, oban_config)
    end
  end

  test "sqlite caps queue concurrency and stages less often" do
    with_adapter(Ecto.Adapters.SQLite3, fn ->
      config = Jobs.oban_config()

      assert config[:engine] == Oban.Engines.Lite
      assert Enum.all?(config[:queues], fn {_name, limit} -> limit <= 2 end)
      assert config[:stage_interval] >= :timer.seconds(5)
    end)
  end

  test "queue sizes and the pruning window follow their settings" do
    Gamend.SettingsHelpers.put(:gamend_core, Jobs, :queue_hooks, 40)
    Gamend.SettingsHelpers.put(:gamend_core, Jobs, :prune_after_days, 2)

    on_exit(fn ->
      Gamend.SettingsHelpers.delete(:gamend_core, Jobs, :queue_hooks)
      Gamend.SettingsHelpers.delete(:gamend_core, Jobs, :prune_after_days)
    end)

    with_adapter(Ecto.Adapters.Postgres, fn ->
      config = Jobs.oban_config()

      assert config[:queues][:hooks] == 40
      assert config[:queues][:push] == Gamend.Settings.get(Gamend.Push, :queue_concurrency)

      assert {Oban.Plugins.Pruner, pruner} =
               Enum.find(config[:plugins], &match?({Oban.Plugins.Pruner, _}, &1))

      assert pruner[:max_age] == 2 * 86_400
    end)
  end

  test "postgres keeps the configured concurrency untouched" do
    with_adapter(Ecto.Adapters.Postgres, fn ->
      config = Jobs.oban_config()

      assert config[:engine] == Oban.Engines.Basic
      assert config[:queues][:default] == 10
      assert config[:queues][:hooks] == 20
      refute Keyword.has_key?(config, :stage_interval)
    end)
  end
end
