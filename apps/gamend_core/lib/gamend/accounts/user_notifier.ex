defmodule Gamend.Accounts.UserNotifier do
  @moduledoc """
  Small helpers used to deliver transactional emails for the Accounts flow
  (confirmation, magic link, and email change instructions).

  These functions are thin wrappers over the configured application Mailer.
  """
  import Swoosh.Email

  alias Gamend.Accounts.User
  alias Gamend.Mailer
  require Logger

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from(sender_tuple())
      |> subject(subject)
      |> text_body(body)

    # Always protect delivery attempts so a missing/invalid Mailer or
    # transport doesn't crash live processes. Return {:ok, email} on
    # success and {:error, reason} otherwise.
    #
    # Log every failure here: most callers ignore the return value, so a
    # rejected relay or unverified sender domain is otherwise invisible.
    case deliver_bounded(email) do
      {:ok, _metadata} -> {:ok, email}
      other -> failed(subject, other)
    end
  end

  # gen_smtp waits up to 20 minutes for each reply from the relay, and that is
  # not configurable: a hung relay hung whatever sent the mail (a magic-link
  # request, an email change, a mail job) for that long. The send runs in a
  # task given `mail.send_timeout_ms`; what it raises or exits is caught inside
  # it, as the task is linked to the caller.
  defp deliver_bounded(email) do
    task =
      Task.async(fn ->
        try do
          Mailer.deliver(email)
        rescue
          e -> {:exception, e}
        catch
          kind, reason -> {kind, reason}
        end
      end)

    timeout = Gamend.Settings.get(Gamend.Mail, :send_timeout_ms)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      {:exit, reason} -> {:exit, reason}
      nil -> {:error, :timeout}
    end
  end

  defp failed(subject, reason) do
    Logger.error("mail delivery failed subject=#{inspect(subject)}: #{inspect(reason)}")
    {:error, reason}
  end

  # Build the sender {name, email} tuple from env or app config
  defp sender_tuple do
    name =
      Gamend.Settings.get(Gamend.Mail, :smtp_from_name)

    email =
      Gamend.Settings.get(Gamend.Mail, :smtp_from_email) ||
        Application.get_env(:gamend_core, :smtp_from_email)

    cond do
      is_binary(name) and name != "" and is_binary(email) and email != "" ->
        {name, email}

      is_binary(email) and email != "" ->
        {"Gamend", email}

      true ->
        {"Gamend", "contact@gamend.org"}
    end
  end

  @doc """
  Warn a user that their account will be deleted after `days` of inactivity.

  Sent by `Gamend.Accounts.InactivityNotifier` ahead of the retention
  sweep; signing in resets the clock, so the action the mail asks for is just
  "log in".
  """
  def deliver_inactivity_warning(%User{} = user, days) do
    deliver(user.email, "Your account is scheduled for deletion", """

    ==============================

    Hi #{user.email},

    Your account has been inactive for a while. Accounts untouched for #{days} days
    are deleted along with everything in them.

    To keep it, just sign in - that resets the clock and no further action is
    needed.

    If you would rather the account went away, you can ignore this email.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Update email instructions", """

    ==============================

    Hi #{user.email},

    You can change your email by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """)
  end

  @doc """
  Deliver instructions to log in with a magic link.
  """
  def deliver_login_instructions(user, url) do
    case user do
      %User{confirmed_at: nil} -> deliver_confirmation_instructions(user, url)
      _ -> deliver_magic_link_instructions(user, url)
    end
  end

  defp deliver_magic_link_instructions(user, url) do
    deliver(user.email, "Log in instructions", """

    ==============================

    Hi #{user.email},

    You can log into your account by visiting the URL below:

    #{url}

    If you didn't request this email, please ignore this.

    ==============================
    """)
  end

  def deliver_confirmation_instructions(user, url) do
    deliver(user.email, "Confirmation instructions", """

    ==============================

    Hi #{user.email},

    You can confirm your account by visiting the URL below:

    #{url}

    If you didn't create an account with us, please ignore this.

    ==============================
    """)
  end

  @doc """
  Send a simple test email to the given recipient address. Used by admin tools
  to verify SMTP configuration and delivery.
  Returns the same shape as `deliver/3`.
  """
  def deliver_test_email(recipient) when is_binary(recipient) do
    subject = "Gamend — test message"

    body = """

    This is a test message sent from the Gamend admin test-email tool.

    If you received this message your email delivery configuration is working.

    """

    deliver(recipient, subject, body)
  end

  @doc """
  Deliver a notification that the user's account has been activated by an admin.
  Silently returns `{:ok, :no_email}` if the user has no email address.
  """
  def deliver_account_activated(%User{email: email}) when is_binary(email) and email != "" do
    deliver(email, "Your account has been approved", """

    ==============================

    Hi #{email},

    Great news! Your account has been reviewed and approved by an administrator.

    You can now log in and start using the platform.

    ==============================
    """)
  end

  def deliver_account_activated(_user), do: {:ok, :no_email}
end
