defmodule Gamend.Captcha do
  @moduledoc """
  Human verification for the unauthenticated browser forms, via
  [Cloudflare Turnstile](https://developers.cloudflare.com/turnstile/).

  Off by default. It guards the two paths that mail an address the submitter
  chose — registration and the magic link — where the abuse is not "too many
  requests from one IP" (the rate limiter in `GamendWeb.LiveHelpers`
  already answers that) but a botnet spending our mail reputation an address
  at a time. Password login is deliberately *not* guarded: a captcha on every
  routine sign-in is friction for returning players, and the credentials are
  their own proof.

  `POST /api/v1/register` mails an address too, but a game client often has no
  browser to render the widget in, so turning the forms' captcha on leaves it
  alone. `api_register` puts it in front of the endpoint as well: the client
  then sends a Turnstile token as `captcha_token`, from a web export or a
  webview. Device login is never guarded.

  ## Setup

  Create a widget at <https://dash.cloudflare.com/?to=/:account/turnstile> —
  it is free with no request cap and no card — then set:

      GAMEND_CAPTCHA_ENABLED=true
      GAMEND_CAPTCHA_SITE_KEY=0x4AAA...
      GAMEND_CAPTCHA_SECRET_KEY=0x4AAA...

  Dev and test need none of that: with the keys unset we fall back to
  Cloudflare's published dummy pair, which passes on any host including
  localhost. That keeps the widget on the page in development, so a form that
  only breaks once a captcha is in front of it breaks on the developer's
  machine rather than in production. To exercise the failure path, set
  `GAMEND_CAPTCHA_SECRET_KEY` to the always-fails dummy,
  `2x0000000000000000000000000000000AA`.
  """

  use Gamend.Settings.Provider,
    app: :gamend_core,
    group: :captcha,
    label: "Captcha"

  require Logger

  @unknown "unknown"

  setting(:enabled, :boolean,
    default: false,
    doc: "Require a captcha on the register and magic-link forms."
  )

  setting(:api_register, :boolean,
    default: false,
    doc:
      "Also require a captcha token (`captcha_token`) on POST /api/v1/register. " <>
        "Needs `enabled`; a client that cannot render the widget cannot register."
  )

  setting(:site_key, :string,
    required: :warn,
    when: {[:captcha, :enabled], true},
    doc: "Turnstile sitekey (public, rendered into the page)."
  )

  setting(:secret_key, :string,
    secret: true,
    required: :prod,
    when: {[:captcha, :enabled], true},
    doc: "Turnstile secret key, for server-side verification."
  )

  setting(:timeout_ms, :integer,
    default: 5_000,
    doc: "How long to wait for Cloudflare before giving up on a verification."
  )

  # Cloudflare's documented dummy pair: valid on any hostname, always passes.
  # Used when the real keys are unset so dev and test work unconfigured.
  @test_site_key "1x00000000000000000000AA"
  @test_secret_key "1x0000000000000000000000000000000AA"

  @verify_url "https://challenges.cloudflare.com/turnstile/v0/siteverify"

  @typedoc "Why a token was rejected. `:missing` never reached Cloudflare."
  @type error :: :missing | :invalid | :unavailable

  @doc "Whether the register and magic-link forms require a captcha."
  @spec enabled?() :: boolean()
  def enabled?, do: Gamend.Settings.get(__MODULE__, :enabled) == true

  @doc "Whether `POST /api/v1/register` requires a captcha token too."
  @spec api_register?() :: boolean()
  def api_register?,
    do: enabled?() and Gamend.Settings.get(__MODULE__, :api_register) == true

  @doc """
  `verify/2` for `POST /api/v1/register`: `:ok` without a call unless
  `api_register?/0`.
  """
  @spec verify_api_register(term(), String.t() | nil) :: :ok | {:error, error()}
  def verify_api_register(token, remote_ip) do
    if api_register?(), do: verify(token, remote_ip), else: :ok
  end

  @doc "The sitekey to render, falling back to the always-passes dummy."
  @spec site_key() :: String.t()
  def site_key, do: presence(Gamend.Settings.get(__MODULE__, :site_key)) || @test_site_key

  @doc "The host the widget script is served from, for the browser CSP."
  @spec script_origin() :: String.t()
  def script_origin, do: "https://challenges.cloudflare.com"

  @doc """
  Verifies a widget token with Cloudflare.

  Returns `:ok` when the token is good, `{:error, reason}` otherwise. When
  the captcha is disabled this is `:ok` without a network call, so callers can
  gate unconditionally rather than branching on `enabled?/0` themselves.

  `remote_ip` is passed through to Cloudflare when known; `"unknown"` (what
  `GamendWeb.LiveHelpers.client_ip/2` returns with no known address) is
  omitted rather than sent as a literal.

  A token is single-use and expires after five minutes, so a rejected
  submission needs a fresh one — the caller resets the widget.
  """
  @spec verify(term(), String.t() | nil) :: :ok | {:error, error()}
  def verify(token, remote_ip \\ nil)

  def verify(token, remote_ip) do
    if enabled?() do
      do_verify(presence(token), remote_ip)
    else
      :ok
    end
  end

  defp do_verify(nil, _remote_ip), do: {:error, :missing}

  defp do_verify(token, remote_ip) do
    form = [secret: secret_key(), response: token] ++ remote_ip_param(remote_ip)

    case post(form) do
      {:ok, %Req.Response{status: 200, body: %{"success" => true}}} ->
        :ok

      {:ok, %Req.Response{status: 200, body: %{"success" => false} = body}} ->
        Logger.info("captcha rejected: #{inspect(body["error-codes"])}")
        {:error, :invalid}

      # Cloudflare unreachable or misbehaving. This is deliberately a failure:
      # treating it as a pass would make the protection removable by anyone who
      # can get between us and Cloudflare, which is exactly the attacker.
      other ->
        Logger.warning("captcha verification unavailable: #{inspect(other)}")
        {:error, :unavailable}
    end
  end

  defp post(form) do
    # `:captcha_req_options` lets tests inject a Req.Test plug; empty in prod.
    req_opts = Application.get_env(:gamend_core, :captcha_req_options, [])

    Req.post(
      @verify_url,
      [
        form: form,
        receive_timeout: Gamend.Settings.get(__MODULE__, :timeout_ms),
        retry: false
      ] ++ req_opts
    )
  rescue
    e -> {:error, e}
  end

  defp secret_key,
    do: presence(Gamend.Settings.get(__MODULE__, :secret_key)) || @test_secret_key

  defp remote_ip_param(ip) when is_binary(ip) and ip != "" and ip != @unknown,
    do: [remoteip: ip]

  defp remote_ip_param(_ip), do: []

  defp presence(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp presence(_value), do: nil
end
