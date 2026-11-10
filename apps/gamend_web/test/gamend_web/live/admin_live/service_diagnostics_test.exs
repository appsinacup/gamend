defmodule GamendWeb.AdminLive.ServiceDiagnosticsTest do
  use ExUnit.Case, async: false

  alias Gamend.SettingsHelpers
  alias GamendWeb.AdminLive.ServiceDiagnostics

  describe "ssl_cert_info/0" do
    setup do
      previous = SettingsHelpers.get(:gamend_web, GamendWeb.Tls, :certfile)

      on_exit(fn ->
        if previous,
          do: SettingsHelpers.put(:gamend_web, GamendWeb.Tls, :certfile, previous),
          else: SettingsHelpers.delete(:gamend_web, GamendWeb.Tls, :certfile)
      end)

      :ok
    end

    test "reads validity dates and the subject from the configured certificate" do
      path = write_certificate()
      SettingsHelpers.put(:gamend_web, GamendWeb.Tls, :certfile, path)

      info = ServiceDiagnostics.ssl_cert_info()

      assert {:ok, not_before} = Date.from_iso8601(info.not_before)
      assert {:ok, not_after} = Date.from_iso8601(info.not_after)
      assert Date.compare(not_before, not_after) == :lt
      assert info.days_remaining == Date.diff(not_after, Date.utc_today())
      # OTP's test chain names its peer "server Peer cert", issued by its root.
      assert info.subject == "server Peer cert"
      assert info.issuer == "SERVER ROOT CA"
      # Whole bytes: OTP numbers its test certificates from 1, and serial 3 is "03".
      assert info.serial =~ ~r/^[0-9a-f]{2}(:[0-9a-f]{2})*$/
    end

    test "is nil when no certificate is configured or the file is not one" do
      SettingsHelpers.delete(:gamend_web, GamendWeb.Tls, :certfile)
      assert ServiceDiagnostics.ssl_cert_info() == nil

      path = Path.join(System.tmp_dir!(), "not_a_cert_#{System.unique_integer([:positive])}.pem")
      File.write!(path, "not a certificate")
      SettingsHelpers.put(:gamend_web, GamendWeb.Tls, :certfile, path)
      assert ServiceDiagnostics.ssl_cert_info() == nil
    end
  end

  describe "services/0" do
    test "says when the configuration asks for another adapter than this build's" do
      for key <- [:postgres_host, :postgres_user] do
        previous = SettingsHelpers.get(:gamend_core, Gamend.Database, key)
        SettingsHelpers.put(:gamend_core, Gamend.Database, key, "somewhere")

        on_exit(fn ->
          if previous,
            do: SettingsHelpers.put(:gamend_core, Gamend.Database, key, previous),
            else: SettingsHelpers.delete(:gamend_core, Gamend.Database, key)
        end)
      end

      assert %{configured_adapter: :postgres, source: :env_vars} =
               ServiceDiagnostics.services().database
    end

    test "masks the release cookie and names no cache level's options" do
      services = ServiceDiagnostics.services()

      assert Enum.any?(services.cluster.variables, &match?({"RELEASE_COOKIE", _masked}, &1))
      assert Map.keys(services.cache) |> Enum.sort() == [:enabled?, :inclusion_policy, :l2, :mode]
    end
  end

  defp write_certificate do
    %{server_config: server} =
      :public_key.pkix_test_data(%{
        server_chain: %{root: [], peer: []},
        client_chain: %{root: [], peer: []}
      })

    der = Keyword.fetch!(server, :cert)
    pem = :public_key.pem_encode([{:Certificate, der, :not_encrypted}])
    path = Path.join(System.tmp_dir!(), "cert_#{System.unique_integer([:positive])}.pem")
    File.write!(path, pem)
    path
  end
end
