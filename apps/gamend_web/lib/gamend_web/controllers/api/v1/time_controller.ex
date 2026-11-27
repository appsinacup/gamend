defmodule GamendWeb.Api.V1.TimeController do
  @moduledoc """
  The server's clock, so a client can render in server-time space instead of
  guessing from HTTP `Date` headers, which have one-second resolution, and the
  time zones a person picks from.

  Unauthenticated on purpose: a clock is not a secret, and a client needs it
  before it has finished signing in. Nor is the list of zones.
  """
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gamend.Accounts.TimeZone
  alias GamendWeb.Schemas.ServerTimeResponse
  alias GamendWeb.Schemas.TimeZonesResponse

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

  operation(:time_zones,
    operation_id: "list_time_zones",
    summary: "Time zones to pick from",
    description:
      "The IANA time zones the settings page's Notifications tab offers, sorted, `UTC` " <>
        "among them; the site shows each by its name. A client's picker sends one as " <>
        "`timezone` to `PUT /api/v1/me/notification_settings`, or `\"\"` for the device's.",
    responses: [
      ok: {"Time zones", "application/json", TimeZonesResponse}
    ]
  )

  def show(conn, _params), do: reply_data(conn, %{server_now: Gamend.Time.now_ms()})

  def time_zones(conn, _params), do: reply_data(conn, %{zones: TimeZone.names()})
end
