defmodule Gamend.Accounts.ConfirmationMailer do
  @moduledoc """
  Sends a new account's confirmation email, off the request.

  Registration enqueues this in the transaction that inserts the user, so a
  committed account always has its email queued and the transaction holds the
  database for two inserts rather than an SMTP conversation. On SQLite the
  repo has a single connection, and a registration that sent its mail inline
  stalled every other query in the server for the length of the SMTP session.

  The job mints the token itself: a token in the job's args would sit in the
  jobs table in the clear. A failed send is retried with backoff, minting a new
  token each attempt (the unused ones expire). A job that outlives `timeout/1`
  is killed, so a hung relay costs one `mailers` slot, never the database.
  """

  use Oban.Worker, queue: :mailers, max_attempts: 5

  alias Gamend.Accounts.{User, UserNotifier, UserToken}
  alias Gamend.Repo

  # Stands in for the token when the URL is built at enqueue time, where the
  # router is at hand; the job swaps in the real one. URL-safe, so a verified
  # route passes it through unencoded.
  @token "__gamend_confirm_token__"

  @doc """
  The job for `user`. `confirmation_url_fun` maps an encoded token to its URL
  and runs now, with a placeholder; `notifier` delivers.
  """
  @spec new_for(User.t(), (String.t() -> String.t()), module()) :: Ecto.Changeset.t()
  def new_for(%User{id: id}, confirmation_url_fun, notifier \\ UserNotifier)
      when is_function(confirmation_url_fun, 1) and is_atom(notifier) do
    url = confirmation_url_fun.(@token)

    unless String.contains?(url, @token) do
      raise ArgumentError, "confirmation URL #{inspect(url)} dropped its token"
    end

    new(%{"user_id" => id, "url" => url, "notifier" => Atom.to_string(notifier)})
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.seconds(60)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "url" => url, "notifier" => notifier}}) do
    # Straight from the table, not the user cache: a stale cached copy could
    # still read unconfirmed.
    case Repo.get(User, user_id) do
      %User{confirmed_at: nil, email: email} = user when is_binary(email) ->
        deliver(user, url, String.to_existing_atom(notifier))

      _gone_or_confirmed ->
        :ok
    end
  end

  defp deliver(user, url, notifier) do
    {encoded, user_token} = UserToken.build_email_token(user, "confirm")
    Repo.insert!(user_token)

    case notifier.deliver_confirmation_instructions(user, String.replace(url, @token, encoded)) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
