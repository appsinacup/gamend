defmodule GamendWeb.Api.V1.PaymentErrors do
  @moduledoc """
  The error answer for a failed payment call, shared by the checkout and
  webhook controllers. `Gamend.Payments` fails with an atom for every reason
  a client or a provider can act on, and its name is the code. The status is
  the one `GamendWeb.ErrorStatus` gives it, so its name rules hold here as in
  every controller:

  - `*_not_found` is 404, `already_*` and `*_already_*` 409;
  - `*_not_configured` is 503: the server, not the request, is missing
    something, and a provider retries a webhook later;
  - a reason the table lists has its status there.

  Payments' other reasons are what was wrong with the request or the
  provider's payload (`invalid_apple_jws`, `missing_purchase_token`,
  `not_refundable`), so a reason the table has no status for is 400 here
  rather than the 500 `GamendWeb.Reply.reply_reason/2` answers. A failed
  changeset is 422 `validation_failed`. A reason that is not an atom is an
  internal term, so it is logged and answered 400 `payment_failed` rather
  than shown.
  """

  import GamendWeb.ChangesetErrors, only: [unprocessable: 2]
  import GamendWeb.Reply

  require Logger

  @spec reply(Plug.Conn.t(), term()) :: Plug.Conn.t()
  def reply(conn, %Ecto.Changeset{} = changeset), do: unprocessable(conn, changeset)
  def reply(conn, {reason, _detail}) when is_atom(reason), do: reply(conn, reason)

  def reply(conn, reason) when is_atom(reason) and not is_nil(reason),
    do: reply_error(conn, GamendWeb.ErrorStatus.status(reason) || :bad_request, reason)

  def reply(conn, reason) do
    Logger.warning("payment call failed: #{inspect(reason)}")
    reply_error(conn, :bad_request, "payment_failed")
  end
end
