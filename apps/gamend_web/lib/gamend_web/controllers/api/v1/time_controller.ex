defmodule GamendWeb.Api.V1.TimeController do
  @moduledoc """
  The server's clock, so a client can render in server-time space instead of
  guessing from HTTP `Date` headers, which have one-second resolution.

  Unauthenticated on purpose: a clock is not a secret, and a client needs it
  before it has finished signing in.
  """
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias GamendWeb.Schemas.ServerTimeResponse

  @get_server_time "get_server_time"

  tags(["Time"])

  operation(:show,
    operation_id: @get_server_time,
    summary: "Server clock",
    description:
      "Milliseconds since the Unix epoch. Sample a few times and average to " <>
        "estimate the offset; a single reading includes one-way network latency.",
    responses: [
      ok: {"Server time", "application/json", ServerTimeResponse}
    ]
  )

  def show(conn, _params), do: reply_data(conn, %{server_now: Gamend.Time.now_ms()})
end
