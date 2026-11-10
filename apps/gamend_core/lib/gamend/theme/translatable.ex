defmodule Gamend.Theme.Translatable do
  @moduledoc """
  Which leaves of a theme config are text, and which are configuration.

  One list, used by both the renderer (`Gamend.Theme.JSONConfig`) and the
  extractor (`mix gamend.theme.extract`), so the strings a translator is shown
  and the strings the server translates cannot drift apart.

  This is also the guard that keeps configuration out of translations. The
  theme used to be one whole JSON file per locale, and a config field added to
  English never reached the other 29 — every one of them silently lost
  `theme_color`, so non-English visitors got the fallback colour. A key that
  is not on this list is configuration: it is never extracted, never
  translated, and cannot vary by locale.
  """

  @keys ~w(label title text tagline description alt cta subtitle question answer)

  @doc "Keys whose string values are user-facing text."
  @spec keys() :: [String.t()]
  def keys, do: @keys

  @doc "Whether a leaf at `key` holds text rather than configuration."
  @spec text?(String.t() | atom()) :: boolean()
  def text?(key) when is_atom(key), do: text?(Atom.to_string(key))
  def text?(key) when is_binary(key), do: key in @keys

  @doc """
  Walks a decoded theme config, applying `fun` to every translatable leaf and
  leaving everything else untouched.

  `fun` receives the string and returns its replacement, so the same traversal
  serves rendering (translate it) and extraction (collect it).
  """
  @spec walk(term(), (String.t() -> String.t())) :: term()
  def walk(value, fun) when is_function(fun, 1), do: do_walk(value, nil, fun)

  defp do_walk(map, _key, fun) when is_map(map) do
    Map.new(map, fn {key, value} -> {key, do_walk(value, key, fun)} end)
  end

  defp do_walk(list, key, fun) when is_list(list) do
    # A list carries its parent's key: `buttons` is a list of maps, but
    # `tags: ["a", "b"]` would be a list of strings under a text key.
    Enum.map(list, &do_walk(&1, key, fun))
  end

  defp do_walk(value, key, fun) when is_binary(value) do
    if translatable_text?(key, value), do: fun.(value), else: value
  end

  defp do_walk(value, _key, _fun), do: value

  # A value like `{Some.Module.function}` is a runtime template the renderer
  # substitutes, not prose. It sits under a text key (`label`) so the key check
  # alone lets it through — and it went out to translators as if it were a
  # caption. Localizing one breaks the substitution and the literal braces
  # render on the page.
  @template ~r/^\{[A-Za-z_][\w.]*\}$/

  defp translatable_text?(key, value) do
    text?(key) and String.trim(value) != "" and not Regex.match?(@template, String.trim(value))
  end

  @doc """
  Every translatable string in a decoded config, in document order, without
  duplicates. What the extractor writes into `theme.pot`.
  """
  @spec strings(term()) :: [String.t()]
  def strings(config) do
    {_walked, collected} =
      collect(config, nil, [])

    collected |> Enum.reverse() |> Enum.uniq()
  end

  defp collect(map, _key, acc) when is_map(map) do
    Enum.reduce(map, {map, acc}, fn {key, value}, {m, a} ->
      {_v, a} = collect(value, key, a)
      {m, a}
    end)
  end

  defp collect(list, key, acc) when is_list(list) do
    Enum.reduce(list, {list, acc}, fn value, {l, a} ->
      {_v, a} = collect(value, key, a)
      {l, a}
    end)
  end

  defp collect(value, key, acc) when is_binary(value) do
    # Same guard as do_walk/3: what the extractor collects and what the
    # renderer translates must be the same set, or a string reaches translators
    # that the server will never look up.
    if translatable_text?(key, value), do: {value, [value | acc]}, else: {value, acc}
  end

  defp collect(value, _key, acc), do: {value, acc}
end
