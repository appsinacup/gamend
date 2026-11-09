defmodule GamendWeb.MountedRoutes do
  @moduledoc """
  What this server's router mounts, for the pages that link to one another.

  A host leaves a page out by not routing it (`except:` on the macros in
  `GamendWeb.Router.Shared`). Core's pages link to each other, so a link asks
  here first: it exists when its target does, and a host that routes its own
  page at that path keeps the link.

  The account settings page's tabs are not routes, so the macro records the
  ones a host left out in that route's metadata, read here the same way.

  Built once per router build, as `GamendWeb.LiveNav`'s table is.
  """

  @doc ~S|Whether the router has a GET route at exactly this path, such as `"/chat"`.|
  @spec mounted?(String.t()) :: boolean()
  def mounted?(path) when is_binary(path), do: MapSet.member?(table().paths, path)

  @doc "Whether the account settings page has this tab."
  @spec settings_tab?(String.t()) :: boolean()
  def settings_tab?(tab) when is_binary(tab), do: tab not in table().closed_tabs

  defp table do
    # The router the endpoint dispatches to (`GamendWeb.Endpoint`).
    router = Application.get_env(:gamend_web, :router, GamendWeb.Router)
    key = {__MODULE__, router, router.module_info(:md5)}

    case :persistent_term.get(key, nil) do
      nil ->
        table = build(router)
        :persistent_term.put(key, table)
        table

      table ->
        table
    end
  end

  defp build(router) do
    routes = Phoenix.Router.routes(router)

    %{
      paths: for(%{verb: :get, path: path} <- routes, into: MapSet.new(), do: path),
      closed_tabs: Enum.find_value(routes, [], &closed_tabs/1)
    }
  end

  defp closed_tabs(%{metadata: %{closed_tabs: tabs}}), do: tabs
  defp closed_tabs(_route), do: nil
end
