defmodule GamendWeb.PaymentDownloadController do
  use GamendWeb, :controller

  alias Gamend.Accounts.Scope
  alias Gamend.Payments

  require Gamend.Payments.GrantKey, as: GrantKey

  @file_key "file"

  def show(conn, %{"id" => id}) do
    user = Scope.user(conn.assigns.current_scope)

    with {:ok, entitlement_id} <- Ecto.UUID.cast(id),
         %{} = entitlement <- find_entitlement(user.id, entitlement_id),
         {:ok, path, filename} <- download_file(entitlement) do
      send_download(conn, {:file, path}, filename: filename)
    else
      _ ->
        conn
        |> put_status(:not_found)
        |> text("Not found")
    end
  end

  defp find_entitlement(user_id, entitlement_id) do
    user_id
    |> Payments.list_user_entitlements()
    |> Enum.find(&(&1.id == entitlement_id))
  end

  defp download_file(entitlement) do
    case download_config(entitlement) do
      %{} = download ->
        asset_key = map_value(download, "asset_key") || map_value(download, @file_key)
        filename = map_value(download, "filename") || asset_key

        with true <- is_binary(asset_key) and asset_key != "",
             true <- safe_basename?(asset_key),
             downloads_dir <- downloads_dir(),
             path <- Path.join(downloads_dir, asset_key),
             true <- File.regular?(path) do
          {:ok, path, filename || Path.basename(asset_key)}
        else
          _ -> {:error, :not_found}
        end

      _ ->
        {:error, :not_found}
    end
  end

  defp download_config(entitlement) do
    entitlement.metadata
    |> map_value(GrantKey.download())
    |> fallback(
      map_value(entitlement.product && entitlement.product.grant_config, GrantKey.download())
    )
    |> fallback(
      map_value(entitlement.product && entitlement.product.metadata, GrantKey.download())
    )
  end

  defp downloads_dir do
    Application.get_env(:gamend_web, :payment_downloads_dir) ||
      Application.app_dir(:gamend_web, "priv/downloads")
  end

  defp map_value(nil, _key), do: nil
  defp map_value(map, key) when is_map(map), do: map[key] || atom_map_value(map, key)
  defp map_value(_value, _key), do: nil

  defp atom_map_value(map, "asset_key"), do: map[:asset_key]
  defp atom_map_value(map, GrantKey.download()), do: map[:download]
  defp atom_map_value(map, @file_key), do: map[:file]
  defp atom_map_value(map, "filename"), do: map[:filename]
  defp atom_map_value(_map, _key), do: nil

  defp fallback(nil, value), do: value
  defp fallback(value, _fallback), do: value

  defp safe_basename?(asset_key), do: Path.basename(asset_key) == asset_key
end
