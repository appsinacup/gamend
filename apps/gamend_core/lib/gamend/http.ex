defmodule Gamend.HTTP do
  @moduledoc """
  `Req` with the declared timeout and retries, for the calls core makes to other
  services while a player waits: payment receipt checks (Apple, Google Play,
  Steam), OAuth code exchanges, Google ID-token checks and avatar mirroring.

  Req's own defaults suit a script, not a request handler: 15 seconds a try
  and, for a GET, three retries with backoff, so one slow provider held a login
  or a purchase check open for about a minute. Here each try waits
  `client_timeout_ms` and a failed GET is retried `client_retries` times. A POST
  is not retried, as in Req.

  `get/2` and `post/2` take what `Req.get/2` and `Req.post/2` take, so this
  module drops in wherever a module takes an injectable HTTP client. Options a
  caller passes win over the declared ones.
  """

  use Gamend.Settings.Provider,
    app: :gamend_core,
    group: :http,
    label: "Server & HTTP"

  setting(:client_timeout_ms, :integer,
    default: 10_000,
    doc:
      "Per-try timeout for calls to payment, OAuth and avatar providers, in milliseconds: " <>
        "connecting, and waiting for the response."
  )

  setting(:client_retries, :integer,
    default: 1,
    doc: "Retries of a failed GET to a provider. POSTs are never retried. 0 disables."
  )

  @doc "`Req.get/2` with the declared timeout and retries."
  @spec get(String.t() | URI.t(), keyword()) :: {:ok, Req.Response.t()} | {:error, Exception.t()}
  def get(url, opts \\ []), do: Req.get(url, options(opts))

  @doc "`Req.post/2` with the declared timeout and retries."
  @spec post(String.t() | URI.t(), keyword()) :: {:ok, Req.Response.t()} | {:error, Exception.t()}
  def post(url, opts \\ []), do: Req.post(url, options(opts))

  @doc """
  The declared timeout and retry options, with `opts` over them.

  `config :gamend_core, Gamend.HTTP, req_options: [...]` is merged in too, so
  a test can route every provider call through a `Req.Test` stub. Empty in prod.
  """
  @spec options(keyword()) :: keyword()
  def options(opts \\ []) do
    timeout = max(Gamend.Settings.get(__MODULE__, :client_timeout_ms), 1)
    retries = max(Gamend.Settings.get(__MODULE__, :client_retries), 0)
    injected = Keyword.get(Application.get_env(:gamend_core, __MODULE__, []), :req_options, [])

    [receive_timeout: timeout, connect_options: [timeout: timeout], max_retries: retries]
    |> Keyword.merge(injected)
    |> Keyword.merge(opts)
  end
end
