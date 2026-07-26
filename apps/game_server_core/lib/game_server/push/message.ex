defmodule GameServer.Push.Message do
  @moduledoc """
  A validated push message: what `GameServer.Push.send_to_user/3` accepts and
  what the delivery workers carry through job args.

  Fields:

  - `title` – required, capped by `max_push_title` **bytes**
  - `body` – optional, capped by `max_push_body` **bytes**
  - `data` – optional custom key/value map, serialized size capped by
    `max_push_data_size` bytes. FCM requires string values on the wire, so
    non-string values are JSON-encoded by the FCM provider; clients decode
    them back.

  Caps are bytes, not characters, because the provider limits are bytes (FCM
  and APNs both cap the payload at 4096) — a character cap would let multibyte
  text through validation only to fail on the wire.
  - `image` – optional image URL
  - `sound` – optional sound name
  - `badge` – optional iOS badge count
  - `collapse_key` – optional dedupe key (`apns-collapse-id` / FCM
    `collapse_key`), which is what makes an at-least-once redelivery invisible
    on-device
  """

  @enforce_keys [:title]
  defstruct [:title, :body, :data, :image, :sound, :badge, :collapse_key]

  @type t :: %__MODULE__{
          title: String.t(),
          body: String.t() | nil,
          data: map() | nil,
          image: String.t() | nil,
          sound: String.t() | nil,
          badge: non_neg_integer() | nil,
          collapse_key: String.t() | nil
        }

  @string_fields ~w(title body image sound collapse_key)a

  @doc """
  Build and validate a message from a map (string or atom keys).

  Returns `{:ok, %Message{}}` or `{:error, errors}` where `errors` maps a
  field to its problem, e.g. `%{title: "can't be blank"}`.
  """
  @spec new(map()) :: {:ok, t()} | {:error, %{atom() => String.t()}}
  def new(attrs) when is_map(attrs) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)

    message = %__MODULE__{
      title: attrs["title"],
      body: attrs["body"],
      data: attrs["data"],
      image: attrs["image"],
      sound: attrs["sound"],
      badge: attrs["badge"],
      collapse_key: attrs["collapse_key"]
    }

    case validate(message) do
      empty when empty == %{} -> {:ok, message}
      errors -> {:error, errors}
    end
  end

  defp validate(message) do
    %{}
    |> validate_title(message)
    |> validate_strings(message)
    |> validate_body(message)
    |> validate_data(message)
    |> validate_badge(message)
  end

  defp validate_title(errors, %{title: title}) do
    max = GameServer.Limits.get(:max_push_title)

    cond do
      title in [nil, ""] -> Map.put(errors, :title, "can't be blank")
      not is_binary(title) -> Map.put(errors, :title, "must be a string")
      byte_size(title) > max -> Map.put(errors, :title, "too long (max #{max} bytes)")
      true -> errors
    end
  end

  defp validate_strings(errors, message) do
    Enum.reduce(@string_fields -- [:title, :body], errors, fn field, acc ->
      case Map.fetch!(message, field) do
        nil -> acc
        value when is_binary(value) -> acc
        _ -> Map.put(acc, field, "must be a string")
      end
    end)
  end

  defp validate_body(errors, %{body: body}) do
    max = GameServer.Limits.get(:max_push_body)

    cond do
      body == nil -> errors
      not is_binary(body) -> Map.put(errors, :body, "must be a string")
      byte_size(body) > max -> Map.put(errors, :body, "too long (max #{max} bytes)")
      true -> errors
    end
  end

  defp validate_data(errors, %{data: data}) do
    max = GameServer.Limits.get(:max_push_data_size)

    cond do
      data == nil ->
        errors

      not is_map(data) ->
        Map.put(errors, :data, "must be a map")

      byte_size(Jason.encode!(data)) > max ->
        Map.put(errors, :data, "too large (max #{max} bytes)")

      true ->
        errors
    end
  end

  defp validate_badge(errors, %{badge: badge}) do
    if badge == nil or (is_integer(badge) and badge >= 0) do
      errors
    else
      Map.put(errors, :badge, "must be a non-negative integer")
    end
  end

  @doc """
  Truncate a UTF-8 string to at most `max_bytes` without splitting a
  character. For callers bridging longer content (notification bodies,
  personalized titles) into the push byte caps.
  """
  @spec truncate(String.t(), non_neg_integer()) :: String.t()
  def truncate(string, max_bytes) when is_binary(string) and is_integer(max_bytes) do
    if byte_size(string) <= max_bytes do
      string
    else
      string |> binary_part(0, max_bytes) |> trim_partial_char()
    end
  end

  defp trim_partial_char(<<>>), do: <<>>

  defp trim_partial_char(part) do
    if String.valid?(part) do
      part
    else
      trim_partial_char(binary_part(part, 0, byte_size(part) - 1))
    end
  end

  @doc "Serialize for Oban job args (string keys, nils dropped)."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = message) do
    message
    |> Map.from_struct()
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
  end

  @doc "Rebuild from job args. Args were validated at enqueue time."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    %__MODULE__{
      title: map["title"],
      body: map["body"],
      data: map["data"],
      image: map["image"],
      sound: map["sound"],
      badge: map["badge"],
      collapse_key: map["collapse_key"]
    }
  end
end
