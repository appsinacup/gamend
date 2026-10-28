defmodule GamendWeb.GroupLinks do
  @moduledoc """
  Where a group's pages are on this host, read off its router: the join
  page of an invite link (`GamendWeb.UserLive.GroupJoin`) and the reader's
  groups (`GamendWeb.UserLive.Groups` where the host has that page, the
  settings page's Groups tab otherwise). A host picks those paths in
  `gamend_authenticated_live_routes/2` (`groups: "/users/groups"` makes
  them `/users/groups` and `/users/groups/join/:token`), so the paths are
  looked up rather than written down twice.
  """

  alias GamendWeb.UserLive

  @doc "The full URL of an invite link's token, for an admin to copy."
  @spec join_url(Phoenix.LiveView.Socket.t(), String.t()) :: String.t()
  def join_url(socket, token) do
    path = String.replace(live_path(socket.router, UserLive.GroupJoin), ":token", token)
    Phoenix.VerifiedRoutes.unverified_url(socket, path)
  end

  @doc "The path that opens one of the reader's groups."
  @spec group_path(Phoenix.LiveView.Socket.t(), String.t()) :: String.t()
  def group_path(socket, group_id) do
    case live_path(socket.router, UserLive.Groups) do
      nil -> "/users/settings?" <> URI.encode_query(tab: "groups", group: group_id)
      path -> path <> "?" <> URI.encode_query(group: group_id)
    end
  end

  defp live_path(router, view) do
    Enum.find_value(Phoenix.Router.routes(router), fn
      %{path: path, metadata: %{phoenix_live_view: {^view, _action, _opts, _extra}}} -> path
      _route -> nil
    end)
  end
end
