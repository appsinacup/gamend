defmodule GamendWeb.IpBanSyncTest do
  # The ban table kept in step with the other instances (`GamendWeb.IpBanSync`):
  # a ban or unban broadcast from another node is applied here, one from this
  # node is not (the plug applied it already), and the persisted bans load.
  use Gamend.DataCase, async: false

  alias GamendWeb.IpBanSync
  alias GamendWeb.Plugs.IpBan

  @ip "203.0.113.88"

  setup do
    IpBan.init_table()
    on_exit(fn -> IpBan.unban(@ip) end)
    :ok
  end

  defp later, do: DateTime.utc_now() |> DateTime.add(3600, :second)

  test "a ban from another node is applied, and its unban lifts it" do
    {:noreply, _} =
      IpBanSync.handle_info({:ip_ban, :banned, @ip, later(), :other@node}, %{loaded?: true})

    assert IpBan.banned?(@ip)

    {:noreply, _} =
      IpBanSync.handle_info({:ip_ban, :unbanned, @ip, nil, :other@node}, %{loaded?: true})

    refute IpBan.banned?(@ip)
  end

  test "an event this node sent is not applied twice" do
    {:noreply, _} =
      IpBanSync.handle_info({:ip_ban, :banned, @ip, later(), Node.self()}, %{loaded?: true})

    refute IpBan.banned?(@ip)
  end

  test "the persisted bans load once; a later retry is a no-op" do
    assert {:noreply, %{loaded?: true}} =
             IpBanSync.handle_continue(:load_persisted, %{loaded?: false})

    assert {:noreply, %{loaded?: true}} = IpBanSync.handle_info(:retry_load, %{loaded?: true})
    assert {:noreply, %{loaded?: true}} = IpBanSync.handle_info(:unrelated, %{loaded?: true})
  end
end
