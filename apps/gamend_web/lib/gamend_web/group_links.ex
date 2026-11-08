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

  require GamendWeb.SettingsTab, as: SettingsTab

  @doc """
  The full URL of an invite link's token, for an admin to copy: from a
  LiveView's socket, or a controller's conn (the API's `url`).
  """
  @spec join_url(Phoenix.LiveView.Socket.t() | Plug.Conn.t(), String.t()) :: String.t()
  def join_url(socket_or_conn, token) do
    path =
      String.replace(
        live_path(router(socket_or_conn), UserLive.GroupJoin, :show),
        ":token",
        token
      )

    Phoenix.VerifiedRoutes.unverified_url(socket_or_conn, path)
  end

  @doc "The path that opens one of the reader's groups."
  @spec group_path(Phoenix.LiveView.Socket.t(), String.t()) :: String.t()
  def group_path(socket, group_id) do
    case groups_path(socket) do
      nil -> "/users/settings?" <> URI.encode_query(tab: SettingsTab.groups(), group: group_id)
      path -> under(path, group_id)
    end
  end

  @doc """
  The reader's groups as a page of their own (`/users/groups`), as the
  routes are written; nil on a host without it, where they are the settings
  page's tab.
  """
  @spec groups_path(Phoenix.LiveView.Socket.t()) :: String.t() | nil
  def groups_path(socket), do: live_path(socket.router, UserLive.Groups, :index)

  @doc """
  One group's page under the groups page at `groups_path`: its ref
  (`<owner>/<slug>` or its id) as path segments, `/users/groups/ann/team`.
  """
  @spec under(String.t(), String.t()) :: String.t()
  def under(groups_path, ref) do
    segments =
      ref
      |> String.split("/")
      |> Enum.map_join("/", fn segment -> URI.encode(segment, &URI.char_unreserved?/1) end)

    String.trim_trailing(groups_path, "/") <> "/" <> segments
  end

  defp router(%Plug.Conn{} = conn), do: Phoenix.Controller.router_module(conn)
  defp router(socket), do: socket.router

  defp live_path(router, view, action) do
    Enum.find_value(Phoenix.Router.routes(router), fn
      %{path: path, metadata: %{phoenix_live_view: {^view, ^action, _opts, _extra}}} -> path
      _route -> nil
    end)
  end
end
