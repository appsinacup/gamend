defmodule GameServerWeb.Api.V1.Admin.IconUploadTest do
  @moduledoc """
  The two-step icon upload, for the entities an admin owns.

  `confirm` is the load-bearing half: the key comes from the client, so a key
  belonging to a *different* entity must be refused — otherwise anyone could
  adopt another entity's object as their icon.
  """

  use GameServerWeb.ConnCase, async: false

  alias GameServer.Accounts.User
  alias GameServer.AccountsFixtures
  alias GameServer.Leaderboards
  alias GameServer.Quests
  alias GameServer.Repo
  alias GameServer.Storage
  alias GameServer.Tournaments
  alias GameServerWeb.Auth.Guardian

  setup %{conn: conn} do
    admin =
      AccountsFixtures.user_fixture()
      |> User.admin_changeset(%{"is_admin" => true})
      |> Repo.update!()

    {:ok, token, _} = Guardian.encode_and_sign(admin)

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> token)
      |> put_req_header("content-type", "application/json")

    {:ok, conn: conn, admin: admin}
  end

  defp targets do
    {:ok, tournament} =
      Tournaments.create_tournament(%{
        slug: "icon-cup-#{System.unique_integer([:positive])}",
        title: "Icon Cup",
        starts_at: DateTime.add(DateTime.utc_now(:second), 3600),
        round_window_sec: 600,
        bracket_size: 4
      })

    {:ok, leaderboard} =
      Leaderboards.create_leaderboard(%{
        slug: "icon_lb_#{System.unique_integer([:positive])}",
        title: "Icon LB"
      })

    {:ok, quest} =
      Quests.create_quest(%{
        key: "icon_quest_#{System.unique_integer([:positive])}",
        title: "Icon Quest",
        objectives: [%{event: "e", target: 1}]
      })

    [
      {"tournaments", tournament.id, "icons/tournaments"},
      {"leaderboards", leaderboard.id, "icons/leaderboards"},
      {"quests", quest.id, "icons/quests"}
    ]
  end

  test "each entity issues a ticket scoped to its own prefix", %{conn: conn} do
    for {segment, id, prefix} <- targets() do
      resp =
        conn
        |> post(~p"/api/v1/admin/#{segment}/#{id}/icon/upload_url", %{
          "content_type" => "image/png"
        })
        |> json_response(200)

      assert String.starts_with?(resp["key"], "#{prefix}/#{id}/"),
             "#{segment}: key #{resp["key"]} not under #{prefix}/#{id}/"

      assert String.ends_with?(resp["key"], ".png")
    end
  end

  test "an unsupported content type is refused", %{conn: conn} do
    [{segment, id, _} | _] = targets()

    assert conn
           |> post(~p"/api/v1/admin/#{segment}/#{id}/icon/upload_url", %{
             "content_type" => "application/x-msdownload"
           })
           |> json_response(400)
  end

  test "confirming a real upload sets icon_url", %{conn: conn} do
    for {segment, id, prefix} <- targets() do
      key = Storage.build_key(prefix, id, "icon.png")
      {:ok, _} = Storage.put(key, "not-really-a-png")

      resp =
        conn
        |> post(~p"/api/v1/admin/#{segment}/#{id}/icon", %{"key" => key})
        |> json_response(200)

      assert resp["data"]["icon_url"] == Storage.url(key), "#{segment} did not persist icon_url"
    end
  end

  test "a key belonging to another entity is refused", %{conn: conn} do
    [{segment, id, prefix}, {_, other_id, _} | _] = targets()

    stolen = Storage.build_key(prefix, other_id, "icon.png")
    {:ok, _} = Storage.put(stolen, "bytes")

    assert conn
           |> post(~p"/api/v1/admin/#{segment}/#{id}/icon", %{"key" => stolen})
           |> json_response(403)
  end

  test "a key that was never uploaded is refused", %{conn: conn} do
    [{segment, id, prefix} | _] = targets()

    assert conn
           |> post(~p"/api/v1/admin/#{segment}/#{id}/icon", %{"key" => "#{prefix}/#{id}/nope.png"})
           |> json_response(400)
  end

  test "a missing key is a bad request, not a crash", %{conn: conn} do
    [{segment, id, _} | _] = targets()

    assert conn
           |> post(~p"/api/v1/admin/#{segment}/#{id}/icon", %{})
           |> json_response(400)
  end
end
