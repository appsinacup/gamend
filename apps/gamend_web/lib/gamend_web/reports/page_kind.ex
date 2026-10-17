defmodule GamendWeb.Reports.PageKind do
  @moduledoc """
  How core's `"page"` report kind looks (`Gamend.Reports.Kinds.Page`): a card
  for "a page", and one field holding the page's full address, filled with
  the page the reader came from.
  """
  use GamendWeb, :html

  @behaviour GamendWeb.Reports.KindUI

  @impl true
  def label, do: gettext("A page")

  @impl true
  def description, do: gettext("Something broke or looks wrong")

  @impl true
  def icon, do: "hero-bug-ant"

  @impl true
  def subject_component, do: GamendWeb.Reports.PageSubject

  @impl true
  def subject_label(report), do: report.subject["path"]

  @impl true
  def admin_subject(assigns) do
    ~H"""
    <span :if={@report.subject["path"]} class="font-mono text-sm break-all">
      <.link
        :if={linkable?(@report.subject["path"])}
        href={@report.subject["path"]}
        target="_blank"
        rel="noopener noreferrer"
        class="link"
      >
        {@report.subject["path"]}
      </.link>
      <span :if={!linkable?(@report.subject["path"])}>
        {@report.subject["path"]}
      </span>
    </span>
    <span :if={!@report.subject["path"]} class="text-muted">{gettext("No page")}</span>
    """
  end

  # A path on this site, or a web address: never a `javascript:` a reporter typed.
  defp linkable?(page) do
    String.starts_with?(page, "/") or String.starts_with?(page, ["http://", "https://"])
  end
end

defmodule GamendWeb.Reports.PageSubject do
  @moduledoc """
  The page field on `/report`, holding the page's full URL. Filled, in order
  of preference, from the `?page=` the link carried (a bare path gets this
  site's address in front), else by the `ReportPagePath` hook from the last
  page this tab showed (kept in `sessionStorage` by `app.js`).
  """
  use GamendWeb, :live_component

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, Map.take(assigns, [:id, :query]))

    socket =
      if Map.has_key?(socket.assigns, :path) do
        socket
      else
        path = prefill(assigns[:query])
        if path, do: send(self(), {:report_subject, %{"path" => path}})
        assign(socket, :path, path)
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("change", %{"path" => path}, socket) do
    path = String.slice(path, 0, 500)
    send(self(), {:report_subject, if(String.trim(path) == "", do: nil, else: %{"path" => path})})
    {:noreply, assign(socket, :path, path)}
  end

  def handle_event("submit", _params, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <form id={@id} phx-change="change" phx-submit="submit" phx-target={@myself}>
      <label class="fieldset">
        <span class="fieldset-label font-semibold">{gettext("Page")}</span>
        <input
          type="text"
          name="path"
          id={"#{@id}-path"}
          value={@path}
          placeholder={GamendWeb.Endpoint.url() <> "/"}
          autocomplete="off"
          maxlength="500"
          phx-hook="ReportPagePath"
          class="input w-full font-mono text-sm"
        />
      </label>
    </form>
    """
  end

  defp prefill(%{"page" => "/" <> _ = path}),
    do: String.slice(GamendWeb.Endpoint.url() <> path, 0, 500)

  defp prefill(%{"page" => page}) when is_binary(page) and page != "",
    do: String.slice(page, 0, 500)

  defp prefill(_query), do: nil
end
