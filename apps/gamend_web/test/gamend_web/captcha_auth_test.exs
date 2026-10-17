defmodule GamendWeb.CaptchaAuthTest do
  @moduledoc """
  The captcha as the auth forms actually see it.

  `async: false` throughout: enabling the captcha is application env, which an
  async peer would read mid-run.
  """
  use GamendWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Gamend.AccountsFixtures

  alias Gamend.Accounts.User
  alias Gamend.Captcha
  alias Gamend.Repo

  setup do
    Application.put_env(:gamend_core, :captcha_req_options, plug: {Req.Test, __MODULE__})
    previous = Application.get_env(:gamend_core, Captcha)

    Application.put_env(:gamend_core, Captcha,
      enabled: true,
      site_key: "0x4AAAtest",
      secret_key: "secret"
    )

    # Both auth forms check the rate limit before the captcha, and the :auth
    # bucket is keyed by IP in a counter that outlives the test — every test in
    # the run submits from the same address, so the default budget of 10 is long
    # spent by the time these run and the rate limiter answers first. Lifting it
    # here keeps these tests about the captcha; the limiter has its own.
    previous_limit = Application.get_env(:gamend_web, GamendWeb.Plugs.RateLimiter, [])

    Application.put_env(
      :gamend_web,
      GamendWeb.Plugs.RateLimiter,
      Keyword.put(previous_limit, :auth_limit, 1_000_000)
    )

    on_exit(fn ->
      Application.delete_env(:gamend_core, :captcha_req_options)

      Application.put_env(
        :gamend_web,
        GamendWeb.Plugs.RateLimiter,
        previous_limit
      )

      if previous,
        do: Application.put_env(:gamend_core, Captcha, previous),
        else: Application.delete_env(:gamend_core, Captcha)
    end)

    :ok
  end

  defp accept_tokens do
    Req.Test.stub(__MODULE__, fn conn -> Req.Test.json(conn, %{"success" => true}) end)
  end

  defp reject_tokens do
    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{"success" => false, "error-codes" => ["invalid-input-response"]})
    end)
  end

  defp disable_captcha do
    Application.put_env(:gamend_core, Captcha, enabled: false)
  end

  describe "widget rendering" do
    test "the register form carries the widget and the configured sitekey", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/register")

      assert html =~ ~s(phx-hook="Captcha")
      assert html =~ "0x4AAAtest"
    end

    test "the magic-link form carries the widget", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/log_in")

      assert html =~ ~s(id="login_magic_captcha")
    end

    # Password login is deliberately left to the rate limiter, so a returning
    # player signing in with credentials never meets a captcha.
    test "the password form does not", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log_in")

      refute has_element?(lv, "#login_form_password [phx-hook='Captcha']")
    end

    test "nothing renders when the captcha is disabled", %{conn: conn} do
      disable_captcha()

      {:ok, _lv, html} = live(conn, ~p"/users/register")

      refute html =~ ~s(phx-hook="Captcha")
    end
  end

  describe "registration" do
    test "a valid token registers the account", %{conn: conn} do
      accept_tokens()
      _existing = user_fixture()
      email = unique_user_email()

      {:ok, lv, _html} = live(conn, ~p"/users/register")

      {:ok, _lv, html} =
        lv
        |> form("#registration_form", user: valid_user_attributes(email: email))
        |> render_submit(%{"cf-turnstile-response" => "good"})
        |> follow_redirect(conn, ~p"/users/log_in")

      assert html =~ "Account created. Check your email"
      assert Repo.get_by(User, email: email)
    end

    test "a rejected token creates no account and resets the widget", %{conn: conn} do
      reject_tokens()
      _existing = user_fixture()
      email = unique_user_email()

      {:ok, lv, _html} = live(conn, ~p"/users/register")

      html =
        lv
        |> form("#registration_form", user: valid_user_attributes(email: email))
        |> render_submit(%{"cf-turnstile-response" => "bad"})

      assert html =~ "Captcha check failed"
      refute Repo.get_by(User, email: email)
      assert_push_event(lv, "captcha:reset", %{})
    end

    # The submit that matters: a bot posting the form with no widget at all.
    test "a missing token creates no account", %{conn: conn} do
      accept_tokens()
      _existing = user_fixture()
      email = unique_user_email()

      {:ok, lv, _html} = live(conn, ~p"/users/register")

      html =
        lv
        |> form("#registration_form", user: valid_user_attributes(email: email))
        |> render_submit()

      assert html =~ "Please complete the captcha"
      refute Repo.get_by(User, email: email)
    end
  end

  describe "magic link" do
    setup do
      %{user: user_fixture()}
    end

    test "a valid token sends the login email", %{conn: conn, user: user} do
      accept_tokens()

      {:ok, lv, _html} = live(conn, ~p"/users/log_in")

      {:ok, _lv, html} =
        lv
        |> form("#login_form_magic", user: %{email: user.email})
        |> render_submit(%{"cf-turnstile-response" => "good"})
        |> follow_redirect(conn, ~p"/users/log_in")

      assert html =~ "If that email has an account, we sent it a login link."
    end

    test "a missing token sends nothing", %{conn: conn, user: user} do
      accept_tokens()

      {:ok, lv, _html} = live(conn, ~p"/users/log_in")

      html =
        lv
        |> form("#login_form_magic", user: %{email: user.email})
        |> render_submit()

      assert html =~ "Please complete the captcha"
    end

    # Fail-closed reaches the player as a retryable message, not a 500.
    test "an unreachable Cloudflare blocks the send and says so", %{conn: conn, user: user} do
      Req.Test.stub(__MODULE__, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      {:ok, lv, _html} = live(conn, ~p"/users/log_in")

      html =
        lv
        |> form("#login_form_magic", user: %{email: user.email})
        |> render_submit(%{"cf-turnstile-response" => "good"})

      assert html =~ "Could not reach the captcha service"
    end
  end

  describe "POST /api/v1/register" do
    defp api_register(conn, extra \\ %{}) do
      post(
        conn,
        ~p"/api/v1/register",
        Map.merge(
          %{"email" => unique_user_email()},
          extra
        )
      )
    end

    defp require_api_captcha do
      Application.put_env(
        :gamend_core,
        Captcha,
        Keyword.put(Application.get_env(:gamend_core, Captcha), :api_register, true)
      )
    end

    test "is left open while only the forms' captcha is on", %{conn: conn} do
      _admin = user_fixture()
      assert %{"data" => _} = conn |> api_register() |> json_response(201)
    end

    test "demands a token once api_register is on", %{conn: conn} do
      _admin = user_fixture()
      require_api_captcha()

      assert %{"error" => "captcha_required"} = conn |> api_register() |> json_response(403)
    end

    test "rejects a token Cloudflare refuses, and creates no account", %{conn: conn} do
      _admin = user_fixture()
      require_api_captcha()
      reject_tokens()
      email = unique_user_email()

      assert %{"error" => "captcha_invalid"} =
               conn
               |> api_register(%{"email" => email, "captcha_token" => "bad"})
               |> json_response(403)

      refute Repo.get_by(User, email: email)
    end

    test "registers with a good token", %{conn: conn} do
      _admin = user_fixture()
      require_api_captcha()
      accept_tokens()

      assert %{"data" => _} =
               conn |> api_register(%{"captcha_token" => "good"}) |> json_response(201)
    end
  end

  describe "content security policy" do
    test "names the widget origin in script-src and frame-src when enabled", %{conn: conn} do
      conn = get(conn, ~p"/users/register")
      [csp] = get_resp_header(conn, "content-security-policy")

      assert csp =~ ~r/script-src [^;]*https:\/\/challenges\.cloudflare\.com/
      assert csp =~ ~r/frame-src [^;]*https:\/\/challenges\.cloudflare\.com/

      # The widening is additive: what the policy already allowed still stands.
      assert csp =~ "'wasm-unsafe-eval'"
      assert csp =~ "default-src 'self'"
    end

    test "leaves the strict policy alone when disabled", %{conn: conn} do
      disable_captcha()

      conn = get(conn, ~p"/users/register")
      [csp] = get_resp_header(conn, "content-security-policy")

      refute csp =~ "challenges.cloudflare.com"
    end
  end
end
