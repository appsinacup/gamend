defmodule GameServer.Push.Providers.FCM do
  @moduledoc """
  Firebase Cloud Messaging (HTTP v1) provider for Android and Web — and iOS
  relay, if a game prefers Firebase over APNs-direct — delivered through the
  `GameServer.Push.FCMDispatcher` Pigeon dispatcher, authenticated by the
  `GameServer.Push.Goth` worker.
  """

  @behaviour GameServer.Push.Provider

  alias GameServer.Push.FCMDispatcher
  alias Pigeon.FCM.Notification

  # The payload is size-checked before sending (below), so
  # :invalid_argument in practice means a malformed token.
  @invalid_responses [:unregistered, :invalid_argument]

  # Project/credential misconfiguration a retry cannot fix.
  @permanent_responses [:sender_id_mismatch, :third_party_auth_error, :permission_denied]

  # FCM caps a message at 4096 bytes and reports oversize as INVALID_ARGUMENT —
  # the same error as a malformed token. Rejecting oversize before the wire is
  # what keeps that ambiguity from soft-disabling a healthy token (individual
  # field caps can't guarantee this: title + body + data may combine past it).
  @max_payload_bytes 4000

  @impl true
  def deliver(message, token) do
    notification = build_notification(message, token)

    if payload_too_large?(notification) do
      {:error, :permanent, :payload_too_large}
    else
      FCMDispatcher
      |> Pigeon.push(notification)
      |> classify()
    end
  end

  defp payload_too_large?(notification) do
    payload = %{
      "notification" => notification.notification,
      "data" => notification.data,
      "android" => notification.android
    }

    byte_size(Jason.encode!(payload)) > @max_payload_bytes
  end

  @impl true
  def configured?, do: Process.whereis(FCMDispatcher) != nil

  @doc false
  def build_notification(message, token) do
    notification =
      %{
        "title" => message.title,
        "body" => message.body,
        "image" => message.image
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    {:token, token.token}
    |> Notification.new(notification, wire_data(message.data))
    |> put_android_options(message)
  end

  # FCM v1 requires string values in the data payload; non-strings are
  # JSON-encoded and clients decode them back.
  defp wire_data(nil), do: nil

  defp wire_data(data) do
    Map.new(data, fn {k, v} -> {to_string(k), stringify(v)} end)
  end

  defp stringify(value) when is_binary(value), do: value
  defp stringify(value), do: Jason.encode!(value)

  defp put_android_options(notification, message) do
    android =
      %{}
      |> maybe_put("collapse_key", message.collapse_key)
      |> maybe_put(
        "notification",
        if(message.sound, do: %{"sound" => message.sound}, else: nil)
      )

    if android == %{}, do: notification, else: %{notification | android: android}
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  @doc false
  @spec classify(Notification.t()) :: GameServer.Push.Provider.result()
  def classify(%Notification{response: :success}), do: :ok

  def classify(%Notification{response: response}) when response in @invalid_responses,
    do: {:invalid, response}

  def classify(%Notification{response: response}) when response in @permanent_responses,
    do: {:error, :permanent, response}

  def classify(%Notification{response: response}), do: {:error, :transient, response}
end
