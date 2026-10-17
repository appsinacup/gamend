defmodule GamendWeb.AdminLive.ChatFilter do
  @moduledoc """
  Admin view over the chat word blocklist: CRUD on the filter words, import and
  removal of the bundled per-language lists, and a test box that runs a phrase
  through the same matcher `Gamend.Chat.send_message/2` uses.
  """
  use GamendWeb, :live_view

  alias Gamend.Chat.FilterWord
  alias Gamend.Chat.Moderation
  alias Gamend.Chat.Moderation.Cache
  alias Gamend.Chat.Moderation.Normalizer
  alias GamendWeb.LiveHelpers

  @blank_word %{
    "id" => nil,
    "word" => "",
    "severity" => "block",
    "match_mode" => "substring",
    "lang" => ""
  }

  @impl true
  def mount(_params, _session, socket) do
    languages = Moderation.bundled_languages()

    socket =
      socket
      |> assign(:page_title, "Admin · Chat filter")
      |> assign(:page, 1)
      |> assign(:page_size, 25)
      |> assign(:word_filter, "")
      |> assign(:severity_filter, "")
      |> assign(:lang_filter, "")
      |> assign(:languages, languages)
      |> assign(:word_form, @blank_word)
      |> assign(:import_form, %{"lang" => List.first(languages) || "", "severity" => "block"})
      |> assign(:phrase, "")
      |> assign(:chat_guide_url, chat_guide_url(socket))
      |> reload()

    {:ok, socket}
  end

  @public_chat_guide "https://gamend.org/docs/chat"

  # Core's guides are routed only when the host mounts them
  # (`gamend_current_user_routes docs: …`); on a host that does not, the
  # in-app link 404'd. Link to the published guide instead.
  defp chat_guide_url(%{router: router}) when is_atom(router) and not is_nil(router) do
    case Phoenix.Router.route_info(router, "GET", "/docs/setup", nil) do
      :error -> @public_chat_guide
      _route -> "/docs/setup?guide=chat"
    end
  end

  defp chat_guide_url(_socket), do: @public_chat_guide

  # `?word=` pre-fills the add form, so another admin page can link straight to
  # blocking a word it is showing.
  @impl true
  def handle_params(%{"word" => word}, _uri, socket) when is_binary(word) do
    {:noreply, assign(socket, :word_form, %{@blank_word | "word" => String.trim(word)})}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("filter", params, socket) do
    {:noreply,
     socket
     |> assign(:word_filter, String.trim(Map.get(params, "word", "")))
     |> assign(:severity_filter, Map.get(params, "severity", ""))
     |> assign(:lang_filter, String.trim(Map.get(params, "lang", "")))
     |> assign(:page, 1)
     |> reload()}
  end

  def handle_event("word_form_change", params, socket) do
    form =
      Map.merge(socket.assigns.word_form, Map.take(params, ~w(word severity match_mode lang)))

    {:noreply, assign(socket, :word_form, form)}
  end

  def handle_event("save_word", _params, socket) do
    form = socket.assigns.word_form

    attrs = %{
      "word" => String.trim(form["word"] || ""),
      "severity" => form["severity"],
      "match_mode" => form["match_mode"],
      "lang" => Gamend.Parse.blank_to_nil(String.trim(form["lang"] || ""))
    }

    socket =
      case save_word(form["id"], attrs) do
        {:ok, _word} ->
          socket
          |> put_flash(:info, gettext("Word saved"))
          |> assign(:word_form, @blank_word)

        {:error, :not_found} ->
          put_flash(socket, :error, gettext("Word no longer exists"))

        {:error, :too_many_filter_words} ->
          put_flash(socket, :error, gettext("Filter word limit reached"))

        {:error, %Ecto.Changeset{} = changeset} ->
          put_flash(socket, :error, changeset_error_summary(changeset))
      end

    {:noreply, reload(socket)}
  end

  def handle_event("edit_word", %{"id" => id}, socket) do
    socket =
      case Moderation.get_filter_word(id) do
        nil ->
          put_flash(socket, :error, gettext("Word no longer exists"))

        word ->
          assign(socket, :word_form, %{
            "id" => word.id,
            "word" => word.word,
            "severity" => word.severity,
            "match_mode" => word.match_mode,
            "lang" => word.lang || ""
          })
      end

    {:noreply, socket}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, assign(socket, :word_form, @blank_word)}
  end

  def handle_event("delete_word", %{"id" => id}, socket) do
    socket =
      case Moderation.get_filter_word(id) do
        nil -> put_flash(socket, :error, gettext("Word no longer exists"))
        word -> delete_word(socket, word)
      end

    {:noreply, reload(socket)}
  end

  def handle_event("import_change", params, socket) do
    form = Map.merge(socket.assigns.import_form, Map.take(params, ~w(lang severity)))
    {:noreply, assign(socket, :import_form, form)}
  end

  def handle_event("import_list", _params, socket) do
    %{"lang" => lang, "severity" => severity} = socket.assigns.import_form

    socket =
      case Moderation.import_bundled_list(lang, severity) do
        {:ok, count} ->
          put_flash(
            socket,
            :info,
            ngettext(
              "Imported %{count} word from the %{lang} list",
              "Imported %{count} words from the %{lang} list",
              count,
              lang: lang
            )
          )

        {:error, :unknown_language} ->
          put_flash(socket, :error, gettext("No bundled list for %{lang}", lang: lang))

        {:error, :too_many_filter_words} ->
          put_flash(socket, :error, gettext("Filter word limit reached"))

        {:error, _reason} ->
          put_flash(socket, :error, gettext("Could not read the bundled list"))
      end

    {:noreply, reload(socket)}
  end

  def handle_event("remove_list", _params, socket) do
    lang = socket.assigns.import_form["lang"]
    count = Moderation.delete_filter_words_by_lang(lang)

    {:noreply,
     socket
     |> put_flash(
       :info,
       ngettext(
         "Removed %{count} word tagged %{lang}",
         "Removed %{count} words tagged %{lang}",
         count,
         lang: lang
       )
     )
     |> reload()}
  end

  def handle_event("test_change", params, socket) do
    {:noreply,
     socket
     |> assign(:phrase, Map.get(params, "phrase", ""))
     |> assign_test_result()}
  end

  def handle_event("prev_page", _params, socket),
    do: {:noreply, socket |> LiveHelpers.prev_page() |> reload()}

  def handle_event("next_page", _params, socket),
    do: {:noreply, socket |> LiveHelpers.next_page() |> reload()}

  def handle_event("page_size", %{"size" => size}, socket),
    do: {:noreply, socket |> LiveHelpers.put_page_size(size) |> reload()}

  def handle_event("refresh", _params, socket), do: {:noreply, reload(socket)}

  # ── data ──────────────────────────────────────────────────────────────────

  defp reload(socket) do
    filters = %{
      "word" => Gamend.Parse.blank_to_nil(socket.assigns.word_filter),
      "severity" => Gamend.Parse.blank_to_nil(socket.assigns.severity_filter),
      "lang" => Gamend.Parse.blank_to_nil(socket.assigns.lang_filter)
    }

    words =
      Moderation.list_filter_words(filters,
        page: socket.assigns.page,
        page_size: socket.assigns.page_size
      )

    total = Moderation.count_filter_words(filters)

    # The node's matcher holds the whole blocklist, so it is compared with the
    # unfiltered count; against `total` any active filter read as a missed
    # broadcast.
    db_words =
      if Enum.all?(filters, fn {_key, value} -> is_nil(value) end),
        do: total,
        else: Moderation.count_filter_words()

    socket
    |> assign(:words, words)
    |> assign(:count, total)
    |> assign(:db_words, db_words)
    |> assign(:cached_words, Cache.word_count())
    |> assign(:total_pages, LiveHelpers.total_pages(total, socket.assigns.page_size))
    |> assign_test_result()
  end

  defp save_word(nil, attrs), do: Moderation.create_filter_word(attrs)

  defp save_word(id, attrs) do
    case Moderation.get_filter_word(id) do
      nil -> {:error, :not_found}
      word -> Moderation.update_filter_word(word, attrs)
    end
  end

  defp delete_word(socket, word) do
    socket =
      if socket.assigns.word_form["id"] == word.id do
        assign(socket, :word_form, @blank_word)
      else
        socket
      end

    case Moderation.delete_filter_word(word) do
      {:ok, _word} -> put_flash(socket, :info, gettext("Word removed"))
      {:error, _reason} -> put_flash(socket, :error, gettext("Could not remove the word"))
    end
  end

  # The blocklist is the input to the test box, so every reload re-runs it.
  defp assign_test_result(socket) do
    assign(socket, :test_result, test_phrase(socket.assigns.phrase))
  end

  defp test_phrase(phrase) do
    if String.trim(phrase) == "" do
      nil
    else
      hits = Moderation.hits(phrase)
      blocking? = Enum.any?(hits, fn {_word, severity, _mode} -> severity == "block" end)

      case Moderation.check_content(phrase) do
        {:error, :blocked_content} ->
          test_result(:blocked, hits, blocking?, nil, [], phrase)

        {:ok, content, flagged} ->
          masked = if content == phrase, do: nil, else: content

          outcome =
            cond do
              masked -> :masked
              flagged != [] -> :flagged
              true -> :clean
            end

          test_result(outcome, hits, blocking?, masked, flagged, phrase)
      end
    end
  end

  defp test_result(outcome, hits, blocking?, masked, flagged, phrase) do
    %{
      outcome: outcome,
      hits: hits,
      blocking?: blocking?,
      masked: masked,
      flagged: flagged,
      normalized: Normalizer.normalize(phrase)
    }
  end

  defp changeset_error_summary(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> Enum.map_join("; ", fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
  end

  defp severity_badge("block"), do: "badge-error"
  defp severity_badge("mask"), do: "badge-warning"
  defp severity_badge("flag"), do: "badge-info"
  defp severity_badge(_severity), do: "badge-ghost"

  defp outcome_badge(:blocked), do: "badge-error"
  defp outcome_badge(:masked), do: "badge-warning"
  defp outcome_badge(:flagged), do: "badge-info"
  defp outcome_badge(:clean), do: "badge-success"

  defp outcome_label(:blocked), do: gettext("Blocked")
  defp outcome_label(:masked), do: gettext("Masked")
  defp outcome_label(:flagged), do: gettext("Flagged")
  defp outcome_label(:clean), do: gettext("No match")

  defp outcome_hint(:blocked), do: gettext("Rejected before it is stored or broadcast.")
  defp outcome_hint(:masked), do: gettext("Each hit becomes *** and the message is sent.")
  defp outcome_hint(:flagged), do: gettext("Sent verbatim, and a report is filed for the queue.")
  defp outcome_hint(:clean), do: gettext("Sent unchanged.")

  # ── render ────────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <.link navigate={~p"/admin"} class="btn btn-surface mb-4">← Back to Admin</.link>

      <div class="card bg-base-200 mb-4">
        <div class="card-body">
          <h2 class="card-title">{gettext("Bundled lists")}</h2>
          <p class="text-sm text-muted">
            {gettext(
              "Matching is language-agnostic: importing a language's list adds its words to one shared set, and lang only records where a row came from."
            )}
          </p>

          <form
            phx-change="import_change"
            phx-no-unused-field
            id="chat-filter-import-form"
            class="flex flex-wrap items-end gap-2 mt-2"
          >
            <select name="lang" class="select select-sm select-bordered w-40">
              <option :for={lang <- @languages} value={lang} selected={@import_form["lang"] == lang}>
                {lang}
              </option>
            </select>
            <select name="severity" class="select select-sm select-bordered w-40">
              <option
                :for={severity <- FilterWord.severities()}
                value={severity}
                selected={@import_form["severity"] == severity}
              >
                {severity}
              </option>
            </select>
            <button type="button" phx-click="import_list" class="btn btn-primary btn-sm">
              {gettext("Import bundled list")}
            </button>
            <button
              type="button"
              phx-click="remove_list"
              data-confirm={gettext("Remove every word tagged with this language?")}
              class="btn btn-outline btn-error btn-sm"
            >
              {gettext("Remove this list")}
            </button>
          </form>

          <p :if={@languages == []} class="text-sm text-muted">
            {gettext(
              "No bundled lists are available. Drop one at apps/gamend_core/priv/chat_filter/<lang>.txt."
            )}
          </p>

          <p class="text-sm text-muted mt-2">
            {gettext("Gamend ships no word list of its own; en.txt holds two placeholders.")}
            <a href={@chat_guide_url} class="link">
              {gettext("The Chat guide lists public sources and how to install one.")}
            </a>
          </p>
        </div>
      </div>

      <div class="card bg-base-200 mb-4">
        <div class="card-body">
          <h2 class="card-title">{gettext("Test a phrase")}</h2>
          <p class="text-sm text-muted">
            {gettext("Runs the phrase through the live blocklist, exactly as chat does.")}
          </p>

          <form phx-change="test_change" phx-no-unused-field id="chat-filter-test-form" class="mt-2">
            <input
              type="text"
              name="phrase"
              value={@phrase}
              placeholder={gettext("Type a message to test…")}
              phx-debounce="300"
              class="input input-sm input-bordered w-full"
            />
          </form>

          <div :if={@test_result} class="mt-3 space-y-2">
            <div class="flex flex-wrap items-center gap-2">
              <span class={["badge", outcome_badge(@test_result.outcome)]}>
                {outcome_label(@test_result.outcome)}
              </span>
              <span class="text-sm text-muted">
                {outcome_hint(@test_result.outcome)}
              </span>
            </div>

            <div :if={@test_result.masked} class="text-sm">
              {gettext("Sent as")}: <code class="font-mono text-xs">{@test_result.masked}</code>
            </div>

            <div :if={@test_result.flagged != []} class="text-sm">
              {gettext("Flagged by")}:
              <code class="font-mono text-xs">{Enum.join(@test_result.flagged, ", ")}</code>
            </div>

            <p
              :if={@test_result.outcome == :blocked and not @test_result.blocking?}
              class="text-sm text-muted"
            >
              {gettext(
                "Masking left a match behind, so the message is rejected rather than sent half-masked."
              )}
            </p>

            <div :if={@test_result.hits != []} class="flex flex-wrap gap-1">
              <span
                :for={{word, severity, mode} <- @test_result.hits}
                class={["badge badge-sm", severity_badge(severity)]}
              >
                {word} ({severity}, {mode})
              </span>
            </div>

            <div class="text-xs text-muted">
              {gettext("Normalized")}: <code class="font-mono">{@test_result.normalized}</code>
            </div>
          </div>
        </div>
      </div>

      <div class="card bg-base-200">
        <div class="card-body">
          <div class="flex flex-wrap items-center justify-between gap-2">
            <div class="flex flex-wrap items-baseline gap-2">
              <h2 class="card-title">{gettext("Blocklist")} ({@count})</h2>
              <span
                class={[
                  "badge badge-sm",
                  if(@cached_words == @db_words, do: "badge-ghost", else: "badge-warning")
                ]}
                title={
                  gettext(
                    "Words loaded into this node's in-memory matcher. A number that differs from the database count means this node missed a change broadcast."
                  )
                }
              >
                {gettext("%{n} on this node", n: @cached_words)}
              </span>
            </div>
            <button phx-click="refresh" class="btn btn-ghost btn-sm">{gettext("Refresh")}</button>
          </div>

          <form
            phx-change="word_form_change"
            phx-no-unused-field
            id="chat-filter-word-form"
            class="flex flex-wrap items-end gap-2 mt-2"
          >
            <input
              type="text"
              name="word"
              value={@word_form["word"]}
              placeholder={gettext("word")}
              class="input input-sm input-bordered font-mono w-56"
            />
            <select name="severity" class="select select-sm select-bordered w-36">
              <option
                :for={severity <- FilterWord.severities()}
                value={severity}
                selected={@word_form["severity"] == severity}
              >
                {severity}
              </option>
            </select>
            <select name="match_mode" class="select select-sm select-bordered w-36">
              <option
                :for={mode <- FilterWord.match_modes()}
                value={mode}
                selected={@word_form["match_mode"] == mode}
              >
                {mode}
              </option>
            </select>
            <input
              type="text"
              name="lang"
              value={@word_form["lang"]}
              placeholder={gettext("lang (optional)")}
              class="input input-sm input-bordered font-mono w-32"
            />
            <button type="button" phx-click="save_word" class="btn btn-primary btn-sm">
              {if @word_form["id"], do: gettext("Save word"), else: gettext("Add word")}
            </button>
            <button
              :if={@word_form["id"]}
              type="button"
              phx-click="cancel_edit"
              class="btn btn-ghost btn-sm"
            >
              {gettext("Cancel")}
            </button>
          </form>

          <form
            phx-change="filter"
            phx-no-unused-field
            id="chat-filter-filters"
            class="flex flex-wrap gap-2 my-2"
          >
            <input
              type="text"
              name="word"
              value={@word_filter}
              placeholder={gettext("filter by word")}
              phx-debounce="300"
              class="input input-sm font-mono w-56"
            />
            <select name="severity" class="select select-sm w-36">
              <option value="">{gettext("all severities")}</option>
              <option
                :for={severity <- FilterWord.severities()}
                value={severity}
                selected={@severity_filter == severity}
              >
                {severity}
              </option>
            </select>
            <input
              type="text"
              name="lang"
              value={@lang_filter}
              placeholder={gettext("filter by lang")}
              phx-debounce="300"
              class="input input-sm font-mono w-32"
            />
          </form>

          <div class="overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th>{gettext("Word")}</th>
                  <th>{gettext("Severity")}</th>
                  <th>{gettext("Match")}</th>
                  <th>{gettext("Lang")}</th>
                  <th>{gettext("Added")}</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                <tr :for={word <- @words} id={"filter-word-#{word.id}"}>
                  <td class="font-mono text-xs">{word.word}</td>
                  <td>
                    <span class={["badge badge-sm", severity_badge(word.severity)]}>
                      {word.severity}
                    </span>
                  </td>
                  <td class="text-xs">{word.match_mode}</td>
                  <td class="font-mono text-xs">{word.lang || "—"}</td>
                  <td class="text-xs">
                    <.timestamp at={word.inserted_at} format="full" />
                  </td>
                  <td class="text-right whitespace-nowrap">
                    <button
                      phx-click="edit_word"
                      phx-value-id={word.id}
                      class="btn btn-surface btn-xs"
                    >
                      {gettext("Edit")}
                    </button>
                    <button
                      phx-click="delete_word"
                      phx-value-id={word.id}
                      data-confirm={gettext("Remove this word?")}
                      class="btn btn-outline btn-error btn-xs"
                    >
                      {gettext("Delete")}
                    </button>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <div :if={@words == []} class="text-center py-8 text-muted">
            {gettext("No filter words.")}
          </div>

          <div class="mt-4 flex justify-center">
            <.pagination
              page={@page}
              total_pages={@total_pages}
              total_count={@count}
              page_size={@page_size}
              on_prev="prev_page"
              on_next="next_page"
              on_page_size="page_size"
            />
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
