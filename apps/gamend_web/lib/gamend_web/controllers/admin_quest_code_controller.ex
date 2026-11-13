defmodule GamendWeb.AdminQuestCodeController do
  @moduledoc """
  The CSV the redemption codes page (`GamendWeb.AdminLive.QuestCodes`) links
  to, a controller because a LiveView cannot send a file. Behind
  `:require_admin_user`; a script pages through the JSON list instead.
  """
  use GamendWeb, :controller

  alias Gamend.Quests
  alias Gamend.Quests.Codes
  alias Gamend.Quests.Quest

  @rows_per_chunk 500

  def export(conn, %{"key" => key}) do
    case Quests.get_quest_by_key(key) do
      %Quest{} = quest ->
        send_csv(conn, "#{quest.key}-codes.csv", Codes.stream_all(quest.key))

      nil ->
        send_resp(conn, 404, "")
    end
  end

  # Sent as it is read, a few hundred rows a chunk: a quest with a few
  # hundred thousand codes never sits in memory whole. A browser that goes
  # away stops the read.
  defp send_csv(conn, filename, codes) do
    encoded = URI.encode(filename, &URI.char_unreserved?/1)

    conn =
      conn
      |> put_resp_content_type("text/csv")
      |> put_resp_header(
        "content-disposition",
        ~s(attachment; filename="#{encoded}"; filename*=utf-8''#{encoded})
      )
      |> send_chunked(200)

    ["token,max_uses,uses,status\n"]
    |> Stream.concat(Stream.map(codes, &row/1))
    |> Stream.chunk_every(@rows_per_chunk)
    |> Enum.reduce_while(conn, fn data, conn ->
      case chunk(conn, data) do
        {:ok, conn} -> {:cont, conn}
        {:error, _closed} -> {:halt, conn}
      end
    end)
  end

  defp row(code) do
    [
      csv(code.token),
      ",",
      to_string(code.max_uses),
      ",",
      to_string(code.uses),
      ",",
      code.status,
      "\n"
    ]
  end

  # A token an admin typed may hold a comma or a quote.
  defp csv(value) do
    if String.contains?(value, [",", "\"", "\n", "\r"]),
      do: ["\"", String.replace(value, "\"", "\"\""), "\""],
      else: value
  end
end
