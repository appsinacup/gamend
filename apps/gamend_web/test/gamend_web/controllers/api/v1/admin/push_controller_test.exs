defmodule GamendWeb.Api.V1.Admin.PushControllerTest do
  use GamendWeb.ConnCase, async: false
  use Oban.Testing, repo: Gamend.Repo

  alias Gamend.Accounts.User
  alias Gamend.Push
  alias Gamend.Repo
  alias GamendWeb.Auth.Guardian

  setup %{conn: conn} do
    admin = Gamend.AccountsFixtures.user_fixture()
    {:ok, admin} = admin |> User.admin_changeset(%{"is_admin" => true}) |> Repo.update()
    {:ok, token, _} = Guardian.encode_and_sign(admin)
    target = Gamend.AccountsFixtures.user_fixture()
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

    assert json_response(delete(conn, "/api/v1/admin/push/tokens/#{token.id}"), 200) ==
             %{"ok" => true}

    assert Push.count_tokens(target.id) == 0

    assert %{"error" => "not_found"} =
             json_response(delete(conn, "/api/v1/admin/push/tokens/#{token.id}"), 404)
  end

  test "sends a push to a user's live devices", %{conn: conn, target: target} do
    {:ok, _} = Push.register_token(target.id, %{"token" => "t", "platform" => "android"})

    assert %{"ok" => true} =
             json_response(
               post(conn, "/api/v1/admin/push/send", %{
                 user_id: target.id,
                 title: "Hello",
                 body: "From admin"
               }),
               200
             )

    assert [job] = all_enqueued(worker: Gamend.Push.DeliveryWorker)
    assert job.args["message"]["title"] == "Hello"
  end

  test "send validates the user and the message", %{conn: conn, target: target} do
    assert %{"error" => "user_not_found"} =
             json_response(
               post(conn, "/api/v1/admin/push/send", %{
                 user_id: Gamend.UUIDv7.generate(),
                 title: "Hello"
               }),
               404
             )

    assert %{"error" => "user_not_found"} =
             json_response(
               post(conn, "/api/v1/admin/push/send", %{user_id: "not-a-uuid", title: "Hello"}),
               404
             )

    assert %{"error" => "validation_failed", "errors" => %{"title" => [_]}} =
             json_response(
               post(conn, "/api/v1/admin/push/send", %{user_id: target.id}),
               422
             )

    assert %{"error" => "missing_param"} =
             json_response(post(conn, "/api/v1/admin/push/send", %{title: "Hello"}), 400)
  end
end
