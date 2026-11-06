defmodule GamendWeb.Api.V1.Admin.ChatModerationController do
  @moduledoc """
  Admin API for chat moderation: the report queue and the word filter.

  Parity with the admin console — everything the moderation pages can click is
  callable from a script. Mutes are chat bans, on the bans API
  (`GamendWeb.Api.V1.Admin.BanController`, kind `chat`).
  """
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import GamendWeb.Helpers.ParamParser

  alias Gamend.Accounts.Scope
  alias Gamend.Accounts.User
  alias Gamend.Chat.Moderation
  alias Gamend.Chat.Report
  alias Gamend.Chat.Reports
  alias GamendWeb.Schemas

  alias GamendWeb.Schemas.{
    ChatFilterLanguagesResponse,
    ChatFilterTestResponse,
    ChatFilterWordPage,
    ChatFilterWordResponse,
    ChatReportPage,
    ChatReportResponse,
    DeletedCountResponse,
    ImportedCountResponse,
    OkResponse
  }

  alias OpenApiSpex.Schema

  tags(["Admin – Chat"])

  # ---------------------------------------------------------------------------
  # Reports
  # ---------------------------------------------------------------------------

  operation(:list_reports,
    operation_id: "admin_list_chat_reports",
    summary: "List chat reports (admin)",
    description: "The moderation queue, newest first. Filter by status or by the users involved.",
    security: [%{"authorization" => []}],
    parameters: [
      status: [
        in: :query,
        schema: %Schema{type: :string, enum: ["open", "reviewing", "actioned", "dismissed"]}
      ],
      reported_user_id: [in: :query, schema: %Schema{type: :string, format: :uuid}],
      reporter_id: [in: :query, schema: %Schema{type: :string, format: :uuid}],
      page: [in: :query, schema: %Schema{type: :integer, default: 1}],
      page_size: [in: :query, schema: %Schema{type: :integer, default: 25}]
    ],
    responses: [
      ok: {"Reports", "application/json", ChatReportPage},
      bad_request: Schemas.error("Invalid id")
    ]
  )

  def list_reports(conn, params) do
    case id_filters(params, ["reported_user_id", "reporter_id"]) do
      :error ->
        invalid_id(conn)

      {:ok, filters} ->
        filters = maybe_put_string_filter(filters, "status", params["status"])
        {page, page_size} = GamendWeb.Pagination.params(params)

        reports = Reports.list_reports(filters, page: page, page_size: page_size)
        total_count = Reports.count_reports(filters)

        reply_page(conn, Enum.map(reports, &serialize_report/1), page, page_size, total_count)
    end
  end

  operation(:resolve_report,
    operation_id: "admin_resolve_chat_report",
    summary: "Resolve a chat report (admin)",
    description:
      "Sets the report's status and records the calling admin as its resolver. " <>
        "Muting the reported player or deleting the message are separate calls.",
    security: [%{"authorization" => []}],
    parameters: [
      id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]
    ],
    request_body:
      {"Resolution", "application/json",
       %Schema{
         type: :object,
         required: [:status],
         properties: %{
           status: %Schema{
             type: :string,
             enum: ["open", "reviewing", "actioned", "dismissed"]
           },
           note: %Schema{type: :string, description: "Moderator note, not shown to players"}
         }
       }},
    responses: [
      ok: {"Resolved", "application/json", ChatReportResponse},
      bad_request: Schemas.error("Invalid id or status"),
      not_found: Schemas.error("Not found"),
      unprocessable_entity: Schemas.error("Validation failed")
    ]
  )

  def resolve_report(conn, %{"id" => id} = params) do
    status = params["status"]

    case {parse_id(id), status in Report.statuses()} do
      {nil, _valid_status} ->
        invalid_id(conn)

      {_report_id, false} ->
        reply_error(conn, :bad_request, "invalid_status")

      {report_id, true} ->
        attrs = %{"note" => params["note"], "resolved_by" => admin_id(conn)}

        case Reports.resolve_report(report_id, status, attrs) do
          {:ok, report} -> reply_data(conn, serialize_report(report))
          {:error, :not_found} -> not_found(conn)
          {:error, error} -> write_error(conn, error)
        end
    end
  end

  operation(:delete_report,
    operation_id: "admin_delete_chat_report",
    summary: "Delete a chat report (admin)",
    description: "Removes the report row itself. Resolving is usually what you want instead.",
    security: [%{"authorization" => []}],
    parameters: [
      id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]
    ],
    responses: [
      ok: {"Deleted", "application/json", OkResponse},
      bad_request: Schemas.error("Invalid id"),
      not_found: Schemas.error("Not found")
    ]
  )

  def delete_report(conn, %{"id" => id}) do
    with_record(conn, id, &Reports.get_report/1, fn report ->
      case Reports.delete_report(report) do
        {:ok, _report} -> reply_ok(conn)
        {:error, error} -> write_error(conn, error)
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Word filter
  # ---------------------------------------------------------------------------

  operation(:list_filter_words,
    operation_id: "admin_list_chat_filter_words",
    summary: "List blocklist words (admin)",
    description:
      "The chat word blocklist. Matching is language-agnostic; `lang` is provenance " <>
        "only. The bundled lists to import are at `GET /chat/filter_words/languages`.",
    security: [%{"authorization" => []}],
    parameters: [
      word: [in: :query, schema: %Schema{type: :string}, description: "Substring match"],
      severity: [in: :query, schema: %Schema{type: :string, enum: ["block", "mask", "flag"]}],
      lang: [in: :query, schema: %Schema{type: :string}],
      page: [in: :query, schema: %Schema{type: :integer, default: 1}],
      page_size: [in: :query, schema: %Schema{type: :integer, default: 25}]
    ],
    responses: [
      ok: {"Filter words", "application/json", ChatFilterWordPage}
    ]
  )

  def list_filter_words(conn, params) do
    filters =
      %{}
      |> maybe_put_string_filter("word", params["word"])
      |> maybe_put_string_filter("severity", params["severity"])
      |> maybe_put_string_filter("lang", params["lang"])

    {page, page_size} = GamendWeb.Pagination.params(params)

    words = Moderation.list_filter_words(filters, page: page, page_size: page_size)
    total_count = Moderation.count_filter_words(filters)

    reply_page(conn, Enum.map(words, &serialize_filter_word/1), page, page_size, total_count)
  end

  operation(:filter_languages,
    operation_id: "admin_list_chat_filter_languages",
    summary: "Languages with a bundled word list (admin)",
    description: "What `POST /chat/filter_words/import` accepts as `lang`.",
    security: [%{"authorization" => []}],
    responses: [ok: {"Languages", "application/json", ChatFilterLanguagesResponse}]
  )

  def filter_languages(conn, _params) do
    reply_data(conn, %{languages: Moderation.bundled_languages()})
  end

  operation(:create_filter_word,
    operation_id: "admin_create_chat_filter_word",
    summary: "Add a blocklist word (admin)",
    description:
      "The word is normalized (lower-cased, leetspeak folded) before it is stored, " <>
        "so it matches the same way the runtime filter does.",
    security: [%{"authorization" => []}],
    request_body:
      {"Filter word", "application/json",
       %Schema{
         type: :object,
         required: [:word],
         properties: %{
           word: %Schema{type: :string},
           severity: %Schema{
             type: :string,
             enum: ["block", "mask", "flag"],
             default: "block",
             description: "block rejects, mask stars out the hit, flag files a report"
           },
           match_mode: %Schema{
             type: :string,
             enum: ["substring", "exact"],
             default: "substring"
           },
           lang: %Schema{type: :string}
         }
       }},
    responses: [
      created: {"Created", "application/json", ChatFilterWordResponse},
      forbidden: Schemas.error("The word cap was reached (too_many_filter_words)"),
      unprocessable_entity: Schemas.error("Invalid word")
    ]
  )

  def create_filter_word(conn, params) do
    attrs = %{
      "word" => params["word"],
      "severity" => params["severity"] || "block",
      "match_mode" => params["match_mode"] || "substring",
      "lang" => params["lang"]
    }

    case Moderation.create_filter_word(attrs) do
      {:ok, word} -> reply_data(conn, :created, serialize_filter_word(word))
      {:error, error} -> write_error(conn, error)
    end
  end

  operation(:update_filter_word,
    operation_id: "admin_update_chat_filter_word",
    summary: "Update a blocklist word (admin)",
    security: [%{"authorization" => []}],
    parameters: [
      id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]
    ],
    request_body:
      {"Filter word", "application/json",
       %Schema{
         type: :object,
         properties: %{
           word: %Schema{type: :string},
           severity: %Schema{type: :string, enum: ["block", "mask", "flag"]},
           match_mode: %Schema{type: :string, enum: ["substring", "exact"]},
           lang: %Schema{type: :string}
         }
       }},
    responses: [
      ok: {"Updated", "application/json", ChatFilterWordResponse},
      bad_request: Schemas.error("Invalid id"),
      not_found: Schemas.error("Not found"),
      unprocessable_entity: Schemas.error("Invalid word")
    ]
  )

  def update_filter_word(conn, %{"id" => id} = params) do
    with_record(conn, id, &Moderation.get_filter_word/1, fn word ->
      attrs = Map.take(params, ["word", "severity", "match_mode", "lang"])

      case Moderation.update_filter_word(word, attrs) do
        {:ok, updated} -> reply_data(conn, serialize_filter_word(updated))
        {:error, error} -> write_error(conn, error)
      end
    end)
  end

  operation(:delete_filter_word,
    operation_id: "admin_delete_chat_filter_word",
    summary: "Remove a blocklist word (admin)",
    security: [%{"authorization" => []}],
    parameters: [
      id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true]
    ],
    responses: [
      ok: {"Deleted", "application/json", OkResponse},
      bad_request: Schemas.error("Invalid id"),
      not_found: Schemas.error("Not found")
    ]
  )

  def delete_filter_word(conn, %{"id" => id}) do
    with_record(conn, id, &Moderation.get_filter_word/1, fn word ->
      case Moderation.delete_filter_word(word) do
        {:ok, _word} -> reply_ok(conn)
        {:error, error} -> write_error(conn, error)
      end
    end)
  end

  operation(:import_filter_words,
    operation_id: "admin_import_chat_filter_words",
    summary: "Import a bundled word list (admin)",
    description:
      "Inserts the words bundled at `priv/chat_filter/<lang>.txt` at the chosen " <>
        "severity. Duplicates are skipped and `max_chat_filter_words` still applies. " <>
        "The importable languages are listed by the filter-word index.",
    security: [%{"authorization" => []}],
    request_body:
      {"Import", "application/json",
       %Schema{
         type: :object,
         required: [:lang],
         properties: %{
           lang: %Schema{type: :string, description: "Bundled list to import, e.g. \"en\""},
           severity: %Schema{
             type: :string,
             enum: ["block", "mask", "flag"],
             default: "block"
           }
         }
       }},
    responses: [
      ok: {"Imported", "application/json", ImportedCountResponse},
      bad_request: Schemas.error("No lang (missing_param)"),
      not_found: Schemas.error("No bundled list for that language (unknown_language)"),
      forbidden: Schemas.error("The word cap was reached (too_many_filter_words)")
    ]
  )

  def import_filter_words(conn, params) do
    severity = if is_binary(params["severity"]), do: params["severity"], else: "block"

    case params["lang"] do
      lang when is_binary(lang) ->
        case Moderation.import_bundled_list(lang, severity) do
          {:ok, count} -> reply_data(conn, %{imported: count})
          {:error, :unknown_language} -> reply_error(conn, :not_found, "unknown_language")
          {:error, error} -> write_error(conn, error)
        end

      _lang ->
        reply_error(conn, :bad_request, "missing_param", "lang is required")
    end
  end

  operation(:delete_filter_words_by_lang,
    operation_id: "admin_delete_chat_filter_words_by_lang",
    summary: "Remove an imported word list (admin)",
    description:
      "Deletes every blocklist entry tagged with the given language — the bulk " <>
        "undo for an import. Hand-added words have no language tag and are untouched.",
    security: [%{"authorization" => []}],
    parameters: [
      lang: [
        in: :query,
        required: true,
        schema: %Schema{type: :string},
        description: "Language tag to remove, e.g. \"en\""
      ]
    ],
    responses: [
      ok: {"Removed", "application/json", DeletedCountResponse},
      bad_request: Schemas.error("Missing lang")
    ]
  )

  def delete_filter_words_by_lang(conn, params) do
    case params["lang"] do
      lang when is_binary(lang) and lang != "" ->
        reply_data(conn, %{deleted: Moderation.delete_filter_words_by_lang(lang)})

      _lang ->
        reply_error(conn, :bad_request, "missing_param", "lang is required")
    end
  end

  operation(:test_phrase,
    operation_id: "admin_test_chat_phrase",
    summary: "Test a phrase against the filter (admin)",
    description:
      "Runs the phrase through the live blocklist and reports every hit plus what " <>
        "the chat pipeline would do with it: `block`, `mask`, `flag` or `allow`.",
    security: [%{"authorization" => []}],
    request_body:
      {"Phrase", "application/json",
       %Schema{
         type: :object,
         required: [:phrase],
         properties: %{phrase: %Schema{type: :string}}
       }},
    responses: [
      ok: {"Result", "application/json", ChatFilterTestResponse}
    ]
  )

  def test_phrase(conn, params) do
    phrase = if is_binary(params["phrase"]), do: params["phrase"], else: ""

    hits =
      phrase
      |> Moderation.hits()
      |> Enum.map(fn {word, severity, match_mode} ->
        %{word: word, severity: severity, match_mode: match_mode}
      end)

    reply_data(conn, Map.merge(%{phrase: phrase, hits: hits}, outcome(phrase)))
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp outcome(phrase) do
    case Moderation.check_content(phrase) do
      {:error, :blocked_content} ->
        %{action: "block", content: "", flagged_words: []}

      {:ok, content, flagged} ->
        %{action: action(phrase, content, flagged), content: content, flagged_words: flagged}
    end
  end

  defp action(phrase, content, flagged) do
    cond do
      content != phrase -> "mask"
      flagged != [] -> "flag"
      true -> "allow"
    end
  end

  defp serialize_report(report) do
    %{
      id: report.id,
      reporter_id: report.reporter_id || "",
      reporter_name: display_name(report, :reporter),
      reported_user_id: report.reported_user_id,
      reported_user_name: display_name(report, :reported_user),
      message_id: report.message_id || "",
      content_snapshot: report.content_snapshot || "",
      reason: report.reason || "",
      status: report.status || "open",
      resolved_by: report.resolved_by || "",
      resolved_by_name: display_name(report, :resolved_by_user),
      resolution_note: report.resolution_note || "",
      resolved_at: report.resolved_at,
      inserted_at: report.inserted_at,
      updated_at: report.updated_at
    }
  end

  defp serialize_filter_word(word) do
    %{
      id: word.id,
      word: word.word,
      severity: word.severity,
      match_mode: word.match_mode,
      lang: word.lang || "",
      inserted_at: word.inserted_at,
      updated_at: word.updated_at
    }
  end

  defp display_name(struct, field) do
    case Map.get(struct, field) do
      %{display_name: name} when is_binary(name) -> name
      _assoc -> ""
    end
  end

  defp admin_id(conn) do
    case Scope.user(conn.assigns[:current_scope]) do
      %User{id: id} -> id
      _ -> nil
    end
  end

  # An id-typed column raises on a non-UUID query param, so filters are cast up
  # front rather than handed to the context.
  defp id_filters(params, keys) do
    Enum.reduce_while(keys, {:ok, %{}}, fn key, {:ok, filters} ->
      case param_id(params[key]) do
        {:ok, nil} -> {:cont, {:ok, filters}}
        {:ok, id} -> {:cont, {:ok, Map.put(filters, key, id)}}
        :error -> {:halt, :error}
      end
    end)
  end

  defp param_id(nil), do: {:ok, nil}
  defp param_id(""), do: {:ok, nil}

  defp param_id(value) do
    case parse_id(value) do
      nil -> :error
      id -> {:ok, id}
    end
  end

  defp with_record(conn, id, fetch, fun) do
    case parse_id(id) do
      nil ->
        invalid_id(conn)

      record_id ->
        case fetch.(record_id) do
          nil -> not_found(conn)
          record -> fun.(record)
        end
    end
  end

  defp invalid_id(conn), do: reply_error(conn, :bad_request, "invalid_id")

  defp not_found(conn), do: reply_error(conn, :not_found, "not_found")

  defp write_error(conn, %Ecto.Changeset{} = changeset), do: unprocessable(conn, changeset)

  defp write_error(conn, reason) when is_atom(reason), do: reply_reason(conn, reason)
end
