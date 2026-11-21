defmodule GamendWeb.OAuthProviderToggleTest do
  @moduledoc """
  Provider availability as buttons, routes, and the discovery endpoint see it.

  `async: false`: provider configuration is application env.
  """
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Gamend.OAuth.Providers

  setup do
    orig = Application.get_env(:gamend_core, Providers)

    on_exit(fn ->
      if is_nil(orig) do
        Application.delete_env(:gamend_core, Providers)
      else
        Application.put_env(:gamend_core, Providers, orig)
      end
    end)

    :ok
  end

  defp configure(settings), do: Application.put_env(:gamend_core, Providers, settings)

  describe "Providers.enabled?/1" do
    test "false without credentials" do
      configure([])

      refute Providers.enabled?(:discord)
      assert Providers.enabled() == []
    end

    test "true once the presence key is set, in display order" do
      configure(discord_client_id: "id", github_client_id: "id", steam_api_key: "key")

      assert Providers.enabled() == [:discord, :github, :steam]
    end

    test "an explicit disable wins over credentials" do
      configure(discord_client_id: "id", discord_enabled: false)

      refute Providers.enabled?(:discord)
    end

    test "unknown providers are never enabled" do
      refute Providers.enabled?(:twitch)
    end
  end

  describe "sign-in buttons" do
    test "render only the enabled providers", %{conn: conn} do
      configure(discord_client_id: "id", google_client_id: "id")

      {:ok, _lv, html} = live(conn, ~p"/users/register")

      assert html =~ "/auth/discord"
      assert html =~ "/auth/google"
      refute html =~ "/auth/steam"
    end

    test "name the provider, so the row is not one word repeated", %{conn: conn} do
      configure(discord_client_id: "id", google_client_id: "id")

      {:ok, _lv, html} = live(conn, ~p"/users/log_in")
      assert html =~ "Log in with Discord"
      assert html =~ "Log in with Google"

      {:ok, _lv, html} = live(conn, ~p"/users/register")
      assert html =~ "Register with Discord"
    end

    test "no providers, no divider", %{conn: conn} do
      configure([])

      {:ok, _lv, html} = live(conn, ~p"/users/log_in")

      refute html =~ "/auth/discord"
    end
  end

  describe "route gating" do
    test "a disabled provider's browser route is a 404", %{conn: conn} do
      configure(discord_client_id: "id", discord_enabled: false)

      assert_error_sent 404, fn -> get(conn, "/auth/discord") end
    end

    test "an unconfigured provider's API route is a 404", %{conn: conn} do
      configure([])

      assert_error_sent 404, fn -> get(conn, "/api/v1/auth/steam") end
    end

    test "an unknown provider is a 404, not a crash", %{conn: conn} do
      configure([])

      # Not one of the path's documented providers (`RequestContract`).
      assert %{"error" => "not_found"} = conn |> get("/api/v1/auth/twitch") |> json_response(404)
    end

    test "an enabled provider still works", %{conn: conn} do
      configure(discord_client_id: "cid-999", discord_client_secret: "s")

      conn = get(conn, "/auth/discord")

      assert redirected_to(conn) =~ "discord.com"
    end
  end

  describe "GET /api/v1/auth/providers" do
    test "lists what is enabled", %{conn: conn} do
      configure(discord_client_id: "id", steam_api_key: "key", steam_enabled: false)

      conn = get(conn, "/api/v1/auth/providers")

      assert json_response(conn, 200) == %{"data" => ["discord"]}
    end

    test "empty when nothing is configured", %{conn: conn} do
      configure([])

      conn = get(conn, "/api/v1/auth/providers")

      assert json_response(conn, 200) == %{"data" => []}
    end
  end
end
