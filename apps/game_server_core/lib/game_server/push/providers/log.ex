defmodule GameServer.Push.Providers.Log do
  @moduledoc """
  Zero-config default provider: logs each delivery instead of calling out —
  the `Storage.Local` of push. Every token routed here (nothing configured,
  `PUSH_ADAPTER=log`, or a provider whose dispatcher is down) reports success,
  so the whole flow is exercisable with no credentials.
  """

  @behaviour GameServer.Push.Provider

  require Logger

  @impl true
  def deliver(message, token) do
    Logger.info(
      "[push] log provider: to=#{token.platform}/#{token.provider} " <>
        "token=#{String.slice(token.token, 0, 12)}… title=#{inspect(message.title)}"
    )

    :ok
  end

  @impl true
  def configured?, do: true
end
