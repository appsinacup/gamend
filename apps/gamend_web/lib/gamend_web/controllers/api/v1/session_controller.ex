defmodule GamendWeb.Api.V1.SessionController do
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gamend.Accounts
  alias Gamend.Captcha
  alias GamendWeb.Auth.Guardian
  alias GamendWeb.Auth.Tokens
  alias GamendWeb.Schemas
  alias GamendWeb.Schemas.{OkResponse, RegistrationResponse, SessionResponse}
  alias OpenApiSpex.Schema

  tags(["Authentication"])

  operation(:create,
    operation_id: "login",
    summary: "Login",
    description: "Authenticate user with email and password",
    request_body: {
      "Login credentials",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          email: %Schema{type: :string, format: :email, description: "User email"},
          password: %Schema{type: :string, format: :password, description: "User password"}
        },
        required: [:email, :password],
        example: %{
          email: "user@example.com",
          password: "securepassword123"
        }
      }
    },
    responses: [
      ok: {"Login successful", "application/json", SessionResponse},
      unauthorized: Schemas.error("Invalid credentials"),
      forbidden:
        Schemas.error(
          "The email is not confirmed yet (`email_not_confirmed`), the account awaits " <>
            "activation, or it is scheduled for deletion"
        ),
      too_many_requests:
        Schemas.error(
          "Too many failed passwords for this email: password sign-in is locked for the " <>
            "number of seconds in Retry-After (`account_locked`)"
        )
    ]
  )

  def create(conn, %{"email" => email, "password" => password}) do
    case Accounts.authenticate_by_password(email, password) do
      {:ok, user} ->
        case Tokens.refusal(user) do
          nil ->
            maybe_attach_device(conn, user)
            issue_tokens(conn, user)

          {status, code, message} ->
            reply_error(conn, status, code, message)
        end

      {:error, {:locked, seconds}} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(seconds))
        |> reply_error(
          :too_many_requests,
          "account_locked",
          "Too many failed sign-in attempts. Try again later, or sign in with an emailed link."
        )

      {:error, :email_not_confirmed} ->
        reply_error(
          conn,
          :forbidden,
          "email_not_confirmed",
          "Confirm your email address with the link we sent to it, then log in again. " <>
            "If the link has expired, sign in on the website with an emailed login link, " <>
            "then set a new password in your account settings."
        )

      {:error, :invalid_credentials} ->
        reply_error(conn, :unauthorized, "invalid_credentials", "Invalid email or password")
    end
  end

  operation(:register,
    operation_id: "register",
    summary: "Register",
    description:
      "Create an account with an email and queue its confirmation email, as browser " <>
        "sign-up does. The email carries a link and a six-digit code. Registering is not " <>
        "a sign-in: it answers the new account, never tokens. The password is chosen " <>
        "once the inbox is proved, with the code (`confirm_registration`, which also " <>
        "signs in), or in the settings the link opens. The response does not wait for " <>
        "the email, which is sent and " <>
        "retried in the background (`resend_confirmation` sends it again). The server's " <>
        "first account becomes the admin, and confirms with its email like any other. " <>
        "Account activation (`GAMEND_AUTH_REQUIRE_ACTIVATION`) applies at sign-in, as for " <>
        "every sign-up. When the server requires it (`GAMEND_CAPTCHA_API_REGISTER`), a " <>
        "Cloudflare Turnstile token goes in `captcha_token`.",
    request_body: {
      "Registration",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          email: %Schema{type: :string, format: :email, description: "User email"},
          username: %Schema{
            type: :string,
            description: "Optional; one is generated when it is left out"
          },
          captcha_token: %Schema{
            type: :string,
            description: "Turnstile token, when the server requires a captcha"
          }
        },
        required: [:email],
        example: %{email: "user@example.com"}
      }
    },
    responses: [
      created: {"Account created; not signed in", "application/json", RegistrationResponse},
      bad_request: Schemas.error("Email missing (missing_param)"),
      forbidden:
        Schemas.error(
          "The captcha failed, or a plugin refused the sign-up (registration_refused)"
        ),
      conflict: Schemas.error("Email or username already taken"),
      unprocessable_entity: Schemas.error("Invalid email or username"),
      service_unavailable: Schemas.error("The captcha check could not be completed")
    ]
  )

  def register(conn, %{"email" => email} = params) when is_binary(email) do
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()

    case Captcha.verify_api_register(params["captcha_token"], ip) do
      :ok ->
        params
        |> Map.take(["email", "username"])
        |> Accounts.register_unconfirmed_user_and_deliver(&confirm_url/1, notifier())
        |> registered(conn)

      {:error, :unavailable} ->
        reply_error(
          conn,
          :service_unavailable,
          "captcha_unavailable",
          "The captcha could not be verified, try again"
        )

      {:error, :missing} ->
        reply_error(conn, :forbidden, "captcha_required", "A captcha_token is required")

      {:error, :invalid} ->
        reply_error(conn, :forbidden, "captcha_invalid", "Captcha verification failed")
    end
  end

  def register(conn, _params) do
    reply_error(conn, :bad_request, "missing_param", "email is required")
  end

  operation(:confirm_registration,
    operation_id: "confirm_registration",
    summary: "Confirm a registration with its code",
    description:
      "Confirm the account `register` made with the six-digit code from its email, " <>
        "choose its password, and sign in: answers a session, as `login` does. The code " <>
        "proves the inbox, so this is where the password is set. Spaces and a dash in the " <>
        "code are ignored. A wrong, spent or expired code, an address with no account " <>
        "waiting, and one already confirmed all answer `401 invalid_code`. Wrong codes " <>
        "count toward the address's sign-in lockout, shared with passwords: the one that " <>
        "locks it answers `429 account_locked` and voids the code, so `resend_confirmation` " <>
        "sends a new one once the lock lifts; the link in the email keeps working. The " <>
        "password is checked before the code, so a refused one (`422`) costs no attempt. " <>
        "Signing in revokes every earlier token of the account.",
    request_body: {
      "Registration code",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          email: %Schema{type: :string, format: :email, description: "The address registered"},
          code: %Schema{type: :string, description: "The six digits from the email"},
          password: %Schema{
            type: :string,
            format: :password,
            description: "The account's password from now on"
          }
        },
        required: [:email, :code, :password],
        example: %{email: "user@example.com", code: "042137", password: "securepassword123"}
      }
    },
    responses: [
      ok: {"Confirmed and signed in", "application/json", SessionResponse},
      bad_request: Schemas.error("Email, code or password missing (missing_param)"),
      unauthorized: Schemas.error("Wrong, spent or expired code (invalid_code)"),
      forbidden:
        Schemas.error("Confirmed, but the account awaits activation or is scheduled for deletion"),
      unprocessable_entity: Schemas.error("The password is refused"),
      too_many_requests:
        Schemas.error("Too many wrong codes or passwords for this address (account_locked)")
    ]
  )

  def confirm_registration(conn, %{"email" => email, "code" => code, "password" => password})
      when is_binary(email) and is_binary(code) and is_binary(password) do
    case Accounts.confirm_user_by_code(email, code, password) do
      {:ok, {user, expired_tokens}} ->
        GamendWeb.UserAuth.disconnect_sessions(expired_tokens)

        case Tokens.refusal(user) do
          nil -> issue_tokens(conn, user)
          {status, error_code, message} -> reply_error(conn, status, error_code, message)
        end

      {:error, %Ecto.Changeset{} = changeset} ->
        unprocessable(conn, changeset)

      {:error, {:locked, seconds}} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(seconds))
        |> reply_error(
          :too_many_requests,
          "account_locked",
          "Too many wrong attempts. Try again later, or confirm with the link in the email."
        )

      {:error, :invalid_code} ->
        reply_error(conn, :unauthorized, "invalid_code", "Wrong or expired code")
    end
  end

  def confirm_registration(conn, _params) do
    reply_error(conn, :bad_request, "missing_param", "email, code and password are required")
  end

  operation(:resend_confirmation,
    operation_id: "resend_confirmation",
    summary: "Send the confirmation email again",
    description:
      "Queue a new confirmation email, with a new code, for the account `register` made " <>
        "and nobody has confirmed. Only the newest code works. Always answers " <>
        "`{\"ok\": true}`, whether or not the address has such an account, so it tells " <>
        "no one which addresses are registered; at most one email per account per minute " <>
        "goes out.",
    request_body: {
      "Address",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          email: %Schema{type: :string, format: :email, description: "The address registered"}
        },
        required: [:email],
        example: %{email: "user@example.com"}
      }
    },
    responses: [
      ok: {"Queued, if there was anything to send", "application/json", OkResponse},
      bad_request: Schemas.error("Email missing (missing_param)")
    ]
  )

  def resend_confirmation(conn, %{"email" => email}) when is_binary(email) do
    :ok = Accounts.resend_confirmation(email, &confirm_url/1, notifier())
    reply_ok(conn)
  end

  def resend_confirmation(conn, _params) do
    reply_error(conn, :bad_request, "missing_param", "email is required")
  end

  defp confirm_url(token), do: url(~p"/users/confirm/#{token}")

  # The notifier the browser sign-up reads, so both paths send one email.
  defp notifier,
    do: Application.get_env(:gamend_web, :user_notifier, Gamend.Accounts.UserNotifier)

  # Not a sign-in, unlike device login, which creates an account and signs it
  # in at once: registering proves nothing about the inbox, and a token here
  # would let anyone play as any address. The emailed code signs in, through
  # `confirm_registration/2`.
  defp registered({:ok, user}, conn) do
    reply_data(conn, :created, %{
      user_id: user.id,
      username: user.username || "",
      display_name: user.display_name || "",
      email_confirmed: not is_nil(user.confirmed_at)
    })
  end

  defp registered({:error, %Ecto.Changeset{} = changeset}, conn) do
    if taken?(changeset),
      do: uniqueness_conflict(conn, changeset),
      else: unprocessable(conn, changeset)
  end

  # A `before_user_register` plugin refused the sign-up. The email is queued,
  # never sent here, so it cannot fail this request.
  defp registered({:error, reason}, conn) do
    message = if is_binary(reason), do: reason, else: "The registration was refused"
    reply_error(conn, :forbidden, "registration_refused", message)
  end

  # An email or a username someone already has: 409, the input was fine.
  defp taken?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn {_field, {_message, opts}} ->
      opts[:constraint] == :unique or opts[:validation] == :unsafe_unique
    end)
  end

  operation(:create_device,
    operation_id: "device_login",
    summary: "Device login",
    description: "Authenticate or create a device-backed user using a device_id (no password).",
    request_body: {
      "Device login",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          device_id: %Schema{type: :string, description: "Device identifier string"}
        },
        required: [:device_id],
        example: %{device_id: "device:uuid-or-some-string"}
      }
    },
    responses: [
      ok: {"Login successful", "application/json", SessionResponse},
      bad_request: Schemas.error("Unable to create device user"),
      forbidden:
        Schemas.error(
          "Device auth disabled, or account awaiting activation or scheduled for deletion"
        )
    ]
  )

  # Device-based login: create or find a user for a given device_id and
  # return JWTs. This enables SDKs to authenticate with a simple device_id.
  # Device-specific login endpoint. This route accepts only a device_id
  # and returns JWT tokens for the device's user.
  def create_device(conn, %{"device_id" => device_id}) when is_binary(device_id) do
    if Accounts.device_auth_enabled?() do
      case Accounts.find_or_create_from_device(device_id) do
        {:ok, user} ->
          case Tokens.refusal(user) do
            nil -> issue_tokens(conn, user)
            {status, code, message} -> reply_error(conn, status, code, message)
          end

        {:error, changeset} ->
          unprocessable(conn, changeset)
      end
    else
      reply_error(conn, :forbidden, "device_auth_disabled", "Device login is disabled")
    end
  end

  operation(:delete,
    operation_id: "logout",
    summary: "Logout",
    description:
      "Revoke the caller's tokens. Send the access or refresh token in the " <>
        "Authorization header. This signs the account out on every device, because " <>
        "revocation works by bumping the account's token version. Always returns 200, " <>
        "so a client with an already-expired token can still complete sign-out.",
    parameters: [],
    responses: [
      ok: {"Logout successful", "application/json", OkResponse}
    ]
  )

  # Previously this returned `%{}` and did nothing at all, while its own
  # description claimed to invalidate the session — so a client that had
  # "logged out" kept a working access token, and its refresh token stayed
  # valid for 30 days.
  #
  # There is no per-token denylist to revoke against, so revocation is
  # `token_version`, which is account-wide. Callers are told that plainly above.
  # The route is unauthenticated, so the token is read here rather than by a
  # pipeline: sign-out must not fail merely because the token already expired.
  def delete(conn, _params) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, claims} <- Guardian.decode_and_verify(token),
         {:ok, user} <- Guardian.resource_from_claims(claims) do
      _ = Accounts.revoke_all_tokens(user)
    end

    reply_ok(conn)
  end

  operation(:refresh,
    operation_id: "refresh_token",
    summary: "Refresh access token",
    security: [],
    description: "Exchange a valid refresh token for a new access token",
    request_body: {
      "Refresh token",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          refresh_token: %Schema{type: :string, description: "Valid refresh token"}
        },
        required: [:refresh_token],
        example: %{
          refresh_token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
        }
      }
    },
    responses: [
      ok: {"Token refreshed successfully", "application/json", SessionResponse},
      unauthorized: Schemas.error("Invalid or expired refresh token"),
      bad_request: Schemas.error("Bad request")
    ]
  )

  def refresh(conn, %{"refresh_token" => refresh_token}) do
    # Verify the refresh token and check it's actually a refresh token type
    case Guardian.decode_and_verify(refresh_token, %{"typ" => "refresh"}) do
      {:ok, claims} ->
        case Guardian.resource_from_claims(claims) do
          {:ok, user} ->
            # Issue a new access token
            {:ok, new_access_token, _claims} =
              Guardian.encode_and_sign(user, %{}, token_type: "access")

            reply_data(conn, Tokens.session(user, new_access_token, refresh_token))

          {:error, _reason} ->
            reply_error(conn, :unauthorized, "invalid_refresh_token")
        end

      {:error, _reason} ->
        reply_error(
          conn,
          :unauthorized,
          "invalid_refresh_token",
          "Invalid or expired refresh token"
        )
    end
  end

  def refresh(conn, _params) do
    reply_error(conn, :bad_request, "missing_param", "refresh_token is required")
  end

  # Best-effort device attachment when device_id is provided during email login
  defp maybe_attach_device(conn, user) do
    with %{"device_id" => device_id} when is_binary(device_id) <- conn.body_params,
         true <- is_nil(user.device_id),
         true <- Accounts.device_auth_enabled?() do
      _ = Accounts.attach_device_to_user(user, device_id)
    end

    :ok
  end

  # Only real logins reach here (password, device and a registration's code;
  # registering is not one);
  # `refresh/2` keeps its refresh token. Provider sign-ins go through the same
  # `Tokens.sign_in/1`.
  defp issue_tokens(conn, user), do: reply_data(conn, Tokens.sign_in(user))
end
