defmodule GameServerWeb.Pagination do
  @moduledoc """
  The one way list endpoints page: parse the window, build the meta.

  Every paginated response carries all six meta keys
  (`docs/specs/api-conventions.md`), so a client never has to branch on which
  endpoint it called:

      %{page: 1, page_size: 25, count: 25,
        total_count: 130, total_pages: 6, has_more: true}

  Four controllers used to hand-roll this with a private `parse_int/2` and a
  literal `min(size, 100)`, which silently ignored the configurable
  `max_page_size` limit and shipped metas of three, four and six keys. Both
  halves live here now, and `mix gamend.api.lint` (R7/R8) rejects a new copy.

  ## Usage

      {page, page_size} = Pagination.params(params)
      entries = Context.list(page: page, page_size: page_size)
      json(conn, Pagination.envelope(entries, page, page_size, total_count))
  """

  alias GameServer.Limits

  @type window :: {pos_integer(), pos_integer()}

  @doc """
  The requested page window, clamped to `[1, max_page_size]`.

  Reads string- or atom-keyed params, so it works on both a controller's
  `params` and an internal call.
  """
  @spec params(map()) :: window()
  def params(params) when is_map(params) do
    {
      Limits.clamp_page(value(params, "page", :page)),
      Limits.clamp_page_size(value(params, "page_size", :page_size))
    }
  end

  @doc "Pagination meta for one page of `count` entries out of `total_count`."
  @spec meta(integer(), integer(), integer(), integer()) :: map()
  def meta(page, page_size, count, total_count)
      when is_integer(page) and is_integer(page_size) do
    total_pages = if page_size > 0, do: div(total_count + page_size - 1, page_size), else: 0

    %{
      page: page,
      page_size: page_size,
      count: count,
      total_count: total_count,
      total_pages: total_pages,
      has_more: page < total_pages
    }
  end

  @doc """
  A complete list response: the entries under `data`, their window under `meta`.

  `count` is taken from `entries`, which is what it always means — how many
  came back on this page.
  """
  @spec envelope(list(), integer(), integer(), integer()) :: map()
  def envelope(entries, page, page_size, total_count) when is_list(entries) do
    %{data: entries, meta: meta(page, page_size, length(entries), total_count)}
  end

  defp value(params, string_key, atom_key) do
    Map.get(params, string_key) || Map.get(params, atom_key)
  end
end
