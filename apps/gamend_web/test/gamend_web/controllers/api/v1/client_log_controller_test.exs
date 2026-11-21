defmodule GamendWeb.Api.V1.ClientLogControllerTest do
  use GamendWeb.ConnCase, async: false

  import ExUnit.CaptureLog

  alias Gamend.AccountsFixtures
  alias Gamend.ClientLogs
  alias Gamend.SettingsHelpers
  alias GamendWeb.Auth.Guardian

  setup do
    SettingsHelpers.put(:gamend_core, ClientLogs, :enabled, true)
    on_exit(fn -> SettingsHelpers.delete(:gamend_core, ClientLogs, :enabled) end)
    :ok
  end

  defp session_id, do: "sess-" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

  defp batch(sid, entries \\ nil) do
    %{
      "session" => %{
        "client_session_id" => sid,
        "platform" => "android",
        "app_version" => "1.4.2",
        "build" => "release"
      },
      "entries" =>
        entries ||
          [%{"seq" => 1, "level" => "info", "category" => "game", "message" => "Game starting"}]
    }
  end

  defp post_batch(conn, payload) do
    {result, _log} = with_log(fn -> post(conn, "/api/v1/client_logs", payload) end)
    result
  end

  defp auth_conn(conn, user) do
    {:ok, token, _} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer " <> token)
  end

  describe "GET /api/v1/client_logs/policy" do
    test "tells an unauthenticated client what to collect", %{conn: conn} do
      body = conn |> get("/api/v1/client_logs/policy") |> json_response(200) |> Map.fetch!("data")

      assert body["enabled"] == true
      assert body["level"] == "info"
      assert body["batch_max"] == 200
      assert is_map(body["categories"])
    end

    test "reports disabled so a client collects nothing", %{conn: conn} do
      SettingsHelpers.delete(:gamend_core, ClientLogs, :enabled)

      assert conn
             |> get("/api/v1/client_logs/policy")
             |> json_response(200)
             |> get_in(["data", "enabled"]) ==
               false
    end
  end

  describe "POST /api/v1/client_logs" do
    test "accepts a batch with no bearer token", %{conn: conn} do
      # The whole point of optional auth: a client that cannot log in still
      # needs to be able to report why.
      sid = session_id()
      body = conn |> post_batch(batch(sid)) |> json_response(202) |> Map.fetch!("data")

      assert body["accepted"] == 1
      assert body["client_session_id"] == sid
      assert ClientLogs.get_session(sid).user_id == nil
    end

    test "attributes a batch to the bearer token's user", %{conn: conn} do
      sid = session_id()
      user = AccountsFixtures.user_fixture()

      assert conn |> auth_conn(user) |> post_batch(batch(sid)) |> json_response(202)
      assert ClientLogs.get_session(sid).user_id == user.id
    end

    test "refuses a session claimed by another user", %{conn: conn} do
      sid = session_id()
      owner = AccountsFixtures.user_fixture()
      attacker = AccountsFixtures.user_fixture()

      assert conn |> auth_conn(owner) |> post_batch(batch(sid)) |> json_response(202)

      assert conn
             |> auth_conn(attacker)
             |> post_batch(batch(sid))
             |> json_response(403)
    end

    test "answers 503 when collection is off, so the client retries later", %{conn: conn} do
      SettingsHelpers.delete(:gamend_core, ClientLogs, :enabled)

      assert conn |> post_batch(batch(session_id())) |> json_response(503)
    end

    test "rejects a malformed batch", %{conn: conn} do
      assert conn
             |> post_batch(%{"session" => %{"client_session_id" => "no"}, "entries" => []})
             |> json_response(422)
    end

    test "records the lobby so the run is reachable from the lobby side", %{conn: conn} do
      sid = session_id()

      payload =
        batch(sid, [
          %{
            "seq" => 1,
            "level" => "error",
            "category" => "game",
            "message" => "Restore failed",
            "lobby_id" => "lob-77",
            "screen" => "boat"
          }
        ])

      assert conn |> post_batch(payload) |> json_response(202)

      assert [found] = ClientLogs.list_sessions(lobby_id: "lob-77")
      assert found.client_session_id == sid
      assert found.flagged
    end
  end
end
