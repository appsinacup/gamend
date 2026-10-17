defmodule GamendWeb.Plugs.MailboxPreviewEnabledTest do
  # The mailbox preview (`/dev/mailbox`) opens only where mail is kept
  # locally (Swoosh's Local adapter) and dev or the feature switch allows it.
  use ExUnit.Case, async: false

  import Plug.Test

  alias GamendWeb.Plugs.MailboxPreviewEnabled

  setup do
    mailer = Application.get_env(:gamend_core, Gamend.Mailer)
    env = Application.get_env(:gamend_web, :environment)

    on_exit(fn ->
      Application.put_env(:gamend_core, Gamend.Mailer, mailer)

      if env,
        do: Application.put_env(:gamend_web, :environment, env),
        else: Application.delete_env(:gamend_web, :environment)
    end)

    :ok
  end

  defp call do
    MailboxPreviewEnabled.call(conn(:get, "/dev/mailbox"), MailboxPreviewEnabled.init([]))
  end

  defp adapter(adapter), do: Application.put_env(:gamend_core, Gamend.Mailer, adapter: adapter)

  test "dev with the local adapter opens it" do
    Application.put_env(:gamend_web, :environment, :dev)
    adapter(Swoosh.Adapters.Local)
    refute call().halted
  end

  test "a real mail adapter keeps it shut, even in dev" do
    Application.put_env(:gamend_web, :environment, :dev)
    adapter(Swoosh.Adapters.Test)
    conn = call()
    assert conn.halted
    assert conn.status == 404
  end

  test "outside dev it stays shut unless the feature is on" do
    Application.put_env(:gamend_web, :environment, :prod)
    adapter(Swoosh.Adapters.Local)

    if GamendWeb.Features.enabled?(:mailbox_preview),
      do: refute(call().halted),
      else: assert(call().status == 404)
  end
end
