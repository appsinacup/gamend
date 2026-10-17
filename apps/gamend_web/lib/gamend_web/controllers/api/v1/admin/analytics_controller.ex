defmodule GamendWeb.Api.V1.Admin.AnalyticsController do
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gamend.Analytics
  alias GamendWeb.Schemas

  alias GamendWeb.Schemas.{
    AnalyticsCountsResponse,
    AnalyticsDailyResponse,
    AnalyticsEconomyResponse,
    AnalyticsSummaryResponse,
    ServerStatsResponse
  }

  alias OpenApiSpex.Schema

  tags(["Admin – Analytics"])

  @segment_param [
    in: :query,
    schema: %Schema{type: :string, enum: ["all", "registered", "guest"], default: "all"},
    description:
      "Which accounts: registered (an email or a provider), guest (a device or a browser only) or all"
  ]

  operation(:show,
    operation_id: "admin_get_analytics_summary",
    summary: "DAU / WAU / MAU, D1 / D7 / D30 and payer conversion (admin)",
    description:
      "Same numbers as the /admin/analytics page. Days are UTC. Retention is pooled " <>
        "over the sign-up cohorts of the last 60 days that have reached each horizon.",
    security: [%{"authorization" => []}],
    parameters: [segment: @segment_param],
    responses: [
      ok: {"Summary", "application/json", AnalyticsSummaryResponse},
      unauthorized: Schemas.error("Not authenticated"),
      forbidden: Schemas.error("Admin required")
    ]
  )

  def show(conn, params),
    do: reply_data(conn, Analytics.summary(Date.utc_today(), segment: parse_segment(params)))

  operation(:daily,
    operation_id: "admin_get_analytics_daily",
    summary: "Per-day active / new users and cohort retention (admin)",
    security: [%{"authorization" => []}],
    parameters: [
      days: [
        in: :query,
        schema: %Schema{type: :integer, minimum: 1, maximum: 365, default: 30},
        description: "How many UTC days back, ending today"
      ],
      segment: @segment_param
    ],
    responses: [
      ok: {"Series", "application/json", AnalyticsDailyResponse},
      unauthorized: Schemas.error("Not authenticated"),
      forbidden: Schemas.error("Admin required")
    ]
  )

  def daily(conn, params) do
    days = parse_days(params["days"], 30)
    series = Analytics.daily_series(days, Date.utc_today(), segment: parse_segment(params))
    reply_data(conn, %{days: days, series: series})
  end

  operation(:snapshot,
    operation_id: "admin_get_analytics_snapshot",
    summary: "Live counters: players, lobbies, parties, quests, matchmaking, tournaments (admin)",
    description:
      "The same composition the public /api/v1/stats serves when public stats are enabled; " <>
        "always available to admins.",
    security: [%{"authorization" => []}],
    responses: [
      ok: {"Snapshot", "application/json", ServerStatsResponse},
      unauthorized: Schemas.error("Not authenticated"),
      forbidden: Schemas.error("Admin required")
    ]
  )

  def snapshot(conn, _params), do: reply_data(conn, Analytics.snapshot())

  operation(:economy,
    operation_id: "admin_get_analytics_economy",
    summary: "Currency granted / spent per day per ledger reason (admin)",
    security: [%{"authorization" => []}],
    parameters: [
      days: [
        in: :query,
        schema: %Schema{type: :integer, minimum: 1, maximum: 365, default: 7}
      ],
      currency: [
        in: :query,
        schema: %Schema{type: :string},
        description: "Only this wallet currency (e.g. coins)"
      ]
    ],
    responses: [
      ok: {"Economy flow", "application/json", AnalyticsEconomyResponse},
      unauthorized: Schemas.error("Not authenticated"),
      forbidden: Schemas.error("Admin required")
    ]
  )

  def economy(conn, params) do
    days = parse_days(params["days"], 7)
    opts = if c = blank_to_nil(params["currency"]), do: [currency: c], else: []

    reply_data(conn, %{
      days: days,
      totals: Analytics.economy_totals(days, opts),
      flow: Analytics.economy_flow(days, opts)
    })
  end

  operation(:counts,
    operation_id: "admin_get_analytics_counts",
    summary: "Daily counters by key or prefix (admin)",
    description:
      "Game-defined counters written with Gamend.Analytics.count/3, e.g. level.finished. " <>
        "End key with * for a prefix family (level.*).",
    security: [%{"authorization" => []}],
    parameters: [
      key: [in: :query, schema: %Schema{type: :string, default: "*"}, required: false],
      days: [
        in: :query,
        schema: %Schema{type: :integer, minimum: 1, maximum: 365, default: 7}
      ]
    ],
    responses: [
      ok: {"Counters", "application/json", AnalyticsCountsResponse},
      unauthorized: Schemas.error("Not authenticated"),
      forbidden: Schemas.error("Admin required")
    ]
  )

  def counts(conn, params) do
    days = parse_days(params["days"], 7)
    key = blank_to_nil(params["key"]) || "*"
    series = Analytics.counts(key, days)

    reply_data(conn, %{
      key: key,
      days: days,
      totals: Enum.map(Analytics.count_totals(key, days), fn {k, n} -> %{key: k, total: n} end),
      series:
        Map.new(series, fn {k, by_day} ->
          {k, Map.new(by_day, fn {day, n} -> {Date.to_iso8601(day), n} end)}
        end)
    })
  end

  defp parse_days(nil, default), do: default

  defp parse_days(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n >= 1 and n <= 365 -> n
      _ -> default
    end
  end

  defp parse_days(value, _default) when is_integer(value) and value >= 1 and value <= 365,
    do: value

  defp parse_days(_, default), do: default

  defp parse_segment(params), do: Analytics.segment(params["segment"])

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v) when is_binary(v), do: String.trim(v)
  defp blank_to_nil(_), do: nil
end
