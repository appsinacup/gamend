defmodule GamendWeb.Api.V1.Admin.TournamentController do
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gamend.Tournaments
  alias Gamend.Tournaments.Tournament
  alias GamendWeb.Schemas

  alias GamendWeb.Schemas.{
    AdminTournamentResponse,
    OkResponse,
    TournamentMatchResponse,
    UploadTicketResponse
  }

  alias GamendWeb.Serializers
  alias GamendWeb.Uploads
  alias OpenApiSpex.Schema

  tags(["Admin – Tournaments"])

  @tournament_body %Schema{
    type: :object,
    properties: %{
      slug: %Schema{type: :string},
      title: %Schema{type: :string},
      description: %Schema{type: :string},
      icon_url: %Schema{type: :string, description: "Empty when unset"},
      registration_opens_at: %Schema{type: :string, format: "date-time"},
      starts_at: %Schema{type: :string, format: "date-time", nullable: true},
      ends_at: %Schema{type: :string, format: "date-time"},
      recur: %Schema{type: :string, description: "Cron expression; omit for one-shot"},
      max_entries: %Schema{type: :integer},
      team_size: %Schema{type: :integer},
      bracket_size: %Schema{type: :integer, description: "Power of two >= 2"},
      round_window_sec: %Schema{type: :integer},
      deadline_policy: %Schema{
        type: :string,
        enum: ["forfeit_both", "advance_first_slot", "random"]
      },
      metadata: %Schema{type: :object}
    },
    required: [:slug, :title, :round_window_sec]
  }

  operation(:create,
    operation_id: "admin_create_tournament",
    summary: "Create tournament (admin)",
    security: [%{"authorization" => []}],
    request_body: {"Tournament", "application/json", @tournament_body},
    responses: [
      created: {"Tournament", "application/json", AdminTournamentResponse},
      unauthorized: Schemas.error("Not authenticated"),
      forbidden: Schemas.error("Admin required"),
      unprocessable_entity: Schemas.error("Validation failed")
    ]
  )

  def create(conn, params) do
    case Tournaments.create_tournament(params) do
      {:ok, tournament} -> reply_data(conn, :created, serialize(tournament))
      {:error, changeset} -> changeset_error(conn, changeset)
    end
  end

  operation(:update,
    operation_id: "admin_update_tournament",
    summary: "Update tournament (admin)",
    security: [%{"authorization" => []}],
    parameters: [id: [in: :path, schema: %Schema{type: :string}, required: true]],
    request_body: {"Fields to change", "application/json", @tournament_body},
    responses: [
      ok: {"Tournament", "application/json", AdminTournamentResponse},
      not_found: Schemas.error("Not found"),
      unprocessable_entity: Schemas.error("Validation failed")
    ]
  )

  def update(conn, %{"id" => id} = params) do
    with_tournament(conn, id, fn tournament ->
      case Tournaments.update_tournament(tournament, Map.delete(params, "id")) do
        {:ok, tournament} -> reply_data(conn, serialize(tournament))
        {:error, changeset} -> changeset_error(conn, changeset)
      end
    end)
  end

  operation(:icon_upload_url,
    operation_id: "admin_tournament_icon_upload_url",
    summary: "Request an upload ticket for a tournament icon (admin)",
    description: """
    Step one of two. Returns a presigned ticket; PUT the image straight to
    `url`, then POST the returned `key` to the icon endpoint. Bytes never pass
    through the app server.
    """,
    security: [%{"authorization" => []}],
    parameters: [id: [in: :path, schema: %Schema{type: :string}, required: true]],
    request_body:
      {"Declared content type", "application/json",
       %Schema{
         type: :object,
         properties: %{content_type: %Schema{type: :string, example: "image/png"}},
         required: [:content_type]
       }},
    responses: [
      ok: {"Upload ticket", "application/json", UploadTicketResponse},
      bad_request: Schemas.error("Unsupported content type"),
      not_found: Schemas.error("Not found")
    ]
  )

  def icon_upload_url(conn, %{"id" => id} = params) do
    with_tournament(conn, id, fn tournament ->
      Uploads.ticket(
        conn,
        "icons/tournaments",
        tournament.id,
        "icon",
        Uploads.content_type(params)
      )
    end)
  end

  operation(:set_icon,
    operation_id: "admin_set_tournament_icon",
    summary: "Confirm an uploaded tournament icon (admin)",
    description: "Step two: records a previously uploaded object as the icon.",
    security: [%{"authorization" => []}],
    parameters: [id: [in: :path, schema: %Schema{type: :string}, required: true]],
    request_body:
      {"Uploaded object key", "application/json",
       %Schema{type: :object, properties: %{key: %Schema{type: :string}}, required: [:key]}},
    responses: [
      ok: {"Tournament", "application/json", AdminTournamentResponse},
      bad_request: Schemas.error("Object not found"),
      forbidden: Schemas.error("Key not owned by this tournament"),
      not_found: Schemas.error("Not found")
    ]
  )

  def set_icon(conn, %{"id" => id} = params) do
    with_tournament(conn, id, fn tournament ->
      Uploads.confirm(conn, "icons/tournaments", tournament.id, params["key"], fn url ->
        case Tournaments.update_tournament(tournament, %{"icon_url" => url}) do
          {:ok, updated} -> reply_data(conn, serialize(updated))
          {:error, changeset} -> changeset_error(conn, changeset)
        end
      end)
    end)
  end

  operation(:delete,
    operation_id: "admin_delete_tournament",
    summary: "Delete tournament and all its entries/matches (admin)",
    security: [%{"authorization" => []}],
    parameters: [id: [in: :path, schema: %Schema{type: :string}, required: true]],
    responses: [
      ok: {"Deleted", "application/json", OkResponse},
      not_found: Schemas.error("Not found")
    ]
  )

  def delete(conn, %{"id" => id}) do
    with_tournament(conn, id, fn tournament ->
      # A delete racing this one may have removed it since it was read.
      case Tournaments.delete_tournament(tournament) do
        {:ok, _} -> reply_ok(conn)
        {:error, :not_found} -> reply_error(conn, :not_found, "not_found")
      end
    end)
  end

  operation(:cancel,
    operation_id: "admin_cancel_tournament",
    summary: "Cancel tournament (admin; terminal, no recurrence spawn)",
    security: [%{"authorization" => []}],
    parameters: [id: [in: :path, schema: %Schema{type: :string}, required: true]],
    responses: [
      ok: {"Tournament", "application/json", AdminTournamentResponse},
      not_found: Schemas.error("Not found")
    ]
  )

  def cancel(conn, %{"id" => id}) do
    with_tournament(conn, id, fn tournament ->
      case Tournaments.cancel_tournament(tournament) do
        {:ok, tournament} -> reply_data(conn, serialize(tournament))
        {:error, :not_found} -> reply_error(conn, :not_found, "not_found")
      end
    end)
  end

  operation(:reopen,
    operation_id: "admin_reopen_tournament",
    summary: "Reopen a cancelled tournament (admin)",
    security: [%{"authorization" => []}],
    parameters: [id: [in: :path, schema: %Schema{type: :string}, required: true]],
    responses: [
      ok: {"Tournament", "application/json", AdminTournamentResponse},
      forbidden: Schemas.error("Not cancelled (not_cancelled)"),
      not_found: Schemas.error("Not found"),
      conflict: Schemas.error("Another change moved its state first (state_changed)")
    ]
  )

  def reopen(conn, %{"id" => id}) do
    with_tournament(conn, id, fn tournament ->
      case Tournaments.reopen_tournament(tournament) do
        {:ok, reopened} ->
          reply_data(conn, serialize(reopened))

        {:error, reason} ->
          refusal(conn, reason)
      end
    end)
  end

  operation(:draw,
    operation_id: "admin_draw_tournament",
    summary: "Draw the bracket now (admin; pulls starts_at to now)",
    security: [%{"authorization" => []}],
    parameters: [id: [in: :path, schema: %Schema{type: :string}, required: true]],
    responses: [
      ok: {"Tournament", "application/json", AdminTournamentResponse},
      forbidden: Schemas.error("Not in a drawable state (not_drawable)"),
      not_found: Schemas.error("Not found"),
      unprocessable_entity: Schemas.error("The window it sets is invalid")
    ]
  )

  def draw(conn, %{"id" => id}) do
    with_tournament(conn, id, fn tournament ->
      if tournament.state in ["scheduled", "registration"] do
        tournament
        |> Tournaments.update_tournament(%{starts_at: DateTime.utc_now(:second)})
        |> advanced(conn)
      else
        reply_error(conn, :forbidden, "not_drawable")
      end
    end)
  end

  operation(:finish,
    operation_id: "admin_finish_tournament",
    summary: "Finish tournament now (admin; pulls ends_at to now)",
    security: [%{"authorization" => []}],
    parameters: [id: [in: :path, schema: %Schema{type: :string}, required: true]],
    responses: [
      ok: {"Tournament", "application/json", AdminTournamentResponse},
      forbidden: Schemas.error("Not running (not_running)"),
      not_found: Schemas.error("Not found"),
      unprocessable_entity: Schemas.error("The window it sets is invalid")
    ]
  )

  def finish(conn, %{"id" => id}) do
    with_tournament(conn, id, fn tournament ->
      if tournament.state == "running" do
        tournament
        |> Tournaments.update_tournament(finish_window(tournament))
        |> advanced(conn)
      else
        reply_error(conn, :forbidden, "not_running")
      end
    end)
  end

  operation(:resolve_match,
    operation_id: "admin_resolve_tournament_match",
    summary: "Force a match verdict (admin)",
    security: [%{"authorization" => []}],
    parameters: [
      id: [in: :path, schema: %Schema{type: :string}, required: true],
      match_id: [in: :path, schema: %Schema{type: :string}, required: true]
    ],
    request_body: {
      "Verdict",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          winner_entry_id: %Schema{
            type: :string,
            format: :uuid,
            nullable: true,
            description: "Omit or null for :no_winner (double forfeit)"
          }
        }
      }
    },
    responses: [
      ok: {"The resolved match", "application/json", TournamentMatchResponse},
      bad_request: Schemas.error("Not an entry of this match (invalid_winner)"),
      forbidden: Schemas.error("A before_tournament_result hook refused it (rejected)"),
      conflict: Schemas.error("Already resolved (already_resolved)"),
      not_found: Schemas.error("Not found")
    ]
  )

  def resolve_match(conn, %{"id" => id, "match_id" => match_id} = params) do
    with_tournament(conn, id, fn tournament ->
      verdict =
        case params["winner_entry_id"] do
          winner when is_binary(winner) and winner != "" -> winner
          _ -> :no_winner
        end

      match = Tournaments.get_match(match_id)

      if match == nil or match.tournament_id != tournament.id do
        reply_error(conn, :not_found, "not_found")
      else
        case Tournaments.resolve_match(match_id, verdict) do
          {:ok, match} ->
            reply_data(conn, serialize_match(tournament, match))

          {:error, reason} ->
            refusal(conn, reason)
        end
      end
    end)
  end

  # ── Helpers ───────────────────────────────────────────────────────────────

  defp with_tournament(conn, id, fun) do
    case Tournaments.get_tournament(id) do
      nil -> reply_error(conn, :not_found, "not_found")
      tournament -> fun.(tournament)
    end
  end

  defp serialize(%Tournament{} = t) do
    %{
      id: t.id,
      slug: t.slug,
      title: t.title,
      description: t.description || "",
      icon_url: t.icon_url || "",
      state: t.state,
      registration_opens_at: t.registration_opens_at,
      starts_at: t.starts_at,
      ends_at: t.ends_at,
      recur: t.recur || "",
      max_entries: t.max_entries,
      team_size: t.team_size,
      bracket_size: t.bracket_size,
      round_window_sec: t.round_window_sec,
      deadline_policy: t.deadline_policy,
      metadata: t.metadata || %{},
      inserted_at: t.inserted_at,
      updated_at: t.updated_at
    }
  end

  defp changeset_error(conn, changeset) do
    unprocessable(conn, changeset)
  end

  # The resolved match as players see it, leader ids included.
  defp serialize_match(tournament, match) do
    entry_ids = Enum.reject([match.a_entry_id, match.b_entry_id], &is_nil/1)

    leaders =
      tournament.id
      |> Tournaments.entries_by_id(entry_ids)
      |> Map.new(fn {id, entry} -> {id, entry.leader_id} end)

    Serializers.serialize_tournament_match(match, leaders)
  end

  # Draw and finish move the tournament's own clock, then let the lifecycle
  # catch up. A window the changeset rejects is a 422, not a crash: it was a
  # hard match, and finishing in the same second as an early draw failed
  # `ends_at` "must be after starts_at" and answered 500.
  defp advanced({:ok, tournament}, conn),
    do: reply_data(conn, serialize(Tournaments.advance_lifecycle(tournament)))

  defp advanced({:error, changeset}, conn), do: changeset_error(conn, changeset)

  # Ends now. A draw in this very second left `starts_at` equal to now, and
  # `ends_at` must come after it, so the start moves back that one second.
  defp finish_window(%Tournament{starts_at: %DateTime{} = starts_at}) do
    now = DateTime.utc_now(:second)

    if DateTime.compare(starts_at, now) == :lt,
      do: %{ends_at: now},
      else: %{starts_at: DateTime.add(now, -1), ends_at: now}
  end

  defp finish_window(_tournament), do: %{ends_at: DateTime.utc_now(:second)}

  # `Gamend.Tournaments` refuses with an atom, whose status
  # `GamendWeb.ErrorStatus` gives (`already_resolved` and `state_changed` 409,
  # `not_cancelled` 403, `not_found` 404), or with a
  # `before_tournament_result` veto (403 `rejected`).
  defp refusal(conn, :invalid_winner), do: reply_error(conn, :bad_request, "invalid_winner")
  defp refusal(conn, %Ecto.Changeset{} = changeset), do: unprocessable(conn, changeset)
  defp refusal(conn, reason), do: reply_reason(conn, reason)
end
