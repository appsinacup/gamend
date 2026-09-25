defmodule GamendWeb.Auth.ApiTokenAuthTest do
  @moduledoc """
  A personal API token authenticates any route an access token does, through
  both pipelines, and stops the moment it is revoked, expired or superseded.
  """
  use GamendWeb.ConnCase, async: true

  import Ecto.Query

  alias Gamend.Accounts
  alias Gamend.Accounts.ApiToken
  alias Gamend.Accounts.ApiTokens
  alias Gamend.AccountsFixtures
  alias Gamend.Repo
  alias GamendWeb.Auth.Guardian

  setup do
    user = AccountsFixtures.user_fixture()
    {:ok, token, row} = ApiTokens.create(user, %{"name" => "ci"})
    %{user: user, token: token, row: row}
  end

  defp me(conn, token) do
    conn
    |> put_req_header("authorization", "Bearer " <> token)
    |> get("/api/v1/me")
  end

  test "authenticates as its owner", %{conn: conn, user: user, token: token} do
    assert %{"data" => %{"id" => id}} = conn |> me(token) |> json_response(200)
    assert id == user.id
  end

  test "the scheme is case-insensitive, as it is for a JWT", %{conn: conn, token: token} do
    conn =
      conn
      |> put_req_header("authorization", "bearer " <> token)
      |> get("/api/v1/me")

    assert json_response(conn, 200)
  end

  test "records its use", %{conn: conn, token: token, row: row} do
    assert conn |> me(token) |> json_response(200)

    assert Repo.get!(ApiToken, row.id).last_used_at
  end

  test "an unknown token is a 401 with the invalid_token code", %{conn: conn} do
    assert %{"error" => "invalid_token"} =
             conn |> me("gamend_pat_notarealtoken") |> json_response(401)
  end

  test "a revoked token is a 401", %{conn: conn, user: user, token: token, row: row} do
    {:ok, _} = ApiTokens.revoke(user.id, row.id)

    assert conn |> me(token) |> json_response(401)
  end

  test "an expired token is a 401", %{conn: conn, token: token, row: row} do
    past = DateTime.utc_now() |> DateTime.add(-1, :minute) |> DateTime.truncate(:second)
    Repo.update_all(from(t in ApiToken, where: t.id == ^row.id), set: [expires_at: past])

    assert conn |> me(token) |> json_response(401)
  end

  test "signing out everywhere retires it", %{conn: conn, user: user, token: token} do
    {:ok, _} = Accounts.revoke_all_tokens(user)

    assert conn |> me(token) |> json_response(401)
  end

  test "a JWT still works beside it", %{conn: conn, user: user} do
    {:ok, jwt, _claims} = Guardian.encode_and_sign(user)

    assert conn |> me(jwt) |> json_response(200)
  end
end
