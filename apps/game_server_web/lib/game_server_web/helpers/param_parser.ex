defmodule GameServerWeb.Helpers.ParamParser do
  @moduledoc """
  Shared helpers for safely parsing controller parameters.

  Import into controllers that need safe integer parsing:

      import GameServerWeb.Helpers.ParamParser
  """

  @doc """
  Safely parse a value into a UUID id. Returns the UUID string or `nil`.

  ## Examples

      iex> parse_id("0198c0de-1234-7abc-8def-0123456789ab")
      "0198c0de-1234-7abc-8def-0123456789ab"
      iex> parse_id("abc")
      nil
      iex> parse_id(nil)
      nil
  """
  @spec parse_id(term()) :: Ecto.UUID.t() | nil
  def parse_id(val), do: GameServer.UUIDv7.cast_or_nil(val)

  @doc """
  Like `parse_id/1` but returns `{:ok, uuid}` or `:error`.
  """
  @spec parse_id!(term()) :: {:ok, Ecto.UUID.t()} | :error
  def parse_id!(val) do
    case parse_id(val) do
      nil -> :error
      uuid -> {:ok, uuid}
    end
  end

  @doc """
  Safely parse a value into an integer. Returns the integer or `nil`.

  Unlike `parse_id/1`, this accepts strings with trailing data because some
  filter endpoints historically used `Integer.parse/1` without requiring an
  exact match.
  """
  @spec parse_int(term()) :: integer() | nil
  def parse_int(nil), do: nil
  def parse_int(""), do: nil
  def parse_int(val) when is_integer(val), do: val

  def parse_int(val) when is_binary(val) do
    case Integer.parse(val) do
      {int, _rest} -> int
      :error -> nil
    end
  end

  def parse_int(_), do: nil

  @doc """
  Fetch a value from either string or atom keyed params.
  """
  @spec param_value(map(), String.t(), atom()) :: term()
  def param_value(params, string_key, atom_key) when is_map(params) do
    Map.get(params, string_key) || Map.get(params, atom_key)
  end

  @doc """
  Put a non-empty filter value into a map.
  """
  @spec maybe_put_filter(map(), atom() | String.t(), term()) :: map()
  def maybe_put_filter(filters, _key, nil), do: filters
  def maybe_put_filter(filters, _key, ""), do: filters
  def maybe_put_filter(filters, key, value), do: Map.put(filters, key, value)

  @doc """
  Put a non-empty filter value from params into a map using an atom key.
  """
  @spec maybe_put_param_filter(map(), atom(), map()) :: map()
  def maybe_put_param_filter(filters, key, params) when is_map(params) do
    maybe_put_filter(filters, key, param_value(params, Atom.to_string(key), key))
  end

  @spec maybe_put_string_filter(map(), atom() | String.t(), term()) :: map()
  def maybe_put_string_filter(filters, _key, nil), do: filters
  def maybe_put_string_filter(filters, _key, ""), do: filters

  def maybe_put_string_filter(filters, key, value) when is_binary(value),
    do: Map.put(filters, key, value)

  def maybe_put_string_filter(filters, _key, _value), do: filters

  @spec maybe_put_int_filter(map(), atom() | String.t(), term()) :: map()
  def maybe_put_int_filter(filters, key, value) do
    case parse_int(value) do
      nil -> filters
      int -> Map.put(filters, key, int)
    end
  end

  @spec maybe_put_bool_filter(map(), atom() | String.t(), term()) :: map()
  def maybe_put_bool_filter(filters, _key, nil), do: filters

  def maybe_put_bool_filter(filters, key, value) when is_boolean(value),
    do: Map.put(filters, key, value)

  def maybe_put_bool_filter(filters, key, value) when is_binary(value) do
    case String.downcase(value) do
      "true" -> Map.put(filters, key, true)
      "false" -> Map.put(filters, key, false)
      _ -> filters
    end
  end

  def maybe_put_bool_filter(filters, _key, _value), do: filters

  @spec maybe_put_string_opt(keyword(), atom(), term()) :: keyword()
  def maybe_put_string_opt(opts, _key, nil), do: opts
  def maybe_put_string_opt(opts, _key, ""), do: opts

  def maybe_put_string_opt(opts, key, value) when is_binary(value),
    do: Keyword.put(opts, key, value)

  def maybe_put_string_opt(opts, _key, _value), do: opts

  @spec maybe_put_int_opt(keyword(), atom(), term()) :: keyword()
  def maybe_put_int_opt(opts, key, value) do
    case parse_int(value) do
      nil -> opts
      int -> Keyword.put(opts, key, int)
    end
  end

  @spec maybe_put_bool_opt(keyword(), atom(), term()) :: keyword()
  def maybe_put_bool_opt(opts, _key, nil), do: opts

  def maybe_put_bool_opt(opts, key, value) when is_boolean(value),
    do: Keyword.put(opts, key, value)

  def maybe_put_bool_opt(opts, key, value) when is_binary(value) do
    case String.downcase(value) do
      "true" -> Keyword.put(opts, key, true)
      "false" -> Keyword.put(opts, key, false)
      _ -> opts
    end
  end

  def maybe_put_bool_opt(opts, _key, _value), do: opts
end
