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

  def export(conn, %{"key" => key}) do
    case Quests.get_quest_by_key(key) do
      %Quest{} = quest ->
        rows = Enum.map(Codes.all(quest.key), &row/1)

        send_download(
          conn,
          {:binary, IO.iodata_to_binary(["token,max_uses,uses,status\n", rows])},
          filename: "#{quest.key}-codes.csv",
          content_type: "text/csv"
        )

      nil ->
        send_resp(conn, 404, "")
    end
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
