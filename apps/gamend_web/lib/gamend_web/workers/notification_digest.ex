defmodule GamendWeb.Workers.NotificationDigest do
  @moduledoc """
  Sends one user's digest of one group (`Gamend.Notifications.Digest`, which
  queues this job by name: core cannot build the site's links). The rows go
  only after the email went, so a failed send is retried with them all. A user
  who turned the group's email off meanwhile gets nothing, and the rows go.
  """

  use Oban.Worker,
    queue: :mailers,
    max_attempts: 5,
    unique: [period: 3600, fields: [:worker, :args]]

  alias Gamend.Accounts
  alias Gamend.Accounts.Preferences, as: AccountPreferences
  alias Gamend.Accounts.User
  alias Gamend.Accounts.UserNotifier
  alias Gamend.Notifications.Digest
  alias Gamend.Notifications.Preferences
  alias GamendWeb.NotificationEmail

  require Gamend.Notifications.NotificationChannel, as: NotificationChannel

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(60)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "group" => group}}) do
    items = Digest.items(user_id, group)
    user = Accounts.get_user(user_id)

    cond do
      items == [] ->
        :ok

      match?(%User{email: email} when is_binary(email), user) and
          Preferences.enabled?(user, group, NotificationChannel.email()) ->
        send_digest(user, group, items)

      true ->
        Digest.delete(items)
        :ok
    end
  end

  defp send_digest(user, group, items) do
    {subject, body} =
      NotificationEmail.in_locale(AccountPreferences.locale(user), fn ->
        {NotificationEmail.digest_subject(group, items),
         NotificationEmail.digest_body(user.id, group, items)}
      end)

    case UserNotifier.deliver_notification(
           user,
           subject,
           body,
           NotificationEmail.unsubscribe_url(user.id, group)
         ) do
      {:ok, _email} ->
        Digest.delete(items)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end
end
