defmodule GamendWeb.AdminLive.QuestCodes do
  @moduledoc """
  The redemption codes of one code-only quest: generate, add one with a chosen
  token, search, revoke, restore and download. Reached from a row's Codes
  button on `/admin/quests`.
  """
  use GamendWeb, :live_view

  alias Gamend.Accounts
  alias Gamend.Quests
  alias Gamend.Quests.Codes
  alias Gamend.Quests.Quest
  alias GamendWeb.AdminLive.Shared
  alias GamendWeb.LiveHelpers

  require Gamend.Quests.QuestCodeStatus, as: QuestCodeStatus

  # Not `:search`: it holds a code, and a code never goes in a URL.
  use GamendWeb.UrlState,
    reload: :reload_codes,
    keys: [:page, :page_size]

  @impl true
  def mount(%{"key" => key}, _session, socket) do
    case Quests.get_quest_by_key(key) do
      %Quest{code_only: true} = quest ->
        {:ok,
         socket
         |> assign(:page_title, "Codes: #{quest.title}")
         |> assign(:quest, quest)
         |> assign(:page, 1)
         |> assign(:page_size, 25)
         |> assign(:search, "")
         |> assign(:generating, false)
         |> reset_forms()
         |> reload_codes()}

      _ ->
        raise GamendWeb.NotFoundError
    end
  end

  @impl true
  def handle_event("generate", %{"generate" => params}, socket) do
    with {:ok, count} <- parse_count(params["count"]),
         {:ok, max_uses} <- parse_max_uses(params["max_uses"]),
         {:ok, metadata} <- parse_metadata(params["metadata"]) do
      quest = socket.assigns.quest

      {:noreply,
       socket
       |> assign(:generating, true)
       |> start_async(:generate, fn ->
         Quests.generate_codes(quest, count, max_uses: max_uses, metadata: metadata)
       end)}
    else
      :error -> {:noreply, put_flash(socket, :error, "Check the count, uses and metadata.")}
    end
  end

  def handle_event("add", %{"code" => params}, socket) do
    with {:ok, max_uses} <- parse_max_uses(params["max_uses"]),
         {:ok, metadata} <- parse_metadata(params["metadata"]) do
      attrs = %{"token" => params["token"], "max_uses" => max_uses, "metadata" => metadata}

      case Quests.create_code(socket.assigns.quest, attrs) do
        {:ok, code} ->
          {:noreply,
           socket
           |> put_flash(:info, "Code #{code.token} added")
           |> reset_forms()
           |> reload_codes()}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, failure(reason))}
      end
    else
      :error -> {:noreply, put_flash(socket, :error, "Check the uses and metadata.")}
    end
  end

  def handle_event("search", %{"search" => search}, socket) do
    {:noreply, socket |> assign(:search, search) |> assign(:page, 1) |> reload_codes()}
  end

  def handle_event("revoke", %{"id" => id}, socket),
    do: {:noreply, set_status(socket, id, QuestCodeStatus.revoked())}

  def handle_event("restore", %{"id" => id}, socket),
    do: {:noreply, set_status(socket, id, QuestCodeStatus.active())}

  def handle_event("prev_page", _params, socket),
    do: {:noreply, socket |> LiveHelpers.prev_page() |> reload_codes()}

  def handle_event("next_page", _params, socket),
    do: {:noreply, socket |> LiveHelpers.next_page() |> reload_codes()}

  def handle_event("page_size", %{"size" => size}, socket),
    do: {:noreply, socket |> LiveHelpers.put_page_size(size) |> reload_codes()}

  @impl true
  def handle_async(:generate, {:ok, {:ok, created}}, socket) do
    {:noreply,
     socket
     |> assign(:generating, false)
     |> put_flash(:info, "#{created} codes generated")
     |> reload_codes()}
  end

  def handle_async(:generate, {:ok, {:error, reason}}, socket) do
    {:noreply, socket |> assign(:generating, false) |> put_flash(:error, failure(reason))}
  end

  def handle_async(:generate, {:exit, _reason}, socket) do
    {:noreply,
     socket
     |> assign(:generating, false)
     |> put_flash(:error, "Generating stopped. Some codes may have been made.")
     |> reload_codes()}
  end

  defp set_status(socket, id, status) do
    case Quests.set_code_status(id, status) do
      {:ok, _code} -> reload_codes(socket)
      {:error, _reason} -> put_flash(socket, :error, Shared.gone_message())
    end
  end

  defp failure(%Ecto.Changeset{} = changeset), do: Shared.error_summary(changeset)
  defp failure(:too_many_codes), do: "That is more than one Generate may make."
  defp failure(reason), do: "Failed: #{inspect(reason)}"

  defp parse_count(value) do
    case Integer.parse(to_string(value)) do
      {count, ""} when count > 0 -> {:ok, count}
      _ -> :error
    end
  end

  defp parse_max_uses(value) when value in [nil, ""], do: {:ok, nil}
  defp parse_max_uses(value), do: parse_count(value)

  defp parse_metadata(value) when value in [nil, ""], do: {:ok, %{}}

  defp parse_metadata(value) do
    case Jason.decode(value) do
      {:ok, %{} = map} -> {:ok, map}
      _ -> :error
    end
  end

  defp reset_forms(socket) do
    socket
    |> assign(
      :generate_form,
      to_form(%{"count" => "100", "max_uses" => "1", "metadata" => ""}, as: :generate)
    )
    |> assign(:add_form, to_form(%{"token" => "", "max_uses" => "", "metadata" => ""}, as: :code))
  end

  defp reload_codes(socket) do
    key = socket.assigns.quest.key
    %{page: page, page_size: page_size, search: search} = socket.assigns

    codes = Quests.list_codes(key, page: page, page_size: page_size, search: search)
    count = Quests.count_codes(key, search: search)

    socket
    |> assign(:codes, codes)
    |> assign(:used_by, Map.new(codes, &{&1.id, used_by(&1)}))
    |> assign(:count, count)
    |> assign(:total_pages, max(LiveHelpers.total_pages(count, page_size), 1))
  end

  defp used_by(%{uses: 0}), do: []
  defp used_by(code), do: Codes.used_by(code.id)

  defp uses_text(%{max_uses: nil, uses: uses}), do: "#{uses} / every player"
  defp uses_text(%{max_uses: max, uses: uses}), do: "#{uses} / #{max}"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-6">
        <.admin_header page="/admin/quests" title={"Codes: #{@quest.title}"} back="/admin/quests">
          <:subtitle>
            Link players to it with <code class="font-mono">/redeem?quest={@quest.key}</code>
          </:subtitle>
          <:actions>
            <a
              id="quest-codes-export"
              href={~p"/admin/quests/#{@quest.key}/codes/export"}
              class="btn btn-sm btn-outline"
            >
              <.icon name="hero-arrow-down-tray-solid" class="w-4 h-4" /> Download CSV
            </a>
          </:actions>
        </.admin_header>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
          <div class="card bg-base-200">
            <div class="card-body">
              <h2 class="card-title">Generate</h2>
              <.form for={@generate_form} id="quest-codes-generate" phx-submit="generate">
                <.input field={@generate_form[:count]} type="number" label="How many" min="1" />
                <.input
                  field={@generate_form[:max_uses]}
                  type="number"
                  label="Uses per code (blank: every player once)"
                  min="1"
                />
                <.input
                  field={@generate_form[:metadata]}
                  type="text"
                  label="Metadata (JSON, players can read it)"
                />
                <button type="submit" class="btn btn-primary btn-sm" disabled={@generating}>
                  {if @generating, do: "Generating…", else: "Generate"}
                </button>
              </.form>
            </div>
          </div>

          <div class="card bg-base-200">
            <div class="card-body">
              <h2 class="card-title">Add one code</h2>
              <.form for={@add_form} id="quest-codes-add" phx-submit="add">
                <.input field={@add_form[:token]} type="text" label="Code (any text)" />
                <.input
                  field={@add_form[:max_uses]}
                  type="number"
                  label="Uses (blank: every player once)"
                  min="1"
                />
                <.input
                  field={@add_form[:metadata]}
                  type="text"
                  label="Metadata (JSON, players can read it)"
                />
                <button type="submit" class="btn btn-primary btn-sm">Add</button>
              </.form>
            </div>
          </div>
        </div>

        <div class="card bg-base-200">
          <div class="card-body">
            <div class="flex flex-wrap items-center justify-between gap-2">
              <h2 class="card-title">Codes ({@count})</h2>
              <form id="quest-codes-search" phx-change="search" phx-submit="search">
                <input
                  type="text"
                  name="search"
                  value={@search}
                  placeholder="Find an exact code"
                  aria-label="Find an exact code"
                  autocomplete="off"
                  class="input input-sm input-bordered"
                  phx-debounce="300"
                />
              </form>
            </div>

            <div class="overflow-x-auto mt-4">
              <table class="table table-zebra w-full min-w-[48rem]">
                <thead>
                  <tr>
                    <th>Code</th>
                    <th>Uses</th>
                    <th>Status</th>
                    <th>Used by</th>
                    <th>Created</th>
                    <th>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={code <- @codes} id={"quest-code-#{code.id}"}>
                    <td>
                      <div class="flex items-center gap-1">
                        <input
                          id={"quest-code-token-#{code.id}"}
                          type="text"
                          readonly
                          value={code.token}
                          aria-label="Code"
                          class="input input-xs input-bordered w-56 font-mono"
                        />
                        <button
                          type="button"
                          id={"quest-code-copy-#{code.id}"}
                          phx-hook="CopyText"
                          data-target={"quest-code-token-#{code.id}"}
                          data-copied="Copied"
                          class="btn btn-xs btn-ghost"
                        >
                          Copy
                        </button>
                      </div>
                    </td>
                    <td class="text-sm font-mono">{uses_text(code)}</td>
                    <td class="text-sm">
                      <%= if code.status == QuestCodeStatus.active() do %>
                        <span class="badge badge-success badge-sm">active</span>
                      <% else %>
                        <span class="badge badge-neutral badge-sm">revoked</span>
                      <% end %>
                    </td>
                    <td class="text-sm">
                      {Enum.map_join(@used_by[code.id], ", ", &Accounts.display_label/1)}
                      <span :if={code.uses > length(@used_by[code.id])} class="text-muted">
                        +{code.uses - length(@used_by[code.id])}
                      </span>
                    </td>
                    <td class="text-sm"><.timestamp at={code.inserted_at} /></td>
                    <td>
                      <%= if code.status == QuestCodeStatus.active() do %>
                        <button
                          phx-click="revoke"
                          phx-value-id={code.id}
                          class="btn btn-xs btn-outline btn-error"
                        >
                          Revoke
                        </button>
                      <% else %>
                        <button
                          phx-click="restore"
                          phx-value-id={code.id}
                          class="btn btn-xs btn-outline btn-success"
                        >
                          Restore
                        </button>
                      <% end %>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>

            <div class="mt-4">
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
      </div>
    </Layouts.app>
    """
  end
end
