defmodule GamendWeb.Plugs.RealIpTest do
  use ExUnit.Case, async: true

  import Plug.Conn
  import Plug.Test

  alias GamendWeb.Plugs.RealIp

  # What the endpoint's listener on `::` reports for an IPv4 peer.
  @mapped_loopback {0, 0, 0, 0, 0, 0xFFFF, 0x7F00, 1}
  @mapped_private {0, 0, 0, 0, 0, 0xFFFF, 0x0A58, 1}
  @mapped_public {0, 0, 0, 0, 0, 0xFFFF, 0xCB00, 0x7109}

  @client {198, 51, 100, 7}

  defp remote_ip(peer, headers \\ []) do
    conn =
      Enum.reduce(headers, conn(:get, "/"), fn {name, value}, conn ->
        put_req_header(conn, name, value)
      end)

    RealIp.call(%{conn | remote_ip: peer}, []).remote_ip
  end

  describe "a proxy reaching the listener over IPv4" do
    test "loopback or private, its X-Forwarded-For names the client" do
      assert remote_ip(@mapped_loopback, [{"x-forwarded-for", "198.51.100.7"}]) == @client
      assert remote_ip(@mapped_private, [{"x-forwarded-for", "198.51.100.7"}]) == @client
    end

    test "the proxies in the chain are walked past, in either form" do
      assert remote_ip(@mapped_private, [{"x-forwarded-for", "198.51.100.7, 127.0.0.1"}]) ==
               @client

      assert remote_ip(@mapped_private, [{"x-forwarded-for", "198.51.100.7, ::ffff:10.88.0.1"}]) ==
               @client
    end

    test "a client's own entries, to the left of the real one, are ignored" do
      assert remote_ip(@mapped_loopback, [{"x-forwarded-for", "127.0.0.1, 198.51.100.7"}]) ==
               @client
    end

    test "a client written in the mapped form comes out as IPv4" do
      assert remote_ip(@mapped_loopback, [{"x-forwarded-for", "::ffff:198.51.100.7"}]) == @client
    end

    test "with no client in the headers, the peer stays as it arrived" do
      assert remote_ip(@mapped_loopback) == @mapped_loopback

      assert remote_ip(@mapped_loopback, [{"x-forwarded-for", "127.0.0.1, 10.0.0.1"}]) ==
               @mapped_loopback
    end

    # Caddy, nginx and the edge pass these on as the client sent them.
    test "cannot be told the client's address by a platform header" do
      assert remote_ip(@mapped_loopback, [{"cf-connecting-ip", "127.0.0.1"}]) == @mapped_loopback
      assert remote_ip(@mapped_loopback, [{"fly-client-ip", "127.0.0.1"}]) == @mapped_loopback

      assert remote_ip(@mapped_loopback, [
               {"cf-connecting-ip", "127.0.0.1"},
               {"x-forwarded-for", "198.51.100.7"}
             ]) == @client
    end
  end

  test "a public peer's headers are ignored, whichever form it arrives in" do
    headers = [
      {"x-forwarded-for", "198.51.100.7"},
      {"cf-connecting-ip", "198.51.100.7"},
      {"fly-client-ip", "198.51.100.7"}
    ]

    assert remote_ip(@mapped_public, headers) == @mapped_public
    assert remote_ip({203, 0, 113, 9}, headers) == {203, 0, 113, 9}
  end

  describe "a peer that is not in the mapped form" do
    test "reads the platform headers first" do
      assert remote_ip({127, 0, 0, 1}, [
               {"cf-connecting-ip", "198.51.100.7"},
               {"x-forwarded-for", "203.0.113.9"}
             ]) == @client

      assert remote_ip({0xFD00, 0, 0, 0, 0, 0, 0, 1}, [{"fly-client-ip", "198.51.100.7"}]) ==
               @client
    end

    test "reads X-Forwarded-For without them" do
      assert remote_ip({0, 0, 0, 0, 0, 0, 0, 1}, [{"x-forwarded-for", "198.51.100.7"}]) == @client
    end
  end
end
