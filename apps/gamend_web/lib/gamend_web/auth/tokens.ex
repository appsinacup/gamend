defmodule GamendWeb.Auth.Tokens do
  @moduledoc """
  The tokens a sign-in answers, whatever it signed in with: email and
  password, a device, registration, or a provider. One place, so every
  sign-in carries the same `Session` and the same side effects.
  """

  alias Gamend.Accounts
  alias Gamend.Accounts.User
  alias GamendWeb.Auth.Guardian

  @doc """
  A new access and refresh token for `user`, as `GamendWeb.Schemas.Session`
  describes them, after the login side effects: `last_seen_at`, the
  `after_user_logged_in` hook and the `login` quest event.
  """
  @spec sign_in(User.t()) :: map()
  def sign_in(%User{} = user) do
    # `touch_last_seen/1` joins them rather than running inline: it is two more
    # writes (the `last_seen_at` update, and the activity-day insert behind it)
    # on a path that already wrote the user row, and both are fire-and-forget by
    # construction — nothing in the response depends on either. On SQLite's
    # single writer those writes were the difference between a login returning
    # and a login waiting, and signup throughput fell as concurrency rose
    # because of them. The work still happens, and still costs the same; the
    # caller no longer holds a connection while it does.
    #
    # Tests run `Gamend.Async` inline, so anything asserting on `last_seen_at`
    # straight after a login still sees it.
    Gamend.Async.run(fn ->
      Gamend.Accounts.touch_last_seen(user)
      Gamend.Hooks.internal_call(:after_user_logged_in, [user])
      Gamend.Quests.report_event(user.id, "login")
    end)

    {:ok, access_token, _} = Guardian.encode_and_sign(user, %{}, token_type: "access")
    {:ok, refresh_token, _} = Guardian.encode_and_sign(user, %{}, token_type: "refresh")

    session(user, access_token, refresh_token)
  end

  @doc """
  Why `user` may not sign in over the API, as `{status, code, message}` for
  `GamendWeb.Reply.reply_error/4`, or nil when they may. Every API sign-in
  asks before `sign_in/1`.

  An account scheduled for deletion is refused rather than restored: a game
  client signs in on its own (a stored device id, a silent provider login), and
  that must not undo a deletion its owner asked for. Signing in on the website
  is the way back (`GamendWeb.UserAuth.log_in_user/3`).
  """
  @spec refusal(User.t()) :: {atom(), String.t(), String.t()} | nil
  def refusal(%User{} = user) do
    cond do
      not Accounts.user_activated?(user) ->
        {:forbidden, "account_not_activated",
         "Your account is pending activation by an administrator."}

      Accounts.deletion_scheduled?(user) ->
        {:forbidden, "deletion_scheduled",
         "This account is scheduled for deletion. Sign in on the website to keep it."}

      true ->
        nil
    end
  end

  @doc "The `Session` fields for tokens already issued (a refresh keeps its refresh token)."
  @spec session(User.t(), String.t(), String.t()) :: map()
  def session(%User{} = user, access_token, refresh_token) do
    %{
      access_token: access_token,
      refresh_token: refresh_token,
      expires_in: access_ttl_seconds(),
      user_id: user.id,
      username: user.username || "",
      display_name: user.display_name || ""
    }
  end

  @doc """
  How long each token type lives, from `auth.access_token_ttl_minutes` and
  `auth.refresh_token_ttl_days`. `GamendWeb.Auth.Guardian` takes it as its
  `token_ttl`, so every token signed anywhere carries the same lifetime for
  its type.
  """
  @spec ttls() :: %{String.t() => {pos_integer(), :minutes | :days}}
  def ttls do
    %{"access" => {access_ttl_minutes(), :minutes}, "refresh" => {refresh_ttl_days(), :days}}
  end

  @doc "Seconds an access token issued now stays valid: the `expires_in` a sign-in answers."
  @spec access_ttl_seconds() :: pos_integer()
  def access_ttl_seconds, do: access_ttl_minutes() * 60

  # Floored at 1: zero or less would sign tokens that are expired on arrival,
  # locking every client out with nothing in the response saying why.
  defp access_ttl_minutes,
    do: max(Gamend.Settings.get(Gamend.Accounts, :access_token_ttl_minutes), 1)

  defp refresh_ttl_days, do: max(Gamend.Settings.get(Gamend.Accounts, :refresh_token_ttl_days), 1)
end
