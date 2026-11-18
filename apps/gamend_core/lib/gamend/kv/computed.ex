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
      (`%{user_id: id | nil, lobby_id: id | nil}`): a map is the row's value,
      anything else no row.
    * `from` lists the stored keys it is worked out from. A write or a delete
      of one, in the same scope, says the computed row moved.

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
  """

  @type scope :: %{user_id: String.t() | nil, lobby_id: String.t() | nil}

  @doc "Whether `key` is a computed row."
  @spec computed?(String.t()) :: boolean()
  def computed?(key) when is_binary(key), do: is_map_key(rows(), key)

  @doc """
  The computed row `key` in a scope: `{:ok, payload}`, `:error` where the host
  answers no row, `:not_computed` for a key that is stored.
  """
  @spec fetch(String.t(), String.t() | nil, String.t() | nil) ::
          {:ok, Gamend.KV.payload()} | :error | :not_computed
  def fetch(key, user_id, lobby_id) when is_binary(key) do
    case rows() do
      %{^key => %{value: {mod, fun}}} when is_atom(mod) and is_atom(fun) ->
        case apply(mod, fun, [%{user_id: user_id, lobby_id: lobby_id}]) do
          %{} = value -> {:ok, %{value: value, metadata: %{}}}
          _none -> :error
        end

      _stored ->
        :not_computed
    end
  end

  @doc "The computed rows worked out from the stored key `key`."
  @spec dependents(String.t()) :: [String.t()]
  def dependents(key) when is_binary(key) do
    for {computed, %{from: from}} <- rows(), is_list(from), key in from, do: computed
  end

  defp rows do
    case Application.get_env(:gamend_core, :computed_rows) do
      %{} = rows -> rows
      _none -> %{}
    end
  end
end
