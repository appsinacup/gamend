defmodule GamendWeb.Plugs.IpBanTest do
  use Gamend.DataCase, async: false

  alias Gamend.Bans
  alias Gamend.Bans.Cache
  alias GamendWeb.Plugs.IpBan

  setup do
    Cache.init_table()
    on_exit(fn -> :ets.delete_all_objects(:bans) end)
    :ok
  end

  defp in_an_hour, do: Bans.expires_after(:timer.hours(1))

  test "ban/2 applies locally and persists to the database" do
    {:ok, _ban} = IpBan.ban("203.0.113.7", expires_at: in_an_hour(), reason: "Scraping")

    assert IpBan.banned?("203.0.113.7")

    assert [%{subject: "203.0.113.7", expires_at: %DateTime{}, reason: "Scraping"}] =
             Bans.list_active(:ip)
  end

  test "permanent bans persist with nil expires_at" do
    {:ok, _ban} = IpBan.ban("203.0.113.8")

    assert [%{subject: "203.0.113.8", expires_at: nil}] = Bans.list_active(:ip)
  end

  test "unban/1 lifts the ban locally and in the database, and keeps it as history" do
    {:ok, _ban} = IpBan.ban("203.0.113.9")
    :ok = IpBan.unban("203.0.113.9")

    refute IpBan.banned?("203.0.113.9")
    assert Bans.list_active(:ip) == []
    assert [%{subject: "203.0.113.9", lifted_at: %DateTime{}}] = Bans.list(%{kind: :ip})
  end

  test "load_persisted/0 restores bans into ETS" do
    {:ok, _} = IpBan.ban("203.0.113.10")
    {:ok, _} = IpBan.ban("203.0.113.11", expires_at: in_an_hour())

    # an expired ban must not be restored
    expired = DateTime.add(DateTime.utc_now(:second), -60, :second)
    Repo.insert!(%Bans.Ban{kind: :ip, subject: "203.0.113.12", expires_at: expired})

    :ets.delete_all_objects(:bans)
    :ok = Cache.load_persisted()

    assert IpBan.banned?("203.0.113.10")
    assert IpBan.banned?("203.0.113.11")
    refute IpBan.banned?("203.0.113.12")
  end

  test "apply_remote/2 mirrors events without touching the database" do
    :ok = Cache.apply_remote(:put, {{:ip, "203.0.113.13", nil}, nil})
    assert IpBan.banned?("203.0.113.13")
    assert Bans.list_active(:ip) == []

    :ok = Cache.apply_remote(:deleted, {:ip, "203.0.113.13", nil})
    refute IpBan.banned?("203.0.113.13")
  end

  describe "IPv6" do
    test "a ban covers the address's /64, and is listed as the /64" do
      {:ok, _ban} = IpBan.ban("2001:db8:5:6::1")

      assert IpBan.banned?("2001:db8:5:6:ffff::2")
      refute IpBan.banned?("2001:db8:5:7::1")
      # Account bans other tests leave in the shared cache are not this test's.
      assert [{:ip, "2001:db8:5:6::/64", :infinity}] =
               Enum.filter(Cache.list(), &match?({:ip, _, _}, &1))

      assert [%{subject: "2001:db8:5:6::/64"}] = Bans.list_active(:ip)

      :ok = IpBan.unban("2001:db8:5:6::abcd")
      refute IpBan.banned?("2001:db8:5:6::1")
    end

    test "a ban stored per address, as before, still holds and still lifts" do
      Repo.insert!(%Bans.Ban{kind: :ip, subject: "2001:db8:9::1"})
      :ok = Cache.load_persisted()
      assert IpBan.banned?("2001:db8:9::1")

      :ok = IpBan.unban("2001:db8:9::1")
      refute IpBan.banned?("2001:db8:9::1")
      assert Bans.list_active(:ip) == []
    end

    test "the plug refuses any address in a banned /64" do
      {:ok, _ban} = IpBan.ban("2001:db8:5:6::1")

      conn = %{Phoenix.ConnTest.build_conn() | remote_ip: {0x2001, 0xDB8, 5, 6, 7, 7, 7, 7}}
      assert IpBan.call(conn, []).halted

      other = %{Phoenix.ConnTest.build_conn() | remote_ip: {0x2001, 0xDB8, 5, 8, 0, 0, 0, 1}}
      refute IpBan.call(other, []).halted
    end
  end
end
