defmodule Gamend.HTTPTest do
  use ExUnit.Case, async: false

  alias Gamend.SettingsHelpers

  test "every call gets the declared timeout and retries" do
    opts = Gamend.HTTP.options()

    assert opts[:receive_timeout] == 10_000
    assert opts[:connect_options] == [timeout: 10_000]
    assert opts[:max_retries] == 1
  end

  test "the settings drive them, and a caller's own options win" do
    SettingsHelpers.put(:gamend_core, Gamend.HTTP, :client_timeout_ms, 2_000)
    SettingsHelpers.put(:gamend_core, Gamend.HTTP, :client_retries, 0)

    on_exit(fn ->
      SettingsHelpers.delete(:gamend_core, Gamend.HTTP, :client_timeout_ms)
      SettingsHelpers.delete(:gamend_core, Gamend.HTTP, :client_retries)
    end)

    opts = Gamend.HTTP.options(receive_timeout: 500, form: [a: 1])

    assert opts[:receive_timeout] == 500
    assert opts[:connect_options] == [timeout: 2_000]
    assert opts[:max_retries] == 0
    assert opts[:form] == [a: 1]
  end

  test "a request goes out with them" do
    Req.Test.stub(Gamend.HTTPTest, fn conn -> Req.Test.json(conn, %{"ok" => true}) end)

    assert {:ok, %Req.Response{status: 200, body: %{"ok" => true}}} =
             Gamend.HTTP.get("http://provider.test/x", plug: {Req.Test, Gamend.HTTPTest})
  end
end
