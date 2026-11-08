defmodule GamendWeb.Api.V1.UserControllerTest do
  use GamendWeb.ConnCase

  alias Gamend.Accounts

  import Gamend.AccountsFixtures

  test "GET /api/v1/users returns search results", %{conn: conn} do
    a = user_fixture(%{email: "search-me@example.com"})
    {:ok, a} = Accounts.update_user_display_name(a, %{"display_name" => "SearchMe"})

    conn = get(conn, "/api/v1/users", %{q: "Search"})
    assert conn.status == 200

    resp = json_response(conn, 200)
    assert is_map(resp)
    assert is_list(resp["data"])
    assert Enum.any?(resp["data"], fn r -> r["id"] == a.id end)
    assert Enum.all?(resp["data"], fn r -> not Map.has_key?(r, "email") end)
  end

  test "GET /api/v1/users does not search by email", %{conn: conn} do
    user = user_fixture(%{email: "hidden-search@example.com"})
    {:ok, _user} = Accounts.update_user_display_name(user, %{"display_name" => "VisibleName"})

    conn = get(conn, "/api/v1/users", %{q: "hidden-search"})
    resp = json_response(conn, 200)

    assert resp["data"] == []
    assert resp["meta"]["total_count"] == 0
  end

  test "search pagination returns total_count and total_pages", %{conn: conn} do
    # create 3 matching users
    for email <- ["many1@example.com", "many2@example.com", "other@example.com"] do
      user = user_fixture(%{email: email})
      {:ok, _user} = Accounts.update_user_display_name(user, %{"display_name" => "Many"})
    end

    # page 1, size 2
    conn1 = get(conn, "/api/v1/users", %{q: "Many", page: 1, page_size: 2})
    resp1 = json_response(conn1, 200)
    assert length(resp1["data"]) == 2

    expected_total = Gamend.Accounts.count_search_users("Many")
    assert resp1["meta"]["total_count"] == expected_total
    assert resp1["meta"]["total_pages"] == div(expected_total + 2 - 1, 2)

    # page 2 should have the remaining results (could be 0..1 depending on fixtures)
    conn2 = get(conn, "/api/v1/users", %{q: "Many", page: 2, page_size: 2})
    resp2 = json_response(conn2, 200)
    remaining = max(0, expected_total - 2)
    assert length(resp2["data"]) == remaining
    assert resp2["meta"]["total_count"] == expected_total
    assert resp2["meta"]["total_pages"] == div(expected_total + 2 - 1, 2)
  end

  test "GET /api/v1/users/:id returns user info", %{conn: conn} do
    u = user_fixture(%{email: "foo-user@example.com"})
    {:ok, u} = Accounts.update_user_display_name(u, %{"display_name" => "FooUser"})

    conn = get(conn, "/api/v1/users/#{u.id}")
    assert conn.status == 200
    resp = json_response(conn, 200)["data"]
    assert resp["id"] == u.id
    refute Map.has_key?(resp, "email")
    # Another user's lobby and party are private: not even an empty field.
    refute Map.has_key?(resp, "lobby_id")
    refute Map.has_key?(resp, "party_id")
    assert resp["last_seen_at"] == "1970-01-01T00:00:00Z"
  end

  test "GET /api/v1/users/:id says nothing of when the player is online", %{conn: conn} do
    u = user_fixture(%{email: "seen-user@example.com"})

    u
    |> Ecto.Changeset.change(is_online: true, last_seen_at: DateTime.utc_now(:second))
    |> Gamend.Repo.update!()

    Gamend.Accounts.invalidate_user_cache_by_id(u.id)

    resp = conn |> get("/api/v1/users/#{u.id}") |> json_response(200) |> Map.fetch!("data")

    assert resp["is_online"] == false
    assert resp["last_seen_at"] == "1970-01-01T00:00:00Z"
  end

  test "GET /api/v1/users/:id returns 404 if not found", %{conn: conn} do
    conn = get(conn, "/api/v1/users/00000000-0000-0000-0000-000000000000")
    assert conn.status == 404
  end

  describe "public metadata exposure" do
    # Both endpoints are unauthenticated, so whatever they return about a user
    # is world-readable and reachable by guessing a name prefix. They used to
    # return `user.metadata` whole, which for a game that keeps position or
    # routing in there is a stranger tracking a named player.

    setup do
      previous = Application.get_env(:gamend_web, GamendWeb.Features)

      on_exit(fn ->
        if previous,
          do: Application.put_env(:gamend_web, GamendWeb.Features, previous),
          else: Application.delete_env(:gamend_web, GamendWeb.Features)
      end)

      user = user_fixture(%{email: "meta-leak@example.com"})
      {:ok, user} = Accounts.update_user_display_name(user, %{"display_name" => "MetaLeak"})

      {:ok, user} =
        Accounts.merge_metadata(user, %{
          "learning" => %{"course_id" => "languages", "lesson_id" => "es_es"},
          "map_route" => "es:madrid,sevilla",
          "map_city_id" => "madrid"
        })

      %{user: user}
    end

    defp allow_keys(keys) do
      config = Application.get_env(:gamend_web, GamendWeb.Features, [])

      Application.put_env(
        :gamend_web,
        GamendWeb.Features,
        Keyword.put(config, :public_user_metadata_keys, keys)
      )
    end

    test "search strips metadata by default", %{conn: conn, user: user} do
      allow_keys([])

      row =
        conn
        |> get("/api/v1/users", %{q: "MetaLeak"})
        |> json_response(200)
        |> Map.fetch!("data")
        |> Enum.find(&(&1["id"] == user.id))

      assert row["display_name"] == "MetaLeak"
      assert row["metadata"] == %{}
    end

    test "show strips metadata by default", %{conn: conn, user: user} do
      allow_keys([])

      resp =
        conn |> get("/api/v1/users/#{user.id}") |> json_response(200) |> Map.fetch!("data")

      assert resp["metadata"] == %{}
    end

    test "an allow-listed key is returned and everything else still is not", %{
      conn: conn,
      user: user
    } do
      allow_keys(["learning"])

      resp =
        conn |> get("/api/v1/users/#{user.id}") |> json_response(200) |> Map.fetch!("data")

      assert resp["metadata"]["learning"]["lesson_id"] == "es_es"
      refute Map.has_key?(resp["metadata"], "map_route")
      refute Map.has_key?(resp["metadata"], "map_city_id")
    end

    test "the profile picture is never returned", %{conn: conn, user: user} do
      # profile_url is imported verbatim from Google/Discord/Steam/Facebook at
      # OAuth sign-in, so it is routinely a photograph of the account holder.
      # An unauthenticated name search must not return it.
      allow_keys(["learning"])

      row =
        conn
        |> get("/api/v1/users", %{q: "MetaLeak"})
        |> json_response(200)
        |> Map.fetch!("data")
        |> Enum.find(&(&1["id"] == user.id))

      refute Map.has_key?(row, "profile_url")

      resp = conn |> get("/api/v1/users/#{user.id}") |> json_response(200)
      refute Map.has_key?(resp, "profile_url")
    end
  end
end
