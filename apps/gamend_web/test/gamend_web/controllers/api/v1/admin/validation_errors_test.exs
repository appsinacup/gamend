defmodule GamendWeb.Api.V1.Admin.ValidationErrorsTest do
  @moduledoc """
  The validation-failure branch of the admin write endpoints.

  Seventeen call sites serialized changeset errors as raw `{msg, opts}` tuples,
  which `Jason` cannot encode — so each of these raised
  `Protocol.UndefinedError` and answered **500**, on endpoints whose OpenAPI
  operation documents a 422. Not one of those branches had a test, which is why
  it survived. These are that test.
  """
  use GamendWeb.ConnCase, async: false

  alias Gamend.Accounts
  alias GamendWeb.Auth.Guardian

  setup %{conn: conn} do
    user = Gamend.AccountsFixtures.user_fixture()
    {:ok, admin} = Accounts.update_user(user, %{is_admin: true})
    {:ok, token, _} = Guardian.encode_and_sign(admin)
    %{admin_conn: put_req_header(conn, "authorization", "Bearer " <> token)}
  end

  describe "a changeset failure is a 422 with a serializable body" do
    test "admin leaderboard create", %{admin_conn: conn} do
      body = conn |> post(~p"/api/v1/admin/leaderboards", %{}) |> json_response(422)

      assert body["error"] == "validation_failed"
      assert is_map(body["errors"])
      assert body["errors"] != %{}
    end

    test "admin kv entry create", %{admin_conn: conn} do
      resp = post(conn, ~p"/api/v1/admin/kv/entries", %{})
      assert resp.status in [400, 422]
      # Whatever the status, the body must survive JSON encoding — that is the
      # part that used to raise.
      assert is_map(json_response(resp, resp.status))
    end
  end

  describe "message formatting" do
    test "messages are interpolated, not raw msgids", %{admin_conn: conn} do
      # A length violation carries `%{count}` in its msgid. Shipping that
      # uninterpolated was the second-most-common shape before this.
      long = String.duplicate("a", 500)

      body =
        conn
        |> post(~p"/api/v1/admin/leaderboards", %{"key" => long, "title" => long})
        |> json_response(422)

      for {_field, messages} <- body["errors"], message <- List.wrap(messages) do
        assert is_binary(message), "expected a string message, got #{inspect(message)}"
        refute message =~ "%{", "message still carries an uninterpolated binding: #{message}"
      end
    end
  end

  describe "admin leaderboard record create, malformed input" do
    setup do
      {:ok, board} =
        Gamend.Leaderboards.create_leaderboard(%{
          "slug" => "rec_#{System.unique_integer([:positive])}",
          "title" => "Records"
        })

      %{board: board}
    end

    # `String.to_integer/1` raised on these, so each answered 500.
    test "a non-numeric, partial or float score is a 422", %{admin_conn: conn, board: board} do
      user = Gamend.AccountsFixtures.user_fixture()

      for bad <- ["abc", "12abc", 1.5] do
        body =
          conn
          |> post(~p"/api/v1/admin/leaderboards/#{board.id}/records", %{
            "user_id" => user.id,
            "score" => bad
          })
          |> json_response(422)

        assert body["errors"]["score"], "#{inspect(bad)} was not rejected"
      end
    end

    # submit_score reports this as :leaderboard_not_found, which no clause
    # matched, so it fell through to the 400 catch-all.
    test "an unknown leaderboard is a 404", %{admin_conn: conn} do
      user = Gamend.AccountsFixtures.user_fixture()

      body =
        conn
        |> post(~p"/api/v1/admin/leaderboards/#{Ecto.UUID.generate()}/records", %{
          "user_id" => user.id,
          "score" => 5
        })
        |> json_response(404)

      assert body["error"] == "leaderboard_not_found"
    end
  end
end
