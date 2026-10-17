defmodule GamendWeb.Api.V1.ReportController do
  @moduledoc """
  Content reports from a game client (`Gamend.Reports`): the same queue the
  website's `/report` files into.

  Signed in (a device token is enough): the account is what the per-account
  daily cap counts against. Images arrive base64 in the JSON body rather than
  through an upload ticket — a report carries at most a few small screenshots,
  and one request that either files everything or nothing is easier on a
  client than a three-step upload.
  """
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gamend.Accounts.Scope
  alias Gamend.Reports
  alias GamendWeb.RateLimit
  alias GamendWeb.Schemas
  alias GamendWeb.Schemas.ReportKindsResponse
  alias GamendWeb.Schemas.ReportReceiptResponse
  alias GamendWeb.Schemas.ReportRequest

  tags(["Reports"])

  operation(:kinds,
    operation_id: "list_report_kinds",
    security: [%{"authorization" => []}],
    summary: "Report kinds",
    description: "What a report can be about: each kind's key, topics and image limits.",
    responses: [ok: {"Report kinds", "application/json", ReportKindsResponse}]
  )

  def kinds(conn, _params) do
    max_bytes = Reports.resolved_config(:max_attachment_bytes)

    reply_data(conn, %{
      kinds:
        Enum.map(Reports.kinds(), fn kind ->
          %{
            key: kind.key(),
            topics: kind.topics(),
            max_attachments: kind.max_attachments(),
            max_attachment_bytes: max_bytes
          }
        end)
    })
  end

  operation(:create,
    operation_id: "create_report",
    security: [%{"authorization" => []}],
    summary: "File a report",
    description:
      "Report a problem with the game's content: a page, a word, anything a kind covers. " <>
        "Lands in the admin queue at /admin/reports.",
    request_body: {"Report", "application/json", ReportRequest},
    responses: [
      created: {"Report filed", "application/json", ReportReceiptResponse},
      bad_request: Schemas.error("Unknown kind, bad topic, bad image (invalid_report)"),
      conflict: Schemas.error("The caller already has this report open (already_reported)"),
      too_many_requests: Schemas.error("Over the hourly or daily cap (report_limit)"),
      service_unavailable: Schemas.error("Reports are switched off (reports_disabled)")
    ]
  )

  def create(conn, params) do
    params = body(conn, params)

    with :ok <- rate_limit(conn),
         {:ok, images} <- decode_images(params["attachments"]),
         {:ok, report} <-
           Reports.create(params, %{
             user_id: Scope.user_id(conn.assigns[:current_scope]),
             locale: params["locale"],
             source: "api",
             client: params["client"],
             attachments: images
           }) do
      reply_data(conn, :created, %{id: report.id, kind: report.kind, status: report.status})
    else
      {:error, :disabled} ->
        reply_error(conn, :service_unavailable, "reports_disabled")

      {:error, reason} when reason in [:rate_limited, :daily_limit, :user_daily_limit] ->
        reply_error(conn, :too_many_requests, "report_limit")

      {:error, :already_reported} ->
        reply_error(conn, :conflict, "already_reported")

      {:error, %Ecto.Changeset{} = changeset} ->
        unprocessable(conn, changeset)

      {:error, reason} ->
        reply_error(conn, :bad_request, "invalid_report", reason_text(reason))
    end
  end

  defp rate_limit(conn) do
    case Reports.resolved_config(:ip_hourly_limit) do
      limit when is_integer(limit) and limit > 0 ->
        key = "reports:" <> RateLimit.ip_key(conn.remote_ip)

        case RateLimit.hit(key, :timer.hours(1), limit) do
          {:allow, _} -> :ok
          {:deny, _} -> {:error, :rate_limited}
        end

      _ ->
        :ok
    end
  end

  defp decode_images(nil), do: {:ok, []}

  defp decode_images(list) when is_list(list) do
    Enum.reduce_while(list, {:ok, []}, fn
      encoded, {:ok, acc} when is_binary(encoded) ->
        case Base.decode64(encoded, ignore: :whitespace) do
          {:ok, bytes} -> {:cont, {:ok, [bytes | acc]}}
          :error -> {:halt, {:error, :attachment_type}}
        end

      _other, _acc ->
        {:halt, {:error, :attachment_type}}
    end)
    |> case do
      {:ok, images} -> {:ok, Enum.reverse(images)}
      error -> error
    end
  end

  defp decode_images(_other), do: {:error, :attachment_type}

  defp reason_text(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_text(_reason), do: nil

  # OpenApiSpex may hand the body back as a cast struct; the context wants the
  # plain string-keyed map (see ClientLogController).
  defp body(conn, params) do
    case conn.private[:open_api_spex] do
      %{body_params: %_{} = cast} -> cast |> Map.from_struct() |> stringify()
      _ -> params
    end
  end

  defp stringify(%_{} = struct), do: struct |> Map.from_struct() |> stringify()

  defp stringify(map) when is_map(map),
    do: Map.new(map, fn {k, v} -> {to_string(k), stringify(v)} end)

  defp stringify(list) when is_list(list), do: Enum.map(list, &stringify/1)
  defp stringify(other), do: other
end
