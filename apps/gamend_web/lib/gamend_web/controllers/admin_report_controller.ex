defmodule GamendWeb.AdminReportController do
  @moduledoc """
  The two report downloads the admin queue (`GamendWeb.AdminLive.Reports`)
  links to: a report's image, and a kind's export.

  Images are served from here, never from `/storage`: a screenshot can show
  anything on a reporter's screen, so only an admin reads one. Both routes sit
  behind `:require_admin_user`.
  """
  use GamendWeb, :controller

  alias Gamend.Reports
  alias GamendWeb.Reports.KindUI

  def attachment(conn, %{"id" => id, "index" => index}) do
    with %{} = report <- Reports.get(id),
         {n, ""} <- Integer.parse(index),
         {:ok, bytes, type} <- Reports.attachment(report, n) do
      conn
      |> put_resp_content_type(type, nil)
      |> put_resp_header("cache-control", "private, no-store")
      |> put_resp_header("x-content-type-options", "nosniff")
      |> send_resp(200, bytes)
    else
      _ -> send_resp(conn, 404, "")
    end
  end

  def export(conn, %{"kind" => key} = params) do
    ui = key |> Reports.kind() |> ui_of()
    filters = params |> Map.take(~w(status topic q subject_ref)) |> Map.put("kind", key)

    case KindUI.export?(ui) && ui.export(Reports.list(filters)) do
      {filename, type, body} ->
        send_download(conn, {:binary, IO.iodata_to_binary(body)},
          filename: filename,
          content_type: type
        )

      _ ->
        send_resp(conn, 404, "")
    end
  end

  defp ui_of(nil), do: nil
  defp ui_of(kind), do: Reports.ui(kind)
end
