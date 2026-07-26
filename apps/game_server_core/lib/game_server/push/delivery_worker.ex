defmodule GameServer.Push.DeliveryWorker do
  @moduledoc """
  Delivers one push message to one token. One job per token is deliberate:
  FCM v1 and APNs are one-request-per-token anyway, and it buys exact
  per-token Oban retry/backoff — a half-delivered batch job would re-push
  duplicates on retry.

  Fires `after_push_sent` on every terminal outcome (delivered, token
  disabled, permanent failure, or retries exhausted) — never on a transient
  error that will retry.
  """

  use Oban.Worker, queue: :push, max_attempts: 5

  require Logger

  alias GameServer.Push
  alias GameServer.Push.Message
  alias GameServer.Push.PushToken
  alias GameServer.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"token_id" => token_id, "message" => message_map}} = job) do
    token = Repo.get(PushToken, token_id)

    if token == nil or token.disabled_at != nil do
      # Removed or disabled since enqueue (or by an earlier attempt).
      :ok
    else
      deliver(token, Message.from_map(message_map), message_map, job)
    end
  end

  defp deliver(token, message, message_map, job) do
    provider = Push.provider_for(token)

    case provider.deliver(message, token) do
      :ok ->
        Push.mark_token_used(token.token)
        notify_sent(token, message_map, "delivered", nil)
        :ok

      {:invalid, reason} ->
        Logger.info("[push] disabling dead token #{token.id} (#{inspect(reason)})")
        Push.disable_token(token.token)
        notify_sent(token, message_map, "invalid", reason)
        :ok

      {:error, :permanent, reason} ->
        Logger.error(
          "[push] permanent delivery error via #{inspect(provider)} for token " <>
            "#{token.id}: #{inspect(reason)} — check the provider configuration"
        )

        notify_sent(token, message_map, "failed", reason)
        {:cancel, reason}

      {:error, :transient, reason} ->
        if job.attempt >= job.max_attempts do
          notify_sent(token, message_map, "failed", reason)
        end

        {:error, reason}
    end
  end

  defp notify_sent(token, message_map, status, reason) do
    result = %{
      "token_id" => token.id,
      "platform" => token.platform,
      "provider" => token.provider,
      "status" => status,
      "reason" => if(reason, do: inspect(reason))
    }

    GameServer.Hooks.internal_call(:after_push_sent, [token.user_id, message_map, result])
  end
end
