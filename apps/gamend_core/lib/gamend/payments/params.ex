defmodule Gamend.Payments.Params do
  @moduledoc """
  Shape-wrangling shared by `Gamend.Payments` and its provider adapters.

  Every provider receives a JSON body from somewhere outside — Apple's signed
  notifications, Google's RTDN envelopes, Steam's form responses — and each one
  needed the same four things: string-keyed maps, an epoch-millis timestamp as
  an ISO-8601 string, a positive integer with a fallback, and a required
  non-empty string.

  So each one had them. `normalize_params/1` and its `normalize_nested/1`
  existed verbatim in four modules (Apple twice, once in `Apple.JWS`),
  `millis_to_iso8601/1` and `parse_positive_int/2` in two, `required_binary/2`
  in two. None of the copies had drifted yet, which is the only reason this is
  a tidy-up rather than a bug hunt.
  """

  @doc """
  Recursively string-keys a map, so a body that arrived as atoms and one that
  arrived as JSON can be read the same way.
  """
  @spec normalize(term()) :: term()
  defdelegate normalize(attrs), to: Gamend.Parse, as: :string_keys_deep

  @doc "An integer, or an integer written as a string. See `Gamend.Parse.integer/1`."
  @spec parse_int(term()) :: integer() | nil
  defdelegate parse_int(value), to: Gamend.Parse, as: :integer

  @doc "A positive integer, or `default` when the value is missing or not one."
  @spec parse_positive_int(term(), integer()) :: integer()
  def parse_positive_int(value, default) do
    case parse_int(value) do
      int when is_integer(int) and int > 0 -> int
      _ -> default
    end
  end

  @doc "Epoch milliseconds as an ISO-8601 string; `nil` when it is not one."
  @spec millis_to_iso8601(term()) :: String.t() | nil
  def millis_to_iso8601(nil), do: nil

  def millis_to_iso8601(value) do
    with int when is_integer(int) <- parse_int(value),
         {:ok, datetime} <- DateTime.from_unix(int, :millisecond) do
      DateTime.to_iso8601(datetime)
    else
      _ -> nil
    end
  end

  @doc """
  Fetches `key` as a non-empty string, or `{:error, :missing_<key>}`.
  """
  @spec required_binary(map(), String.t()) :: {:ok, String.t()} | {:error, atom()}
  def required_binary(map, key) do
    case map[key] do
      value when is_binary(value) and value != "" -> {:ok, value}
      # snake_case whatever the provider calls the field (`signedPayload`):
      # an error code is one (`GamendWeb.ResponseContract`).
      _ -> {:error, String.to_atom("missing_#{Macro.underscore(key)}")}
    end
  end

  @doc ~S"""
  Turns the literal `\n` sequences a PEM key picks up when it travels through an
  environment variable back into real newlines.
  """
  @spec normalize_private_key(String.t()) :: String.t()
  def normalize_private_key(value), do: String.replace(value, "\\n", "\n")

  @doc "A non-empty string, or an integer as its string, at `key`; `{:error, :missing_<key>}` otherwise."
  @spec required_value(map(), term()) :: {:ok, String.t()} | {:error, atom()}
  def required_value(map, key) do
    case Map.get(map, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      value when is_integer(value) -> {:ok, to_string(value)}
      # snake_case whatever the provider calls the field (`signedPayload`):
      # an error code is one (`GamendWeb.ResponseContract`).
      _ -> {:error, String.to_atom("missing_#{Macro.underscore(key)}")}
    end
  end

  @doc "Whether `value` is a non-empty string."
  @spec present?(term()) :: boolean()
  def present?(value), do: is_binary(value) and value != ""

  @doc "Puts `value` under `key` when `condition` is true and the value is a non-empty string."
  @spec put_if_present(map(), term(), term(), boolean()) :: map()
  def put_if_present(metadata, key, value, true) when is_binary(value) and value != "" do
    Map.put(metadata, key, value)
  end

  def put_if_present(metadata, _key, _value, _condition), do: metadata

  @doc "A stored provider payload with newer fields merged over it."
  @spec merge_payload(map(), map()) :: map()
  def merge_payload(existing, incoming) when is_map(existing) and is_map(incoming) do
    Map.merge(existing, incoming)
  end

  @doc "Epoch seconds (integer or string) as a second-precision `DateTime`; `nil` when it is not one."
  @spec unix_seconds_to_datetime(term()) :: DateTime.t() | nil
  def unix_seconds_to_datetime(value) when is_integer(value) do
    case DateTime.from_unix(value, :second) do
      {:ok, datetime} -> DateTime.truncate(datetime, :second)
      {:error, _reason} -> nil
    end
  end

  def unix_seconds_to_datetime(value) when is_binary(value) do
    value
    |> parse_int()
    |> unix_seconds_to_datetime()
  end

  def unix_seconds_to_datetime(_value), do: nil

  @doc "An ISO-8601 string, or a `DateTime`, as a second-precision `DateTime`; `nil` otherwise."
  @spec parse_datetime(term()) :: DateTime.t() | nil
  def parse_datetime(nil), do: nil
  def parse_datetime(%DateTime{} = dt), do: DateTime.truncate(dt, :second)

  def parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> DateTime.truncate(dt, :second)
      _ -> nil
    end
  end

  def parse_datetime(_value), do: nil

  @doc "A `DateTime` as ISO-8601; `nil` for anything else."
  @spec datetime_iso(term()) :: String.t() | nil
  def datetime_iso(%DateTime{} = value), do: DateTime.to_iso8601(value)
  def datetime_iso(_value), do: nil

  @doc "An ISO 4217 code in upper case."
  @spec normalize_currency(String.t() | nil) :: String.t() | nil
  def normalize_currency(nil), do: nil
  def normalize_currency(currency) when is_binary(currency), do: String.upcase(currency)

  # Amounts are kept in the currency's minor unit (Stripe's convention): 499
  # USD is 4.99. These are the currencies with no minor unit and with three.
  @zero_decimal_currencies ~w(BIF CLP DJF GNF JPY KMF KRW MGA PYG RWF UGX VND VUV XAF XOF XPF)
  @three_decimal_currencies ~w(BHD JOD KWD OMR TND)

  @doc "How many decimals `currency`'s minor unit has: 2 for most, 0 for JPY, 3 for KWD."
  @spec currency_decimals(String.t() | nil) :: 0 | 2 | 3
  def currency_decimals(currency) when is_binary(currency) do
    case String.upcase(currency) do
      code when code in @zero_decimal_currencies -> 0
      code when code in @three_decimal_currencies -> 3
      _code -> 2
    end
  end

  def currency_decimals(_currency), do: 2

  @doc """
  A price in milliunits (a thousandth of the currency's unit: Apple's
  `price`, 1990 for 1.99) in the currency's minor unit, rounded; nil when
  either is missing.
  """
  @spec milliunits_to_minor(term(), String.t() | nil) :: non_neg_integer() | nil
  def milliunits_to_minor(price, currency)
      when is_integer(price) and price >= 0 and is_binary(currency),
      do: round(price / Integer.pow(10, 3 - currency_decimals(currency)))

  def milliunits_to_minor(_price, _currency), do: nil
end
