defmodule GameServerWeb.Api.V1.Admin.PushControllerTest do
  use GameServerWeb.ConnCase, async: false
  use Oban.Testing, repo: GameServer.Repo

  alias GameServer.Accounts.User
  alias GameServer.Push
  alias GameServer.Repo
  alias GameServerWeb.Auth.Guardian

  setup %{conn: conn} do
    admin = GameServer.AccountsFixtures.user_fixture()
    {:ok, admin} = admin |> User.admin_changeset(%{"is_admin" => true}) |> Repo.update()
    {:ok, token, _} = Guardian.encode_and_sign(admin)
    target = GameServer.AccountsFixtures.user_fixture()
    %{conn: put_req_header(conn, "authorization", "Bearer " <> token), target: target}
  end

  test "requires admin", %{target: target} do
    {:ok, token, _} = Guardian.encode_and_sign(target)
    conn = build_conn() |> put_req_header("authorization", "Bearer " <> token)
    assert json_response(get(conn, "/api/v1/admin/push/tokens"), 403)
  end

  test "lists tokens with filters and user names", %{conn: conn, target: target} do
    {:ok, live} = Push.register_token(target.id, %{"token" => "t-live", "platform" => "android"})
    {:ok, dead} = Push.register_token(target.id, %{"token" => "t-dead", "platform" => "ios"})
    :ok = Push.disable_token(dead.token)

    body = json_response(get(conn, "/api/v1/admin/push/tokens?user_id=#{target.id}"), 200)
    assert body["meta"]["total_count"] == 2

    body =
      json_response(
        get(conn, "/api/v1/admin/push/tokens?user_id=#{target.id}&status=live"),
        200
      )

    assert [entry] = body["data"]
    assert entry["id"] == live.id
    assert entry["user_name"]
  end

  test "deletes any user's token", %{conn: conn, target: target} do
    {:ok, token} = Push.register_token(target.id, %{"token" => "t", "platform" => "web"})

    assert %{"id" => _} =
             json_response(delete(conn, "/api/v1/admin/push/tokens/#{token.id}"), 200)

    assert Push.count_tokens(target.id) == 0

    assert %{"error" => "not_found"} =
             json_response(delete(conn, "/api/v1/admin/push/tokens/#{token.id}"), 404)
  end

  test "sends a push to a user's live devices", %{conn: conn, target: target} do
    {:ok, _} = Push.register_token(target.id, %{"token" => "t", "platform" => "android"})

    assert %{"status" => "queued"} =
             json_response(
               post(conn, "/api/v1/admin/push/send", %{
                 user_id: target.id,
                 title: "Hello",
                 body: "From admin"
               }),
               200
             )

    assert [job] = all_enqueued(worker: GameServer.Push.DeliveryWorker)
    assert job.args["message"]["title"] == "Hello"
  end

  test "send validates the user and the message", %{conn: conn, target: target} do
    assert %{"error" => "user_not_found"} =
             json_response(
               post(conn, "/api/v1/admin/push/send", %{
                 user_id: GameServer.UUIDv7.generate(),
                 title: "Hello"
               }),
               404
             )

    assert %{"error" => "invalid_message"} =
             json_response(
               post(conn, "/api/v1/admin/push/send", %{user_id: target.id}),
               400
             )
  end
end
