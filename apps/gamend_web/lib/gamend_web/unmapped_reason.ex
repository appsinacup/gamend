defmodule GamendWeb.UnmappedReason do
  @moduledoc """
  Raised by `GamendWeb.Reply.reply_reason/2` for an error reason with no
  status: an atom `GamendWeb.ErrorStatus` does not know, or a term that is not
  an atom at all. It is a bug in the server, so the client gets 500 and the
  log names the reason; the fix is a line in the table or a clause in the
  controller.
  """

  defexception [:reason, plug_status: 500]

  @impl true
  def message(%{reason: reason}) do
    "no status for error reason #{inspect(reason)}: add it to GamendWeb.ErrorStatus, " <>
      "or match it in the controller"
  end
end
