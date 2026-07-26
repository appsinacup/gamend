defmodule GameServer.Push.Providers.APNs do
  @moduledoc """
  APNs-direct provider for iOS, delivered through the
  `GameServer.Push.APNSDispatcher` Pigeon dispatcher (token-auth `.p8`,
  HTTP/2 over Mint). The `apns-topic` comes from `APNS_TOPIC`.
  """

  @behaviour GameServer.Push.Provider

  alias GameServer.Push.APNSDispatcher
  alias Pigeon.APNS.Notification

  # Token is gone or was never valid for this app: stop pushing to it.
  @invalid_responses [
    :bad_device_token,
    :unregistered,
    :device_token_not_for_topic,
    :expired_token
  ]

  # Config or payload errors a retry cannot fix. Everything else (timeouts,
  # 429/5xx-family, :expired_provider_token — Pigeon re-mints the JWT) is
  # transient and bounded by the worker's max_attempts.
  @permanent_responses [
    :bad_certificate,
    :bad_certificate_environment,
    :bad_collapse_id,
    :bad_expiration_date,
    :bad_message_id,
    :bad_path,
    :bad_priority,
    :bad_topic,
    :duplicate_headers,
    :forbidden,
    :invalid_provider_token,
    :invalid_push_type,
    :method_not_allowed,
    :missing_device_token,
    :missing_provider_token,
    :missing_topic,
    :payload_empty,
    :payload_too_large,
    :topic_disallowed
  ]

  @impl true
  def deliver(message, token) do
    notification = build_notification(message, token)

    APNSDispatcher
    |> Pigeon.push(notification)
    |> classify()
  end

  @impl true
  def configured?, do: Process.whereis(APNSDispatcher) != nil

  @doc false
  def build_notification(message, token) do
    alert =
      %{"title" => message.title, "body" => message.body}
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    custom = custom_data(message)

    alert
    |> Notification.new(token.token, topic())
    |> maybe(&Notification.put_badge/2, message.badge)
    |> maybe(&Notification.put_sound/2, message.sound)
    |> maybe(&Notification.put_custom/2, custom)
    |> struct(collapse_id: message.collapse_key)
  end

  # APNs has no first-class image field (rich media needs a client-side
  # notification service extension), so the URL rides in the custom payload.
  defp custom_data(message) do
    data = message.data || %{}
    data = if message.image, do: Map.put(data, "image", message.image), else: data
    if data == %{}, do: nil, else: data
  end

  defp maybe(notification, _fun, nil), do: notification
  defp maybe(notification, fun, value), do: fun.(notification, value)

  defp topic do
    Application.get_env(:game_server_core, GameServer.Push, [])[:apns_topic]
  end

  @doc false
  @spec classify(Notification.t()) :: GameServer.Push.Provider.result()
  def classify(%Notification{response: :success}), do: :ok

  def classify(%Notification{response: response}) when response in @invalid_responses,
    do: {:invalid, response}

  def classify(%Notification{response: response}) when response in @permanent_responses,
    do: {:error, :permanent, response}

  def classify(%Notification{response: response}), do: {:error, :transient, response}
end
