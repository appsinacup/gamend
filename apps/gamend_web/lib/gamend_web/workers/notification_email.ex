defmodule GamendWeb.Workers.NotificationEmail do
  @moduledoc """
  Sends one notification by email, for `Gamend.Notifications.notify/3`
  (which queues this job by name: core cannot build the site's links).

  The user's choice is read again at send time, so an unsubscribe between
  queueing and sending is honoured. One email per user, group and subject an
  hour (`Gamend.Notifications`' `@email_unique`, set where the job is made). The footer is written in the language the user last
  read the site in (`Gamend.Accounts.Preferences.locale/1`); the subject and
  text are the caller's, already in it.
  """

  use Oban.Worker,
    queue: :mailers,
    max_attempts: 5,
    unique: [period: 3600, fields: [:worker, :args]]

  alias Gamend.Accounts
  alias Gamend.Accounts.Preferences, as: AccountPreferences
  alias Gamend.Accounts.User
  alias Gamend.Accounts.UserNotifier
  alias Gamend.Notifications.Preferences
  alias GamendWeb.NotificationEmail

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(60)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "group" => group} = args}) do
    with %User{email: email} = user when is_binary(email) <- Accounts.get_user(user_id),
         true <- Preferences.enabled?(user, group, "email") do
      body =
        in_locale(AccountPreferences.locale(user), fn ->
          NotificationEmail.body(user.id, group, args["text"] || "", args["url"])
        end)

      subject = args["subject"] || ""

      case UserNotifier.deliver_notification(
             user,
             subject,
             body,
             NotificationEmail.unsubscribe_url(user.id, group)
           ) do
        {:ok, _email} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      _gone_or_off -> :ok
    end
  end

  defp in_locale(locale, fun) when is_binary(locale),
    do: Gettext.with_locale(GamendWeb.GettextSync.host_backend(), locale, fun)

  defp in_locale(_locale, fun), do: fun.()
end
