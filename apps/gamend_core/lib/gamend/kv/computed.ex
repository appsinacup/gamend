defmodule Gamend.KV.Computed do
  @moduledoc """
  Rows the host computes: read like any row, stored nowhere.

  A page often draws more than what is stored: a level from the km banked, a
  track with what is owned and what waits. A client needs the same, live,
  and a second copy of it in a row would have to be kept in step with the
  first. A computed row is that value under a key of its own:

      config :gamend_core, :computed_rows, %{
        "pass" => %{value: {MyGame.Pass, :row}, from: ["progress", "sail_day"]}
      }

    * `value` is `{module, function}`, called with the scope asked for
      (`%{user_id: id | nil, lobby_id: id | nil, part: part | nil}`): a map
      is the row's value, anything else no row.
    * `from` lists the stored keys it is worked out from. A write or a delete
      of one, in the same scope, says the computed row moved.
    * `access`, where it is given, is the least a reader must be, in the
      words `before_kv_get` answers in (`:owner_only` and the like): the
      hook can close the row further, never open it. A row of what is
      only its owner's is that owner's on a host that says nothing.

  A key ending in `*` is a family of rows, one a part: a row per language
  worked out from that language's stored row.

      "word_pools:*" => %{value: {MyGame.WordPools, :row}, from: ["words:*"]}

  `word_pools:fr` is then `MyGame.WordPools.row/1` with `part: "fr"`, and a
  write of `words:fr` moves it, and only it. A `from` key with no `*` moves
  no row of a family: which part would it be? A key named whole wins over a
  family, and the longest prefix over a shorter one, as `kv_schemas`
  patterns do.

  `Gamend.KV.get/2` answers it, so the HTTP API and `kv:subscribe` do too,
  behind the same `before_kv_get` decision as a stored row. When it moves,
  everyone subscribed to it is told `{:kv_stale, %{key, user_id, lobby_id}}`
  on its topic (`Gamend.KV.subscribe/2`), after the write commits; the user
  channel then reads it once and pushes `kv_updated` (or `kv_deleted` where
  it is gone), so a client sees an ordinary row. Nobody subscribed, nothing
  computed.

  What it depends on outside the store (an inventory, a wallet) the host
  says itself: `Gamend.KV.refresh/2`.

  A computed key is never stored: a row written under it is never read.

  Core computes one row itself, `preferences`: what a page may set on the
  account (`Gamend.Accounts.Preferences.row/1`), its owner's only. A host's
  row under the same key replaces it.
  """

  @type scope :: %{
          user_id: String.t() | nil,
          lobby_id: String.t() | nil,
          part: String.t() | nil
        }

  @family "*"

  @core %{
    "preferences" => %{value: {Gamend.Accounts.Preferences, :row}, access: :owner_only}
  }

  @doc "Whether `key` is a computed row, one of a family's included."
  @spec computed?(String.t()) :: boolean()
  def computed?(key) when is_binary(key), do: find(key) != nil

  @doc """
  The computed row `key` in a scope: `{:ok, payload}`, `:error` where the host
  answers no row, `:not_computed` for a key that is stored.
  """
  @spec fetch(String.t(), String.t() | nil, String.t() | nil) ::
          {:ok, Gamend.KV.payload()} | :error | :not_computed
  def fetch(key, user_id, lobby_id) when is_binary(key) do
    case find(key) do
      {%{value: {mod, fun}}, part} when is_atom(mod) and is_atom(fun) ->
        case apply(mod, fun, [%{user_id: user_id, lobby_id: lobby_id, part: part}]) do
          %{} = value -> {:ok, %{value: value, metadata: %{}}}
          _none -> :error
        end

      _stored ->
        :not_computed
    end
  end

  @doc """
  The least a reader of `key` must be (`access`), `:public` for a computed
  row that names none and for a stored key.
  """
  @spec access(String.t()) :: atom()
  def access(key) when is_binary(key) do
    case find(key) do
      {%{access: access}, _part} when is_atom(access) -> access
      _none -> :public
    end
  end

  @doc "The computed rows worked out from the stored key `key`."
  @spec dependents(String.t()) :: [String.t()]
  def dependents(key) when is_binary(key) do
    for {computed, %{from: from}} <- rows(),
        is_list(from),
        source <- from,
        moved <- [moved_by(computed, source, key)],
        moved != nil,
        uniq: true,
        do: moved
  end

  # The row `key` names and its part: `{row, nil}` for a key of its own,
  # `{row, part}` for one of a family's; nil for a stored key.
  defp find(key) do
    rows = rows()

    case rows do
      %{^key => row} ->
        {row, nil}

      _none ->
        # The longest prefix wins, as `kv_schemas` patterns do.
        rows
        |> Enum.flat_map(fn {computed, row} ->
          with prefix when is_binary(prefix) <- family_prefix(computed),
               true <- String.starts_with?(key, prefix),
               part when part != "" <- String.replace_prefix(key, prefix, "") do
            [{byte_size(prefix), {row, part}}]
          else
            _not -> []
          end
        end)
        |> Enum.max_by(&elem(&1, 0), fn -> {0, nil} end)
        |> elem(1)
    end
  end

  # Which row of `computed` a write of `key` moves, where `source` is one of
  # what it is worked out from: the row itself for a source named whole, the
  # family's row of the same part for a source ending in `*`; nil for none.
  defp moved_by(computed, source, key) do
    case {family_prefix(computed), family_prefix(source)} do
      {nil, nil} ->
        if source == key, do: computed

      {prefix, from} when is_binary(prefix) and is_binary(from) ->
        part = String.replace_prefix(key, from, "")
        if String.starts_with?(key, from) and part != "", do: prefix <> part

      {nil, from} ->
        if String.starts_with?(key, from), do: computed

      {_family, nil} ->
        nil
    end
  end

  # What every key of a family starts with; nil for a key of its own.
  defp family_prefix(key) do
    if String.ends_with?(key, @family), do: String.replace_suffix(key, @family, "")
  end

  defp rows do
    case Application.get_env(:gamend_core, :computed_rows) do
      %{} = rows -> Map.merge(@core, rows)
      _none -> @core
    end
  end
end
