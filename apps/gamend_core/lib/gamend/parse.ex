defmodule Gamend.Parse do
  @moduledoc """
  Parsing and normalizing values that arrive from outside: request bodies, form
  params, hook arguments, JSON.

  Strict means the whole value must be the thing. `"12abc"` is not 12. That is
  the difference from `GamendWeb.Helpers.ParamParser.parse_int/1`, which is
  deliberately lenient for filter params where a stray suffix should still
  narrow the list — for a value that gets *stored* (a score, a count, a
  quantity), accepting a prefix quietly writes a number nobody sent.

  It exists because there was no general home for this. The strict version
  lived in `Gamend.Payments.Params` under a payments name, so code outside
  payments either reached for `String.to_integer/1` — which raises, and turned
  `"score": "abc"` on the admin leaderboard API into a 500 — or wrote its own.
  """

  @doc """
  An integer, or a string that is exactly an integer (surrounding whitespace
  allowed). `nil` for anything else, including floats and partial numbers.
  """
  @spec integer(term()) :: integer() | nil
  def integer(value) when is_integer(value), do: value

  def integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} -> int
      _ -> nil
    end
  end

  def integer(_value), do: nil

  @doc """
  A UUID string, or `nil`: the 36-character hyphenated form only.

  `Ecto.UUID.cast/1` also takes any 16-byte binary as a raw UUID, so a
  16-character slug or name (`"weekend-gauntlet"`) cast to an id and its own
  lookup never ran. Ask this wherever a value may be an id or something else.
  """
  @spec uuid(term()) :: Ecto.UUID.t() | nil
  def uuid(value) when is_binary(value) and byte_size(value) == 36 do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> uuid
      :error -> nil
    end
  end

  def uuid(_value), do: nil

  @doc """
  A map with its atom keys turned into strings — the top level only.

  Attributes reach a context either atom-keyed (an internal call, a plugin) or
  string-keyed (a request), and `Ecto.Changeset.cast/3` rejects a mix of the
  two. Nested values are left alone: a `metadata` map is stored as given.
  Hooks and quests each carried a private copy.
  """
  @spec string_keys(map()) :: map()
  def string_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      pair -> pair
    end)
  end

  @doc """
  Like `string_keys/1`, but all the way down through nested maps and lists —
  for a provider payload read field by field, where a nested atom key would
  simply never match.
  """
  @spec string_keys_deep(term()) :: term()
  def string_keys_deep(%_{} = struct), do: struct

  def string_keys_deep(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), string_keys_deep(v)}
      {k, v} -> {k, string_keys_deep(v)}
    end)
  end

  def string_keys_deep(list) when is_list(list), do: Enum.map(list, &string_keys_deep/1)
  def string_keys_deep(value), do: value

  @doc "Like `integer/1`, with `default` in place of `nil`."
  @spec integer(term(), default) :: integer() | default when default: term()
  def integer(value, default) do
    case integer(value) do
      nil -> default
      int -> int
    end
  end

  @doc """
  `nil` for `nil` or `""`, the value otherwise -- what an optional filter from a
  form means when it is left empty. Not trimmed: a caller that wants
  `"  "` treated as blank trims first.

  Eleven admin LiveViews and two chat contexts each defined this privately.
  """
  @spec blank_to_nil(term()) :: term()
  def blank_to_nil(value) when value in [nil, ""], do: nil
  def blank_to_nil(value), do: value
end
