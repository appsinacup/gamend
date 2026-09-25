defmodule Gamend.Accounts.UserNotifierTest do
  use Gamend.DataCase, async: false

  import ExUnit.CaptureLog

  alias Gamend.Accounts.UserNotifier
  alias Gamend.SettingsHelpers

  defmodule HangingAdapter do
    use Swoosh.Adapter

    @impl true
    def deliver(_email, _config), do: Process.sleep(:infinity)
  end

  describe "a relay that never answers" do
    setup do
      mailer = Application.get_env(:gamend_core, Gamend.Mailer)
      Application.put_env(:gamend_core, Gamend.Mailer, adapter: HangingAdapter)
      SettingsHelpers.put(:gamend_core, Gamend.Mail, :send_timeout_ms, 50)

      on_exit(fn ->
        Application.put_env(:gamend_core, Gamend.Mailer, mailer)
        SettingsHelpers.delete(:gamend_core, Gamend.Mail, :send_timeout_ms)
      end)
    end

    # gen_smtp waits up to 20 minutes for each reply, and a hung relay held the
    # request or job that was sending for that long.
    test "is given up on after send_timeout_ms rather than waited on" do
      log =
        capture_log(fn ->
          {micros, result} =
            :timer.tc(fn -> UserNotifier.deliver_test_email("hung@example.com") end)

          assert {:error, {:error, :timeout}} = result
          assert micros < 2_000_000
        end)

      assert log =~ "timeout"
    end
  end

  test "a send that raises is reported as a failure, not a crash" do
    defmodule RaisingAdapter do
      use Swoosh.Adapter

      @impl true
      def deliver(_email, _config), do: raise("relay exploded")
    end

    mailer = Application.get_env(:gamend_core, Gamend.Mailer)
    Application.put_env(:gamend_core, Gamend.Mailer, adapter: RaisingAdapter)
    on_exit(fn -> Application.put_env(:gamend_core, Gamend.Mailer, mailer) end)

    capture_log(fn ->
      assert {:error, {:exception, %RuntimeError{}}} =
               UserNotifier.deliver_test_email("boom@example.com")
    end)
  end
end
