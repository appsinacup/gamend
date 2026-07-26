defmodule GameServer.Push.Provider do
  @moduledoc """
  Behaviour for push delivery providers.

  Delivery is one message to one token (FCM v1 and APNs are both
  one-request-per-token), invoked from `GameServer.Push.DeliveryWorker`.
  Result meanings drive the worker's bookkeeping:

  - `:ok` – delivered; `last_used_at` is bumped.
  - `{:invalid, reason}` – the provider says this token is dead; it is
    soft-disabled.
  - `{:error, :transient, reason}` – worth retrying; the Oban job errors and
    backs off.
  - `{:error, :permanent, reason}` – a config/payload error retrying cannot
    fix; the job is cancelled and the reason logged.
  """

  alias GameServer.Push.Message
  alias GameServer.Push.PushToken

  @type result ::
          :ok
          | {:invalid, atom()}
          | {:error, :transient | :permanent, term()}

  @callback deliver(Message.t(), PushToken.t()) :: result()

  @doc "Whether the provider can deliver right now (credentials + process up)."
  @callback configured?() :: boolean()
end
