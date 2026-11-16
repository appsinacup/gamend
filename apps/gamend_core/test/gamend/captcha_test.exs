defmodule Gamend.CaptchaTest do
  use Gamend.DataCase, async: false

  alias Gamend.Captcha

  setup do
    Application.put_env(:gamend_core, :captcha_req_options, plug: {Req.Test, __MODULE__})
    on_exit(fn -> Application.delete_env(:gamend_core, :captcha_req_options) end)
    :ok
  end

  defp enable(opts \\ []) do
    previous = Application.get_env(:gamend_core, Captcha)

    Application.put_env(
      :gamend_core,
      Captcha,
      Keyword.merge([enabled: true, secret_key: "secret"], opts)
    )

    on_exit(fn ->
      if previous,
        do: Application.put_env(:gamend_core, Captcha, previous),
        else: Application.delete_env(:gamend_core, Captcha)
    end)
  end

  defp respond(body) do
    Req.Test.stub(__MODULE__, fn conn -> Req.Test.json(conn, body) end)
  end

  describe "when disabled" do
    test "verify/2 passes without a token and without a network call" do
      # No stub is registered, so a request here would raise rather than pass.
      assert :ok = Captcha.verify(nil)
      assert :ok = Captcha.verify("anything")
    end
  end

  describe "when enabled" do
    setup do
      enable()
      :ok
    end

    test "a token Cloudflare accepts passes" do
      respond(%{"success" => true})

      assert :ok = Captcha.verify("good-token")
    end

    test "a token Cloudflare rejects fails as :invalid" do
      respond(%{"success" => false, "error-codes" => ["invalid-input-response"]})

      assert {:error, :invalid} = Captcha.verify("bad-token")
    end

    test "a missing token fails as :missing without calling out" do
      assert {:error, :missing} = Captcha.verify(nil)
      assert {:error, :missing} = Captcha.verify("")
      assert {:error, :missing} = Captcha.verify("   ")
    end

    # The whole point of the captcha is that an attacker cannot remove it. If an
    # unreachable Cloudflare meant "pass", anyone able to sit between us and
    # Cloudflare could switch the protection off from outside.
    test "an unreachable Cloudflare fails closed" do
      Req.Test.stub(__MODULE__, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

      assert {:error, :unavailable} = Captcha.verify("good-token")
    end

    test "a non-200 from Cloudflare fails closed" do
      Req.Test.stub(__MODULE__, fn conn -> Plug.Conn.send_resp(conn, 500, "boom") end)

      assert {:error, :unavailable} = Captcha.verify("good-token")
    end

    test "the token and secret are sent, and the client IP only when it is real" do
      test_pid = self()

      Req.Test.stub(__MODULE__, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:sent, URI.decode_query(body)})
        Req.Test.json(conn, %{"success" => true})
      end)

      assert :ok = Captcha.verify("tok", "203.0.113.7")
      assert_received {:sent, sent}
      assert %{"secret" => "secret", "response" => "tok", "remoteip" => "203.0.113.7"} = sent

      # "unknown" is what LiveHelpers.client_ip/2 returns with no known address.
      # Forwarding it literally would have Cloudflare score a bogus address.
      assert :ok = Captcha.verify("tok", "unknown")
      assert_received {:sent, sent}
      refute Map.has_key?(sent, "remoteip")

      assert :ok = Captcha.verify("tok", nil)
      assert_received {:sent, sent}
      refute Map.has_key?(sent, "remoteip")
    end

    test "site_key/0 falls back to the always-passes dummy when unset" do
      assert Captcha.site_key() == "1x00000000000000000000AA"
    end

    test "site_key/0 prefers a configured key" do
      enable(site_key: "0x4AAAreal")

      assert Captcha.site_key() == "0x4AAAreal"
    end
  end
end
