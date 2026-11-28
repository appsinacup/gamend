defmodule GamendWeb.Api.V1.AvatarIconTest do
  use GamendWeb.ConnCase, async: false

  alias Gamend.Accounts
  alias Gamend.Accounts.User
  alias Gamend.Icons
  alias Gamend.Storage
  alias GamendWeb.Auth.Guardian

  @png <<0x89, "PNG\r\n", 0x1A, "\n", "rest-of-the-file">>

  setup %{conn: conn} do
    dir = Path.join(System.tmp_dir!(), "gs_avatar_icon_#{System.unique_integer([:positive])}")
    old = Application.get_env(:gamend_core, Gamend.Storage.Local)
    Application.put_env(:gamend_core, Gamend.Storage.Local, dir: dir)

    on_exit(fn ->
      File.rm_rf(dir)
      if old, do: Application.put_env(:gamend_core, Gamend.Storage.Local, old)
    end)

    user = Gamend.AccountsFixtures.user_fixture()
    %{conn: conn, authed: authed(conn, user), user: user}
  end

  defp authed(conn, user) do
    {:ok, token, _} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer " <> token)
  end

  # Not the one the user's id gave them, so a pick is a change.
  defp another_pick(user) do
    shown = Icons.name(User.public_avatar_url(user))
    Enum.find(Icons.picks(), &(&1 != shown))
  end

  test "GET /api/v1/avatar_icons lists the picker's icons and colours, with no session", %{
    conn: conn
  } do
    data = conn |> get("/api/v1/avatar_icons") |> json_response(200) |> Map.fetch!("data")

    assert Enum.map(data["icons"], & &1["key"]) == Icons.picks()
    assert length(data["icons"]) == 30
    assert %{"key" => "rocket-launch", "url" => "/icons/rocket-launch.svg"} in data["icons"]
    assert Enum.map(data["colors"], & &1["key"]) == ~w(primary info success warning error)
    assert %{"key" => "primary", "css" => "var(--color-primary)"} in data["colors"]

    # Each icon's url is the SVG the server serves.
    assert get(build_conn(), "/icons/rocket-launch.svg").status == 200
  end

  test "POST /api/v1/me/avatar/icon sets the icon in its colour, as the site's Save does", %{
    authed: authed,
    user: user
  } do
    # An uploaded picture it replaces.
    key = Storage.build_key("avatars", user.id, "x.png")
    {:ok, _} = Storage.put(key, @png)
    {:ok, user} = Accounts.update_user_avatar(user, Storage.url(key))

    Phoenix.PubSub.subscribe(Gamend.PubSub, "user:#{user.id}")
    icon = another_pick(user)

    body =
      authed
      |> post("/api/v1/me/avatar/icon", %{icon: icon, color: "success"})
      |> json_response(200)

    url = "/icons/#{icon}.svg?color=success"
    assert body["data"]["profile_url"] == url
    assert json_response(get(authed, "/api/v1/me"), 200)["data"]["profile_url"] == url
    # What the user channel says as `user_updated`, as for the site's Save.
    assert_receive %Phoenix.Socket.Broadcast{event: "updated", payload: payload}
    assert (payload[:profile_url] || payload["profile_url"]) == url
    refute Storage.exists?(key)

    # The icon shown already: answered as it is, nothing said.
    assert json_response(
             post(authed, "/api/v1/me/avatar/icon", %{icon: icon, color: "success"}),
             200
           )

    refute_receive %Phoenix.Socket.Broadcast{event: "updated"}, 50

    # No colour: the icon alone.
    assert json_response(post(authed, "/api/v1/me/avatar/icon", %{icon: icon, color: ""}), 200)[
             "data"
           ]["profile_url"] == "/icons/#{icon}.svg"
  end

  test "an unknown icon or colour is refused, and nothing changes", %{authed: authed, user: user} do
    assert json_response(post(authed, "/api/v1/me/avatar/icon", %{icon: "no-such-icon"}), 422)[
             "error"
           ] == "unknown_icon"

    # An icon, but not one the picker offers.
    refute "shield-check" in Icons.picks()

    assert json_response(post(authed, "/api/v1/me/avatar/icon", %{icon: "shield-check"}), 422)[
             "error"
           ] == "unknown_icon"

    assert json_response(
             post(authed, "/api/v1/me/avatar/icon", %{icon: another_pick(user), color: "plaid"}),
             422
           )["error"] == "unknown_color"

    assert json_response(post(authed, "/api/v1/me/avatar/icon", %{}), 422)["error"] ==
             "validation_failed"

    assert Accounts.get_user(user.id).profile_url == user.profile_url
  end

  # A provider's picture not mirrored yet shows as the id's icon; picking that
  # icon stores it, so the mirror never puts the provider's picture back.
  test "the icon shown in place of a provider's picture is stored when picked", %{
    authed: authed,
    user: user
  } do
    {:ok, user} = Accounts.update_user_avatar(user, "https://lh3.googleusercontent.com/a/x")
    shown = User.public_avatar_url(user)
    assert Icons.name(shown)

    assert json_response(
             post(authed, "/api/v1/me/avatar/icon", %{
               icon: Icons.name(shown),
               color: Icons.color(shown) || ""
             }),
             200
           )

    assert Accounts.get_user(user.id).profile_url == shown
  end

  test "a guest picks an icon too, and a visitor may not", %{conn: conn} do
    {:ok, guest} =
      Accounts.find_or_create_from_device("icon-device-#{System.unique_integer([:positive])}")

    icon = another_pick(guest)

    assert json_response(post(authed(conn, guest), "/api/v1/me/avatar/icon", %{icon: icon}), 200)[
             "data"
           ]["profile_url"] == "/icons/#{icon}.svg"

    assert json_response(post(conn, "/api/v1/me/avatar/icon", %{icon: icon}), 401)
  end
end
