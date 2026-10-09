defmodule GamendWeb.ReportLive do
  @moduledoc """
  `/report`: tell us what is wrong. No account needed.

  The reader picks a kind (`Gamend.Reports.kinds/0`, each drawn by its
  `GamendWeb.Reports.KindUI`), the kind's component picks the subject, and
  this page adds what every report has: a topic, the kind's extra fields, a
  description, an email for a reply (the account's, when signed in) and up to
  the kind's number of images.

  The URL carries the choice and anything a link wants to prefill:
  `/report?kind=page&page=/games`. A kind's component reads the rest of the
  query itself, so a host's deep link (`?kind=word&lang=ro&w=1234`) needs
  nothing from this page.

  Images are shrunk in the browser before they are sent (the `ReportForm`
  hook: at most 1600 px wide, WebP where the browser can write it), which also
  drops a photo's location data. The server still checks every byte.
  """
  use GamendWeb, :live_view

  alias Gamend.Accounts.Scope
  alias Gamend.Reports
  alias GamendWeb.LiveHelpers
  alias GamendWeb.RateLimit
  alias GamendWeb.Reports.KindUI

  @upload_accept ~w(.png .jpg .jpeg .webp)

  @impl true
  def mount(_params, session, socket) do
    kinds = Enum.filter(Reports.kinds(), &Reports.ui/1)
    max_images = kinds |> Enum.map(& &1.max_attachments()) |> Enum.max(fn -> 0 end)

    socket =
      socket
      |> assign(:page_title, gettext("Report a problem"))
      |> assign(:kinds, kinds)
      |> assign(:locale, Gettext.get_locale(GamendWeb.Gettext))
      |> assign(:client_ip, LiveHelpers.client_ip(socket, session))
      |> assign(:client, connect_client(socket))
      |> assign(:query, %{})
      |> assign(:path, "/report")
      |> assign(:kind, nil)
      |> assign(:sent, nil)
      |> reset_form()

    # Always allowed, so the template can read `@uploads`; a kind that takes no
    # images simply never shows the picker, and `create/2` refuses any sent.
    socket =
      allow_upload(socket, :attachments,
        accept: @upload_accept,
        max_entries: max(max_images, 1),
        max_file_size: Reports.resolved_config(:max_attachment_bytes)
      )

    {:ok, socket}
  end

  @impl true
  def handle_params(params, uri, socket) do
    kind = Enum.find(socket.assigns.kinds, &(&1.key() == params["kind"]))
    changed? = kind != socket.assigns.kind

    socket =
      socket
      |> assign(:query, params)
      |> assign(:path, URI.parse(uri).path || "/report")
      |> assign(:kind, kind)
      |> assign(:ui, kind && Reports.ui(kind))

    socket =
      if changed? do
        socket
        |> assign(:sent, nil)
        |> reset_form()
        |> assign(:topic, prefill_topic(kind, params))
      else
        socket
      end

    {:noreply, socket}
  end

  defp reset_form(socket) do
    socket
    |> assign(:subject, nil)
    |> assign(:topic, nil)
    |> assign(:data, %{})
    |> assign(:description, "")
    |> assign(:email, account_email(socket))
    |> assign(:error, nil)
    |> assign(:form_key, System.unique_integer([:positive]))
  end

  defp prefill_topic(nil, _params), do: nil

  defp prefill_topic(kind, params) do
    if params["topic"] in kind.topics(), do: params["topic"], else: nil
  end

  defp account_email(socket) do
    case Scope.user(socket.assigns[:current_scope]) do
      %{email: email} when is_binary(email) -> email
      _ -> ""
    end
  end

  # What a bug report needs and nobody types. The screen size arrives from the
  # hook once the page is connected (`"client"`).
  defp connect_client(socket) do
    if connected?(socket) do
      case get_connect_info(socket, :user_agent) do
        ua when is_binary(ua) -> %{"user_agent" => ua}
        _ -> %{}
      end
    else
      %{}
    end
  end

  # ── events ───────────────────────────────────────────────────────────────

  @impl true
  def handle_event("validate", params, socket) do
    {:noreply, take_form(socket, params)}
  end

  def handle_event("client", params, socket) do
    client =
      params
      |> Map.take(~w(viewport screen))
      |> Enum.filter(fn {_k, v} -> is_binary(v) end)
      |> Map.new(fn {k, v} -> {k, String.slice(v, 0, 40)} end)

    {:noreply, update(socket, :client, &Map.merge(&1, client))}
  end

  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :attachments, ref)}
  end

  def handle_event("again", _params, socket) do
    {:noreply, socket |> assign(:sent, nil) |> reset_form()}
  end

  def handle_event("send", params, socket) do
    socket = take_form(socket, params)

    cond do
      # Filled only by a bot reading the markup. It is told what a person is
      # told, so it learns nothing about why nothing was stored.
      blank?(params["website"]) == false ->
        {:noreply, assign(socket, :sent, :ok)}

      socket.assigns.kind == nil ->
        {:noreply, socket}

      rate_limited?(socket) ->
        {:noreply, assign(socket, :error, error_text(socket, :rate_limited))}

      true ->
        submit(socket)
    end
  end

  @impl true
  def handle_info({:report_subject, subject}, socket) do
    {:noreply, socket |> assign(:subject, subject) |> assign(:error, nil)}
  end

  # A picker that knows the topic better than the chips (a "missing word"
  # button) picks it.
  def handle_info({:report_topic, topic}, socket) do
    case valid_topic(socket.assigns.kind, topic) do
      nil -> {:noreply, socket}
      topic -> {:noreply, assign(socket, :topic, topic)}
    end
  end

  defp take_form(socket, params) do
    socket
    |> assign(:topic, valid_topic(socket.assigns.kind, params["topic"]) || socket.assigns.topic)
    |> assign(:data, data_param(params["data"]))
    |> assign(:description, String.slice(params["description"] || "", 0, 2_000))
    |> assign(:email, String.slice(params["email"] || "", 0, 160))
    |> assign(:error, nil)
  end

  defp valid_topic(nil, _topic), do: nil
  defp valid_topic(kind, topic), do: if(topic in kind.topics(), do: topic, else: nil)

  defp data_param(%{} = data) do
    data
    |> Enum.filter(fn {k, v} -> is_binary(k) and is_binary(v) end)
    |> Map.new(fn {k, v} -> {k, String.slice(v, 0, 500)} end)
  end

  defp data_param(_data), do: %{}

  defp rate_limited?(socket) do
    case Reports.resolved_config(:ip_hourly_limit) do
      limit when is_integer(limit) and limit > 0 ->
        key = "reports:" <> RateLimit.ip_key(socket.assigns.client_ip)
        match?({:deny, _}, RateLimit.hit(key, :timer.hours(1), limit))

      _ ->
        false
    end
  end

  defp submit(socket) do
    case read_images(socket) do
      {:ok, images} -> submit(socket, images)
      {:error, reason} -> {:noreply, assign(socket, :error, error_text(socket, reason))}
    end
  end

  defp submit(socket, images) do
    %{kind: kind, topic: topic, subject: subject, data: data} = socket.assigns

    params = %{
      "kind" => kind.key(),
      "topic" => topic,
      "subject" => subject || %{},
      "data" => data,
      "description" => socket.assigns.description,
      "email" => socket.assigns.email
    }

    context = %{
      user_id: user_id(socket),
      locale: socket.assigns.locale,
      source: "web",
      client: socket.assigns.client,
      attachments: images
    }

    case Reports.create(params, context) do
      {:ok, report} ->
        {:noreply, socket |> drop_uploads() |> assign(:sent, report)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, error_text(socket, reason))}
    end
  end

  # Read without consuming: a refused report keeps its images, so fixing a
  # typo does not mean choosing the screenshot again.
  defp read_images(socket) do
    conf = socket.assigns.uploads.attachments
    {done, in_progress} = uploaded_entries(socket, :attachments)

    cond do
      Enum.any?(conf.entries, &(not &1.valid?)) ->
        {:error, :bad_image}

      in_progress != [] ->
        {:error, :uploading}

      done == [] ->
        {:ok, []}

      true ->
        {:ok,
         consume_uploaded_entries(socket, :attachments, fn %{path: path}, _entry ->
           {:postpone, File.read!(path)}
         end)}
    end
  end

  defp drop_uploads(socket) do
    case uploaded_entries(socket, :attachments) do
      {[_ | _], []} ->
        _ = consume_uploaded_entries(socket, :attachments, fn _meta, _entry -> {:ok, nil} end)
        socket

      _ ->
        socket
    end
  end

  defp user_id(socket), do: Scope.user_id(socket.assigns[:current_scope])

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_value), do: false

  defp error_text(socket, reason) do
    KindUI.error_message(socket.assigns[:ui], reason) || generic_error(reason)
  end

  defp generic_error(:disabled),
    do: gettext("Reports are switched off right now. Try again later.")

  defp generic_error(reason) when reason in [:rate_limited, :daily_limit, :user_daily_limit],
    do: gettext("You have sent a lot of reports. Try again in an hour.")

  defp generic_error(:already_reported), do: gettext("You already reported this. We have it.")
  defp generic_error(:description_required), do: gettext("Say what happened.")
  defp generic_error(:invalid_topic), do: gettext("Pick what is wrong.")
  defp generic_error(:too_many_attachments), do: gettext("That is too many images.")
  defp generic_error(:uploading), do: gettext("Wait for the image to finish loading.")
  defp generic_error(:bad_image), do: gettext("Remove the image that cannot be used.")

  defp generic_error(reason) when reason in [:attachment_too_large, :attachment_type],
    do: gettext("That image cannot be used. Send a PNG, JPEG or WebP image.")

  defp generic_error(%Ecto.Changeset{errors: errors}) do
    if Keyword.has_key?(errors, :email),
      do: gettext("Check the email address."),
      else: gettext("Check what you entered and try again.")
  end

  defp generic_error(_reason), do: gettext("Check what you entered and try again.")

  # ── render ───────────────────────────────────────────────────────────────

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="mx-auto max-w-narrow space-y-6">
        <div class="space-y-2">
          <div class="flex items-center gap-3">
            <.back_link href={home_path()} />
            <.page_title class="min-w-0">{gettext("Report a problem")}</.page_title>
          </div>
          <p class="text-muted">
            {gettext("Tell us what is wrong and we will fix it. No account needed.")}
          </p>
        </div>

        <div class="grid gap-3 sm:grid-cols-2" role="list">
          <.link
            :for={kind <- @kinds}
            role="listitem"
            patch={kind_path(@path, kind)}
            aria-current={if(@kind == kind, do: "true")}
            class={[
              "flex items-start gap-3 rounded-box border bg-base-100 p-4 shadow-sm transition-colors",
              if(@kind == kind,
                do: "border-primary ring-2 ring-primary/40",
                else: "border-base-300 hover:border-base-content/30"
              )
            ]}
          >
            <.icon name={Reports.ui(kind).icon()} class="mt-0.5 size-6 shrink-0" />
            <span>
              <span class="block font-semibold">{Reports.ui(kind).label()}</span>
              <span class="block text-sm text-muted">
                {Reports.ui(kind).description()}
              </span>
            </span>
          </.link>
        </div>

        <.panel :if={@sent} class="space-y-4 text-center" id="report-sent">
          <.icon name="hero-check-circle" class="mx-auto size-12 text-success" />
          <p class="text-lg font-semibold">{gettext("Thanks. We read every report.")}</p>
          <p :if={user_id_present?(@current_scope)} class="text-muted">
            {gettext("We will tell you in your notifications when it is fixed.")}
          </p>
          <button type="button" class="btn btn-surface" phx-click="again">
            {gettext("Report something else")}
          </button>
        </.panel>

        <.panel :if={@kind && !@sent} class="space-y-5">
          <.live_component
            :if={KindUI.subject_component(@ui)}
            module={KindUI.subject_component(@ui)}
            id={"report-subject-#{@kind.key()}-#{@form_key}"}
            query={@query}
            topic={@topic}
            locale={@locale}
            current_scope={@current_scope}
          />

          <form
            id={"report-form-#{@form_key}"}
            phx-change="validate"
            phx-submit="send"
            phx-hook="ReportForm"
            class="space-y-5"
          >
            <fieldset :if={@kind.topics() != []} class="space-y-2">
              <legend class="font-semibold">{gettext("What is wrong")}</legend>
              <div class="flex flex-wrap gap-2">
                <label
                  :for={topic <- @kind.topics()}
                  class={["btn btn-sm", if(@topic == topic, do: "btn-primary", else: "btn-surface")]}
                >
                  <input
                    type="radio"
                    name="topic"
                    value={topic}
                    checked={@topic == topic}
                    class="sr-only"
                  />
                  <.icon
                    :if={KindUI.topic_icon(@ui, topic)}
                    name={KindUI.topic_icon(@ui, topic)}
                    class="size-4"
                  />
                  {KindUI.topic_label(@ui, topic)}
                </label>
              </div>
            </fieldset>

            <label :for={field <- KindUI.fields(@ui, @topic)} class="fieldset">
              <span class="fieldset-label font-semibold">{field.label}</span>
              <textarea
                :if={field[:type] == :textarea}
                name={"data[#{field.name}]"}
                maxlength={field[:max] || 500}
                placeholder={field[:placeholder]}
                class="textarea w-full"
              >{@data[field.name]}</textarea>
              <input
                :if={field[:type] != :textarea}
                type="text"
                name={"data[#{field.name}]"}
                value={@data[field.name]}
                maxlength={field[:max] || 200}
                placeholder={field[:placeholder]}
                autocomplete="off"
                class="input w-full"
              />
            </label>

            <label class="fieldset">
              <span class="fieldset-label font-semibold">
                {if Reports.description_required?(@kind, @topic),
                  do: gettext("What happened"),
                  else: gettext("Details (optional)")}
              </span>
              <textarea
                name="description"
                rows="4"
                maxlength="2000"
                class="textarea w-full"
                placeholder={gettext("What did you see, and what did you expect?")}
              >{@description}</textarea>
            </label>

            <div :if={@kind.max_attachments() > 0} class="space-y-2">
              <p class="font-semibold">{gettext("Screenshot (optional)")}</p>
              <.live_file_input upload={@uploads.attachments} class="hidden" />
              <input
                type="file"
                accept="image/*"
                multiple
                class="hidden"
                id={"report-pick-#{@form_key}"}
                data-report-pick
              />
              <label
                for={"report-pick-#{@form_key}"}
                data-report-drop
                class="flex cursor-pointer flex-col items-center gap-1 rounded-box border border-dashed border-base-content/30 p-5 text-center text-sm text-muted hover:border-base-content/60"
              >
                <.icon name="hero-photo" class="size-6" />
                <span>{gettext("Choose, drop or paste an image")}</span>
                <span class="text-xs">
                  {ngettext("Up to %{count} image", "Up to %{count} images", @kind.max_attachments())}
                </span>
              </label>
              <div :if={@uploads.attachments.entries != []} class="flex flex-wrap gap-3">
                <div :for={entry <- @uploads.attachments.entries} class="relative">
                  <.live_img_preview entry={entry} class="h-24 rounded-box border border-base-300" />
                  <button
                    type="button"
                    phx-click="cancel_upload"
                    phx-value-ref={entry.ref}
                    class="btn btn-circle btn-xs absolute -end-2 -top-2"
                    aria-label={gettext("Remove image")}
                  >
                    <.icon name="hero-x-mark" class="size-3" />
                  </button>
                  <p
                    :for={err <- upload_errors(@uploads.attachments, entry)}
                    class="text-xs text-error"
                  >
                    {upload_error(err)}
                  </p>
                </div>
              </div>
              <p :for={err <- upload_errors(@uploads.attachments)} class="text-sm text-error">
                {upload_error(err)}
              </p>
            </div>

            <label class="fieldset">
              <span class="fieldset-label font-semibold">{gettext("Email for a reply (optional)")}</span>
              <input
                type="email"
                name="email"
                value={@email}
                maxlength="160"
                autocomplete="email"
                class="input w-full"
              />
              <span class="fieldset-label">{gettext("Only used to answer this report.")}</span>
            </label>

            <%!-- A field no person sees. A bot filling every field fills this. --%>
            <div class="hidden" aria-hidden="true">
              <label>Website <input type="text" name="website" tabindex="-1" autocomplete="off" /></label>
            </div>

            <p class="text-xs text-muted">
              {gettext(
                "Sent with your report: your browser, your screen size and the site's language."
              )}
            </p>

            <p :if={@error} class="text-error" role="alert" id="report-error">{@error}</p>

            <button type="submit" class="btn btn-primary" phx-disable-with={gettext("Sending…")}>
              <.icon name="hero-paper-airplane" class="size-4" /> {gettext("Send report")}
            </button>
          </form>
        </.panel>
      </div>
    </Layouts.app>
    """
  end

  defp kind_path(path, kind), do: path <> "?" <> URI.encode_query(%{"kind" => kind.key()})

  defp user_id_present?(scope), do: is_binary(Scope.user_id(scope))

  defp upload_error(:too_large), do: gettext("That image is too large.")
  defp upload_error(:too_many_files), do: gettext("That is too many images.")
  defp upload_error(:not_accepted), do: gettext("Send a PNG, JPEG or WebP image.")
  defp upload_error(_error), do: gettext("That image could not be added.")
end
