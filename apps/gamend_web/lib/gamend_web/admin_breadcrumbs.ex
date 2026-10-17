defmodule GamendWeb.AdminBreadcrumbs do
  @moduledoc """
  The breadcrumb trail of an admin page (`/admin/...`), drawn by the layout
  shell when the host's page meta provider has none for it.

  Admin is tooling and never translated, so a crumb is its path segment in
  English: the dashboard's name for it where that differs (`kv` is "KV"),
  else the segment with its underscores as spaces and a capital first letter
  (`rate_limiting` is "Rate limiting"). Every crumb but the page's own links
  to its path, since each step of an admin page's path is an admin page too
  (`/admin/chat` above `/admin/chat/mutes`). A host's own admin pages get a
  trail the same way; its provider answers first, for one whose last step
  deserves a better name than its slug.
  """

  # The dashboard's buttons, where they say more than the segment does.
  @names %{
    "config" => "Configuration",
    "filter" => "Word filter",
    "geo" => "Geo traffic",
    "kv" => "KV",
    "oban" => "Jobs",
    "push" => "Push devices"
  }

  @doc """
  `[{"Home", "/"}, {"Admin", "/admin"}, …, {page, nil}]` for an admin path,
  `[]` for any other.
  """
  @spec trail(String.t()) :: [{String.t(), String.t() | nil}]
  def trail(path) when is_binary(path) do
    case String.split(path, "/", trim: true) do
      ["admin" | segments] ->
        crumbs =
          Enum.scan(segments, {"Admin", "/admin"}, fn segment, {_label, parent} ->
            {name(segment), parent <> "/" <> segment}
          end)

        {page, _path} = List.last(crumbs, {"Admin", "/admin"})
        steps = [{"Admin", "/admin"} | crumbs] |> Enum.drop(-1)

        [{"Home", "/"} | steps] ++ [{page, nil}]

      _ ->
        []
    end
  end

  def trail(_path), do: []

  @doc "The crumb for one admin path segment."
  @spec name(String.t()) :: String.t()
  def name(segment) do
    Map.get_lazy(@names, segment, fn ->
      segment |> String.replace(["_", "-"], " ") |> String.capitalize()
    end)
  end
end
