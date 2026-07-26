defmodule GameServerWeb.FileLogHandlerTest do
  # async: false — installs a global :logger handler and sets env vars.
  use ExUnit.Case, async: false

  require Logger

  alias GameServer.Settings
  alias GameServerWeb.FileLogHandler
  alias GameServerWeb.Observability

  @handler_id :file_log

  setup do
    previous = Application.get_env(:game_server_web, Observability)
    dir = Path.join(System.tmp_dir!(), "file_log_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    on_exit(fn ->
      :logger.remove_handler(@handler_id)
      File.rm_rf(dir)

      if previous,
        do: Application.put_env(:game_server_web, Observability, previous),
        else: Application.delete_env(:game_server_web, Observability)

      for env <-
            ~w(GAMEND_OBSERVABILITY_LOG_FILE_PATH GAMEND_OBSERVABILITY_LOG_FILE_LEVEL GAMEND_OBSERVABILITY_LOG_FILE_MAX_BYTES GAMEND_OBSERVABILITY_LOG_FILE_MAX_FILES) do
        System.delete_env(env)
      end
    end)

    Application.delete_env(:game_server_web, Observability)
    :logger.remove_handler(@handler_id)

    %{dir: dir, path: Path.join(dir, "test.log")}
  end

  # What a host's runtime.exs does with from_env/0, for the Observability group.
  defp apply_env do
    for {app, Observability, opts} <- Settings.from_env() do
      Application.put_env(app, Observability, Keyword.merge(config(), opts))
    end
  end

  defp config, do: Application.get_env(:game_server_web, Observability, [])

  defp put(key, value) do
    Application.put_env(:game_server_web, Observability, Keyword.put(config(), key, value))
  end

  defp handler_config do
    {:ok, %{config: config}} = :logger.get_handler_config(@handler_id)
    config
  end

  defp installed? do
    match?({:ok, _}, :logger.get_handler_config(@handler_id))
  end

  describe "installation" do
    test "does nothing when no path is configured" do
      assert FileLogHandler.install() == :ok
      refute installed?()
    end

    test "installs from app config" do
      put(:log_file_path, "/tmp/from_app_config.log")

      FileLogHandler.install()

      assert installed?()
      assert handler_config().file == ~c"/tmp/from_app_config.log"
    end

    test "installs from GAMEND_OBSERVABILITY_LOG_FILE_PATH once a host applies from_env/0", %{
      path: path
    } do
      System.put_env("GAMEND_OBSERVABILITY_LOG_FILE_PATH", path)
      apply_env()

      FileLogHandler.install()

      assert installed?()
      assert handler_config().file == String.to_charlist(path)
    end

    test "app config wins: from_env/0 never overwrites what the host set", %{path: path} do
      put(:log_file_path, path)
      System.put_env("GAMEND_OBSERVABILITY_LOG_FILE_PATH", "/tmp/should_be_ignored.log")

      FileLogHandler.install()

      assert handler_config().file == String.to_charlist(path)
    end

    test "is idempotent", %{path: path} do
      put(:log_file_path, path)

      assert FileLogHandler.install() == :ok
      assert FileLogHandler.install() == :ok
      assert installed?()
    end

    test "creates the log directory when it does not exist", %{dir: dir} do
      nested = Path.join([dir, "deep", "nested", "app.log"])
      put(:log_file_path, nested)

      FileLogHandler.install()

      assert File.dir?(Path.dirname(nested))
    end
  end

  describe "rotation settings" do
    test "defaults to 10MB across 5 files", %{path: path} do
      put(:log_file_path, path)

      FileLogHandler.install()

      config = handler_config()
      assert config.max_no_bytes == 10_000_000
      assert config.max_no_files == 5
    end

    test "reads limits from the environment", %{path: path} do
      put(:log_file_path, path)
      System.put_env("GAMEND_OBSERVABILITY_LOG_FILE_MAX_BYTES", "2048")
      System.put_env("GAMEND_OBSERVABILITY_LOG_FILE_MAX_FILES", "3")
      apply_env()

      FileLogHandler.install()

      config = handler_config()
      assert config.max_no_bytes == 2048
      assert config.max_no_files == 3
    end

    test "falls back to defaults on an unparseable limit", %{path: path} do
      put(:log_file_path, path)
      System.put_env("GAMEND_OBSERVABILITY_LOG_FILE_MAX_BYTES", "not-a-number")
      apply_env()

      FileLogHandler.install()

      config = handler_config()
      assert config.max_no_bytes == 10_000_000
      assert config.max_no_files == 5
    end

    test "an unknown GAMEND_OBSERVABILITY_LOG_FILE_LEVEL falls back rather than crashing", %{
      path: path
    } do
      put(:log_file_path, path)
      System.put_env("GAMEND_OBSERVABILITY_LOG_FILE_LEVEL", "definitely-not-a-level")
      apply_env()

      FileLogHandler.install()

      assert installed?()
      {:ok, %{level: level}} = :logger.get_handler_config(@handler_id)
      assert level == :info
    end

    test "reads a valid LOG_FILE_LEVEL", %{path: path} do
      put(:log_file_path, path)
      System.put_env("GAMEND_OBSERVABILITY_LOG_FILE_LEVEL", "warning")
      apply_env()

      FileLogHandler.install()

      {:ok, %{level: level}} = :logger.get_handler_config(@handler_id)
      assert level == :warning
    end
  end

  describe "rotation actually happens" do
    @tag :slow
    test "rolls over to numbered files once max_no_bytes is exceeded", %{dir: dir, path: path} do
      # Config alone proves nothing — this drives real writes past the limit and
      # checks OTP rotated, so the "10MB x 5" promise is verified end to end.
      put(:log_file_path, path)
      put(:log_file_max_bytes, 1_024)
      put(:log_file_max_files, 3)

      FileLogHandler.install()

      # Logger.warning, not info: the test env sets the primary logger level to
      # :warning, so info never reaches a handler and the probe would write
      # nothing while still "passing" a weaker assertion.
      #
      # Messages are sized well under max_no_bytes and synced individually.
      # A tight loop of hundreds trips :logger_std_h's overload protection
      # (dropping past drop_mode_qlen), and messages *larger* than the limit
      # rotate on every single write, which leaves the live file empty and makes
      # the result read as "nothing was logged".
      for i <- 1..6 do
        Logger.warning("rotation probe #{i} #{String.duplicate("x", 600)}")
        :logger_std_h.filesync(@handler_id)
      end

      files = dir |> File.ls!() |> Enum.sort()

      assert "test.log" in files

      # OTP names rotated files test.log.0, test.log.1, ...
      rotated = Enum.filter(files, &String.match?(&1, ~r/^test\.log\.\d+$/))
      assert rotated != [], "expected rotated files, got: #{inspect(files)}"

      # Bounded by max_no_files, which is the half of "10MB x 5" that keeps a
      # busy server from filling its disk.
      assert length(rotated) <= 3, "rotation kept too many files: #{inspect(files)}"

      # The live file is rolled before it grows past the limit.
      assert File.stat!(path).size <= 1_024 * 2
    end
  end
end
