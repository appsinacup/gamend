defmodule Gamend.Reports.Kinds.Page do
  @moduledoc """
  The built-in report kind: something on a page is broken or looks wrong.

  The subject is the page's address as the reporter gave it, fragment
  dropped: the full URL the form fills in (`GamendWeb.Reports.PageSubject`),
  a pasted address bar, or a bare path. A URL on another site is kept too,
  since the report may well be about a link that leads there.

  The duplicates key is the page's path on this site, query dropped, so a
  full URL and a bare path for the same page are one report; an address on
  another site keys as itself.
  """

  @behaviour Gamend.Reports.Kind

  @max_path 500

  @impl true
  def key, do: "page"

  @impl true
  def topics, do: []

  @impl true
  def max_attachments, do: 3

  @impl true
  def description_required?(_topic), do: true

  @impl true
  def ui, do: GamendWeb.Reports.PageKind

  @impl true
  def cast(params, _context) do
    path =
      params
      |> get_in(["subject", "path"])
      |> normalize()

    case path do
      nil ->
        {:ok, %{subject_ref: nil, subject: %{}, data: %{}}}

      path when byte_size(path) > @max_path ->
        {:error, :path_too_long}

      path ->
        {:ok, %{subject_ref: ref(path), subject: %{"path" => path}, data: %{}}}
    end
  end

  defp normalize(value) when is_binary(value) do
    case value |> String.trim() |> strip_fragment() do
      "" -> nil
      page -> page
    end
  end

  defp normalize(_value), do: nil

  # This site's URL is keyed by its path; anything else by itself.
  defp local_path(page) do
    case URI.parse(page) do
      %URI{scheme: scheme} = uri when scheme in ["http", "https"] ->
        if same_host?(uri), do: uri.path || "/", else: page

      _ ->
        page
    end
  end

  defp same_host?(%URI{host: host}) when is_binary(host) do
    case Application.get_env(:gamend_web, GamendWeb.Endpoint, [])[:url] do
      url when is_list(url) -> Keyword.get(url, :host) in [host, nil]
      _ -> true
    end
  end

  defp same_host?(_uri), do: false

  defp strip_fragment(value), do: value |> String.split("#", parts: 2) |> hd()

  # The grouping key: the path without its query, capped to the column.
  defp ref(page) do
    page |> local_path() |> String.split("?", parts: 2) |> hd() |> String.slice(0, 255)
  end
end
