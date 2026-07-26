defmodule GameServer.Accounts.UserNotifier do
  @moduledoc """
  Small helpers used to deliver transactional emails for the Accounts flow
  (confirmation, magic link, and email change instructions).

  These functions are thin wrappers over the configured application Mailer.
  """
  import Swoosh.Email

  alias GameServer.Accounts.User
  alias GameServer.Mailer

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
    try do
      case Mailer.deliver(email) do
        {:ok, _metadata} -> {:ok, email}
        other -> {:error, other}
      end
    rescue
      e ->
        {:error, {:exception, e}}
    catch
      kind, reason ->
        {:error, {kind, reason}}
    end
  end

  # Build the sender {name, email} tuple from env or app config
  defp sender_tuple do
    name =
      GameServer.Settings.get(GameServer.Mail, :smtp_from_name)

    email =
      GameServer.Settings.get(GameServer.Mail, :smtp_from_email) ||
        Application.get_env(:game_server_core, :smtp_from_email)

    cond do
      is_binary(name) and name != "" and is_binary(email) and email != "" ->
        {name, email}

      is_binary(email) and email != "" ->
        {"GameServer", email}

      true ->
        {"GameServer", "contact@gamend.appsinacup.com"}
    end
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
    subject = "GameServer — test message"

    body = """

    This is a test message sent from the GameServer admin test-email tool.

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
