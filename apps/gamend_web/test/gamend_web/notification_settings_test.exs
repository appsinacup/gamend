defmodule GamendWeb.NotificationSettingsTest do
  @moduledoc """
  The web half of notification choices: the settings tab, the opt-in on the
  sign-up form, the email job and the unsubscribe link at its foot.
  """
  use GamendWeb.ConnCase, async: false
  use Oban.Testing, repo: Gamend.Repo

  import Phoenix.LiveViewTest
  import Gamend.AccountsFixtures
  import Swoosh.TestAssertions

  alias Gamend.Accounts
  alias Gamend.Accounts.TimeZone
  alias Gamend.Notifications
  alias Gamend.Notifications.Preferences
  alias GamendWeb.NotificationEmail
  alias GamendWeb.Workers.NotificationEmail, as: EmailWorker

  @streak %{
    key: "streak",
    label: "Streak about to end",
    defaults: %{"in_app" => true, "email" => false, "push" => false},
    signup: true
  }

  setup do
    old = Application.get_env(:gamend_core, :notification_groups)
    Application.put_env(:gamend_core, :notification_groups, [@streak])

    on_exit(fn ->
      if old,
        do: Application.put_env(:gamend_core, :notification_groups, old),
        else: Application.delete_env(:gamend_core, :notification_groups)
    end)

    :ok
  end

  defp reload(user), do: Gamend.Repo.get!(Accounts.User, user.id)

  # A fixture's confirmation email sits in the mailbox ahead of ours.
  defp flush_emails do
    receive do
      {:email, _email} -> flush_emails()
    after
      0 -> :ok
    end
  end

  describe "settings tab" do
    setup :register_and_log_in_user

    test "a box turns a group's channel on and off", %{conn: conn, user: user} do
      {:ok, lv, html} = live(conn, ~p"/users/settings?tab=notifications")
      assert html =~ "Streak about to end"
      assert html =~ "Friends and groups"
      assert has_element?(lv, "#notify-account-email[disabled]")

      lv |> element("#notify-streak-email") |> render_click()
      assert Preferences.enabled?(reload(user), "streak", "email")

      lv |> element("#notify-streak-email") |> render_click()
      refute Preferences.enabled?(reload(user), "streak", "email")
    end

    test "a time zone picked by hand is not replaced by the browser's", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings?tab=notifications")

      lv |> form("#notify-time-zone", %{"zone" => "Asia/Tokyo"}) |> render_change()
      assert TimeZone.of(reload(user)) == "Asia/Tokyo"

      # The next visit reports another zone; the pick stands.
      {:ok, _lv, _html} =
        conn
        |> put_connect_params(%{"timezone" => "Europe/Madrid"})
        |> live(~p"/users/settings?tab=notifications")

      assert TimeZone.of(reload(user)) == "Asia/Tokyo"
    end

    test "the switches turn everything off and back on", %{conn: conn, user: user} do
      {:ok, lv, _html} = live(conn, ~p"/users/settings?tab=notifications")

      lv |> element("#notify-off_all") |> render_click()
      assert Preferences.off?(reload(user), "off_all")
      assert render(lv) =~ "Turn notifications back on"

      lv |> element("#notify-off_all") |> render_click()
      refute Preferences.off?(reload(user), "off_all")
    end
  end

  describe "sign-up" do
    test "the email is offered unticked, and a tick opts in", %{conn: conn} do
      _existing = user_fixture()
      {:ok, lv, html} = live(conn, ~p"/users/register")
      assert html =~ "Email me: Streak about to end"
      refute has_element?(lv, "#registration-notify-streak[checked]")

      email = unique_user_email()

      # Typing re-renders the form; a ticked box must stay ticked.
      lv
      |> form("#registration_form", user: %{email: email})
      |> render_change(%{"notify" => %{"streak" => "true"}})

      assert has_element?(lv, "#registration-notify-streak[checked]")

      lv
      |> form("#registration_form", user: valid_user_attributes(email: email))
      |> render_submit(%{"notify" => %{"streak" => "true"}})

      user = Gamend.Repo.get_by!(Accounts.User, email: email)
      assert Preferences.enabled?(user, "streak", "email")
    end
  end

  describe "the email" do
    test "goes out with a one-click unsubscribe header" do
      user = user_fixture()
      {:ok, _user} = Preferences.put(user, "streak", "email", true)

      {:ok, _channels} =
        Notifications.notify(user.id, "streak", %{
          "title" => "Your streak ends tonight",
          "content" => "One test keeps it.",
          "url" => "/tests/daily"
        })

      assert [job] = all_enqueued(worker: EmailWorker)
      flush_emails()
      assert :ok = perform_job(EmailWorker, job.args)

      assert_email_sent(fn email ->
        assert email.subject == "Your streak ends tonight"
        assert email.text_body =~ "One test keeps it."
        assert email.text_body =~ "/tests/daily"
        assert email.text_body =~ "/notifications/unsubscribe/"
        assert email.headers["List-Unsubscribe-Post"] == "List-Unsubscribe=One-Click"
        assert email.headers["List-Unsubscribe"] =~ "/notifications/unsubscribe/"
      end)
    end

    test "is written in the reader's language" do
      user = user_fixture()
      {:ok, user} = Preferences.put(user, "streak", "email", true)
      {:ok, _user} = Gamend.Accounts.Preferences.update(user, &Map.put(&1, "locale", "xx"))
      {:ok, _channels} = Notifications.notify(user.id, "streak", %{"title" => "Hi"})

      assert [job] = all_enqueued(worker: EmailWorker)
      flush_emails()
      # An unknown locale falls back to the msgid, and still sends.
      assert :ok = perform_job(EmailWorker, job.args)
      assert_email_sent(fn email -> assert email.text_body =~ "Stop these emails" end)
    end

    test "is not sent after the user unsubscribed" do
      user = user_fixture()
      {:ok, _user} = Preferences.put(user, "streak", "email", true)
      {:ok, _channels} = Notifications.notify(user.id, "streak", %{"title" => "Hi"})
      {:ok, _user} = Preferences.put(user, "streak", "email", false)

      assert [job] = all_enqueued(worker: EmailWorker)
      flush_emails()
      assert :ok = perform_job(EmailWorker, job.args)
      refute_email_sent()
    end
  end

  describe "unsubscribe link" do
    setup do
      user = user_fixture()
      {:ok, user} = Preferences.put(user, "streak", "email", true)
      %{user: user, token: NotificationEmail.token(user.id, "streak")}
    end

    test "opening it changes nothing", %{conn: conn, user: user, token: token} do
      html = conn |> get(~p"/notifications/unsubscribe/#{token}") |> html_response(200)
      assert html =~ "Streak about to end"
      assert html =~ "Stop these emails"
      assert Preferences.enabled?(reload(user), "streak", "email")
    end

    test "the page's button stops the group", %{conn: conn, user: user, token: token} do
      conn = post(conn, ~p"/notifications/unsubscribe/#{token}", %{"scope" => "group"})
      assert redirected_to(conn) =~ "done=group"
      refute Preferences.enabled?(reload(user), "streak", "email")
    end

    test "a mail client's one-click post works without a session", %{user: user, token: token} do
      conn =
        build_conn()
        |> post("/notifications/unsubscribe/#{token}", %{"List-Unsubscribe" => "One-Click"})

      assert conn.status == 200
      refute Preferences.enabled?(reload(user), "streak", "email")
    end

    test "stop all email", %{conn: conn, user: user, token: token} do
      post(conn, ~p"/notifications/unsubscribe/#{token}", %{"scope" => "all"})
      assert Preferences.off?(reload(user), "off_email")
    end

    test "a forged token is refused", %{conn: conn} do
      assert conn |> get("/notifications/unsubscribe/nope") |> html_response(404) =~
               "This link does not work"

      assert build_conn() |> post("/notifications/unsubscribe/nope") |> Map.get(:status) == 404
    end
  end

  describe "notifications page" do
    setup :register_and_log_in_user

    test "a server notification links where it says", %{conn: conn, user: user} do
      {:ok, _} = Notifications.notify(user.id, "streak", %{"title" => "Hi", "url" => "/tests"})
      {:ok, _lv, html} = live(conn, ~p"/notifications")
      assert html =~ ~s(href="/tests")
    end

    test "links to the settings that choose them", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/notifications")

      assert has_element?(
               lv,
               ~s(#notification-settings[href="/users/settings?tab=notifications"])
             )
    end
  end
end
