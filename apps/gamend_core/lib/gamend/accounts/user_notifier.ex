defmodule Gamend.Accounts.UserNotifier do
  @moduledoc """
  Every email core sends: the account's (confirmation, magic link, email
  change, codes, deletion warning) and the notifications a user chose to get
  by email. Each is a `Gamend.Mail.Message`, sent as plain text and, with the
  website there, as HTML in the site's one look (`GamendWeb.MailLayout`).
  Each send, and each failure, is recorded for the admin (`Gamend.Sent`),
  with its sign-in links and codes hidden.
  """
  import Swoosh.Email

  alias Gamend.Accounts.User
  alias Gamend.Mail.Message
  alias Gamend.Mailer
  alias Gamend.Sent
  require Logger

  require Gamend.Sent.SentKind, as: SentKind
  require Gamend.Sent.SentStatus, as: SentStatus

  # `recipient` is a user or a bare address (the admin's test email).
  # `secrets`: what the stored copy hides (a link that signs in).
  defp deliver(kind, recipient, subject, %Message{} = message, secrets \\ []) do
    {address, user_id} =
      case recipient do
        %User{email: email, id: id} -> {email, id}
        address -> {address, nil}
      end

    address
    |> compose(subject, message)
    |> send_email(subject)
    |> recorded(kind, address, subject, message, user_id: user_id, secrets: secrets)
  end

  defp recorded(result, kind, address, subject, message, opts) do
    status =
      case result do
        {:ok, _email} -> [status: SentStatus.sent()]
        {:error, reason} -> [status: SentStatus.failed(), reason: reason]
      end

    _ = Sent.record_email(kind, address, subject, message, opts ++ status)
    result
  end

  defp compose(recipient, subject, message) do
    email =
      new()
      |> to(recipient)
      |> from(sender_tuple())
      |> subject(subject)
      |> text_body(Message.to_text(message))

    case Message.to_html(message) do
      html when is_binary(html) -> html_body(email, html)
      nil -> email
    end
  end

  defp send_email(email, subject) do
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
  A notification the user chose to get by email
  (`Gamend.Notifications.notify/3`). `unsubscribe_url` is in the footer and
  in the `List-Unsubscribe` headers too (RFC 8058 one-click), so a mail
  client's own "Unsubscribe" button works without opening the site.
  """
  def deliver_notification(user, subject, message, unsubscribe_url, opts \\ [])

  def deliver_notification(
        %User{email: email} = user,
        subject,
        %Message{} = message,
        unsubscribe_url,
        opts
      )
      when is_binary(email) and is_binary(unsubscribe_url) do
    email
    |> compose(subject, message)
    |> header("List-Unsubscribe", "<#{unsubscribe_url}>")
    |> header("List-Unsubscribe-Post", "List-Unsubscribe=One-Click")
    |> send_email(subject)
    |> recorded(opts[:kind] || SentKind.notification(), email, subject, message,
      user_id: user.id,
      group: opts[:group],
      batch: opts[:batch],
      secrets: [unsubscribe_url]
    )
  end

  def deliver_notification(_user, _subject, _message, _url, _opts), do: {:ok, :no_email}

  @doc """
  Warn a user that their account will be deleted after `days` of inactivity.

  Sent by `Gamend.Accounts.InactivityNotifier` ahead of the retention
  sweep; signing in resets the clock, so the action the mail asks for is just
  "log in".
  """
  def deliver_inactivity_warning(%User{} = user, days) do
    deliver(SentKind.deletion_warning(), user, "Your account is scheduled for deletion", %Message{
      title: "Your account will be deleted",
      paragraphs: [
        "Your account has been inactive for a while. Accounts untouched for #{days} days " <>
          "are deleted along with everything in them.",
        "To keep it, just sign in. That resets the clock and nothing else is needed.",
        "If you would rather the account went away, you can ignore this email."
      ]
    })
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(
      SentKind.change_email(),
      user,
      "Update email instructions",
      %Message{
        title: "Change your email",
        paragraphs: ["Press the button to use this address for your account."],
        button: {"Change email", url},
        footer: ["If you didn't ask for this change, ignore this email."]
      },
      [url]
    )
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
    deliver(
      SentKind.login_link(),
      user,
      "Log in instructions",
      %Message{
        title: "Log in",
        paragraphs: ["Press the button to log in as #{user.email}."],
        button: {"Log in", url},
        footer: ["If you didn't ask for this email, ignore it."]
      },
      [url]
    )
  end

  @doc """
  Deliver the email that confirms an account: a link, and with `code` the
  same confirmation as six digits to type into the game. A magic link sent to
  an account not yet confirmed comes here too, with no code.
  """
  def deliver_confirmation_instructions(user, url, code \\ nil) do
    deliver(
      SentKind.confirm_account(),
      user,
      "Confirmation instructions",
      %Message{
        title: "Confirm your account",
        paragraphs:
          ["Press the button to confirm #{user.email}."] ++
            if(code,
              do: ["Or enter this code in the game, where you also choose your password:"],
              else: []
            ),
        button: {"Confirm account", url},
        code: code,
        footer: ["If you didn't create an account with us, ignore this email."]
      },
      [url]
    )
  end

  @doc """
  Deliver the six digits a game asks for to set a new password: a password
  forgotten, on a client with no page to open a link in.
  """
  def deliver_reset_code(user, code) do
    deliver(SentKind.password_code(), user, "Your code to set a new password", %Message{
      title: "Set a new password",
      paragraphs: ["Enter this code in the game, where you also choose your new password:"],
      code: code,
      footer: ["If you didn't ask for a new password, ignore this: your password stays as it is."]
    })
  end

  @doc """
  Deliver the six digits a game signs in with: the magic link of a client
  with no page to open a link in.
  """
  def deliver_login_code(user, code) do
    deliver(SentKind.login_code(), user, "Your code to log in", %Message{
      title: "Log in",
      paragraphs: ["Enter this code in the game to log in:"],
      code: code,
      footer: ["If you didn't ask to log in, ignore this: no one can log in without the code."]
    })
  end

  @doc """
  Send a simple test email to the given recipient address. Used by admin tools
  to verify SMTP configuration and delivery.
  Returns the same shape as `deliver/3`.
  """
  def deliver_test_email(recipient) when is_binary(recipient) do
    deliver(SentKind.test(), recipient, "Gamend — test message", %Message{
      title: "Test message",
      paragraphs: [
        "This is a test message sent from the admin test-email tool.",
        "If you got it, email delivery works."
      ]
    })
  end

  @doc """
  Deliver a notification that the user's account has been activated by an admin.
  Silently returns `{:ok, :no_email}` if the user has no email address.
  """
  def deliver_account_activated(%User{email: email} = user)
      when is_binary(email) and email != "" do
    deliver(SentKind.account_approved(), user, "Your account has been approved", %Message{
      title: "Your account is approved",
      paragraphs: [
        "An administrator reviewed and approved your account.",
        "You can now log in and start playing."
      ]
    })
  end

  def deliver_account_activated(_user), do: {:ok, :no_email}
end
