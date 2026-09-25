defmodule GamendWeb.UserLive.RegistrationTest do
  use GamendWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Gamend.AccountsFixtures

  describe "Registration page" do
    test "renders registration page", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/users/register")

      assert html =~ "Register"
      assert html =~ "Log in"
    end

    test "redirects if already logged in", %{conn: conn} do
      result =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/register")
        |> follow_redirect(conn, ~p"/users/settings")

      assert {:ok, _conn} = result
    end

    test "renders errors for invalid data", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      result =
        lv
        |> element("#registration_form")
        |> render_change(user: %{"email" => "with spaces"})

      assert result =~ "Register"
      assert result =~ "must have the @ sign and no spaces"
    end
  end

  describe "register user" do
    test "first user is auto-confirmed and redirected to tokenized login", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      email = unique_user_email()
      form = form(lv, "#registration_form", user: valid_user_attributes(email: email))

      {:ok, _lv, html} = render_submit(form) |> follow_redirect(conn)

      assert html =~ "Log in"
      assert html =~ "Success."
    end

    test "creates account and redirects to login (non-first user)", %{conn: conn} do
      # ensure this is not the first user so email delivery is attempted
      _existing = user_fixture()

      {:ok, lv, _html} = live(conn, ~p"/users/register")

      email = unique_user_email()
      form = form(lv, "#registration_form", user: valid_user_attributes(email: email))

      {:ok, _lv, html} =
        render_submit(form)
        |> follow_redirect(conn, ~p"/users/log_in")

      assert html =~
               "Account created. Check your email"
    end

    test "renders errors for duplicated email", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      user = user_fixture(%{email: "test@email.com"})

      result =
        lv
        |> form("#registration_form",
          user: %{"email" => user.email}
        )
        |> render_submit()

      assert result =~ "has already been taken"
    end
  end

  describe "registration navigation" do
    test "redirects to login page when the Log in button is clicked", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      {:ok, _login_live, login_html} =
        lv
        |> element("main a", "Log in")
        |> render_click()
        |> follow_redirect(conn, ~p"/users/log_in")

      assert login_html =~ "Log in"
    end
  end
end

defmodule GamendWeb.UserLive.RegistrationDeliveryFailureTest do
  @moduledoc """
  The LiveView picks its notifier up from `:gamend_web, :user_notifier` at
  save time, so making delivery fail means swapping that global — which every
  registration submitted by a concurrently running test would then see too.
  Sync, and kept apart from `RegistrationTest` so the rest of it stays async.
  """
  use GamendWeb.ConnCase, async: false
  use Oban.Testing, repo: Gamend.Repo

  import Phoenix.LiveViewTest
  import Gamend.AccountsFixtures

  defmodule FailNotifier do
    def deliver_confirmation_instructions(_user, _url), do: {:error, :smtp_failed}
  end

  setup do
    prev = Application.get_env(:gamend_web, :user_notifier)
    Application.put_env(:gamend_web, :user_notifier, FailNotifier)

    on_exit(fn ->
      if prev,
        do: Application.put_env(:gamend_web, :user_notifier, prev),
        else: Application.delete_env(:gamend_web, :user_notifier)
    end)

    :ok
  end

  test "sign-up does not wait on the mail server; a failed send is left to the job", %{conn: conn} do
    # ensure this is not the first user so email delivery is attempted
    _existing = user_fixture()

    {:ok, lv, _html} = live(conn, ~p"/users/register")

    email = unique_user_email()
    form = form(lv, "#registration_form", user: valid_user_attributes(email: email))

    {:ok, _lv, html} = render_submit(form) |> follow_redirect(conn, ~p"/users/log_in")
    assert html =~ "Account created. Check your email"

    assert [job] = all_enqueued(worker: Gamend.Accounts.ConfirmationMailer)
    assert {:error, :smtp_failed} = perform_job(Gamend.Accounts.ConfirmationMailer, job.args)
    assert Gamend.Repo.get_by(Gamend.Accounts.User, email: email)
  end
end
