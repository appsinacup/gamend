defmodule GameServerWeb.AdminLive.Tournaments do
  use GameServerWeb, :live_view

  alias GameServer.Tournaments
  alias GameServer.Tournaments.Tournament

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page, 1)
      |> assign(:page_size, 25)
      |> assign(:state_filter, "all")
      |> assign(:form, nil)
      |> assign(:selected, nil)
      |> assign(:detail, nil)
      |> reload()

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-6">
        <.link navigate={~p"/admin"} class="btn btn-outline mb-4">← Back to Admin</.link>

        <div class="card bg-base-200">
          <div class="card-body">
            <div class="flex items-center justify-between">
              <h2 class="card-title">Tournaments ({@count})</h2>
              <div class="flex flex-wrap gap-2">
                <select class="select select-sm" phx-change="filter_state" name="state">
                  <option value="all" selected={@state_filter == "all"}>All states</option>
                  <option
                    :for={state <- Tournament.states()}
                    value={state}
                    selected={@state_filter == state}
                  >
                    {state}
                  </option>
                </select>
                <button phx-click="new_tournament" class="btn btn-primary btn-sm">
                  New tournament
                </button>
              </div>
            </div>

            <div class="overflow-x-auto">
              <table class="table table-sm">
                <thead>
                  <tr>
                    <th>Slug</th>
                    <th>Title</th>
                    <th>State</th>
                    <th>Starts</th>
                    <th>Entries</th>
                    <th>Bracket</th>
                    <th>Recur</th>
                    <th></th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={t <- @tournaments}>
                    <td class="font-mono text-xs">{t.slug}</td>
                    <td>{t.title}</td>
                    <td><span class={state_badge(t.state)}>{t.state}</span></td>
                    <td class="text-xs">{t.starts_at}</td>
                    <td>{Tournaments.count_entries(t.id)}</td>
                    <td class="text-xs">{t.bracket_size} / {t.round_window_sec}s</td>
                    <td class="font-mono text-xs">{t.recur}</td>
                    <td class="flex gap-1">
                      <button phx-click="open_detail" phx-value-id={t.id} class="btn btn-xs">
                        View
                      </button>
                      <button phx-click="edit_tournament" phx-value-id={t.id} class="btn btn-xs">
                        Edit
                      </button>
                      <button
                        phx-click="delete_tournament"
                        phx-value-id={t.id}
                        data-confirm="Delete this tournament and all its entries/matches?"
                        class="btn btn-xs btn-error btn-outline"
                      >
                        Delete
                      </button>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>

            <div class="flex gap-2 mt-2">
              <button phx-click="prev_page" class="btn btn-xs" disabled={@page == 1}>Prev</button>
              <span class="text-xs self-center">Page {@page}</span>
              <button
                phx-click="next_page"
                class="btn btn-xs"
                disabled={@page * @page_size >= @count}
              >
                Next
              </button>
            </div>
          </div>
        </div>

        <div :if={@form} class="card bg-base-200">
          <div class="card-body">
            <h3 class="card-title">
              {if @selected, do: "Edit tournament", else: "New tournament"}
            </h3>
            <.form for={@form} phx-submit="save_tournament" class="grid grid-cols-2 gap-3">
              <.input field={@form[:slug]} label="Slug" />
              <.input field={@form[:title]} label="Title" />
              <.input field={@form[:description]} label="Description" />
              <.input field={@form[:icon_url]} type="text" label="Icon URL (optional)" />
              <.input
                field={@form[:registration_opens_at]}
                type="utc-datetime-local"
                label="Registration opens (optional; empty = immediately)"
              />
              <.input
                field={@form[:starts_at]}
                type="utc-datetime-local"
                label="Starts at (draw; empty = start manually via Draw now)"
              />
              <.input
                field={@form[:ends_at]}
                type="utc-datetime-local"
                label="Ends at (optional hard stop)"
              />
              <.input
                field={@form[:recur]}
                label="Recur cron (optional, e.g. 0 0 * * 6)"
              />
              <.input field={@form[:max_entries]} type="number" label="Max entries (optional)" />
              <.input field={@form[:team_size]} type="number" label="Team size (advisory)" />
              <.input field={@form[:bracket_size]} type="number" label="Bracket size (power of 2)" />
              <.input
                field={@form[:round_window_sec]}
                type="number"
                label="Round window (seconds)"
              />
              <.input
                field={@form[:deadline_policy]}
                type="select"
                label="Deadline policy"
                options={Tournament.deadline_policies()}
              />
              <div class="col-span-2 flex gap-2">
                <button type="submit" class="btn btn-primary btn-sm">Save</button>
                <button type="button" phx-click="cancel_form" class="btn btn-sm">Cancel</button>
              </div>
            </.form>
          </div>
        </div>

        <div :if={@detail} class="card bg-base-200">
          <div class="card-body space-y-4">
            <div class="flex items-center justify-between">
              <h3 class="card-title">
                {@detail.tournament.title}
                <span class={state_badge(@detail.tournament.state)}>
                  {@detail.tournament.state}
                </span>
              </h3>
              <div class="flex flex-wrap gap-2">
                <button
                  :if={@detail.tournament.state == "scheduled"}
                  phx-click="force_registration"
                  class="btn btn-sm btn-outline"
                >
                  Open registration
                </button>
                <button
                  :if={@detail.tournament.state == "registration"}
                  phx-click="force_draw"
                  data-confirm="Draw the bracket now?"
                  class="btn btn-sm btn-outline"
                >
                  Draw now
                </button>
                <button
                  :if={@detail.tournament.state == "running"}
                  phx-click="force_finish"
                  data-confirm="Finish this tournament now?"
                  class="btn btn-sm btn-outline"
                >
                  Finish
                </button>
                <button
                  :if={@detail.tournament.state in ["scheduled", "registration", "running"]}
                  phx-click="force_cancel"
                  data-confirm="Cancel this tournament?"
                  class="btn btn-sm btn-error btn-outline"
                >
                  Cancel
                </button>
                <button
                  :if={@detail.tournament.state == "cancelled"}
                  phx-click="force_reopen"
                  class="btn btn-sm btn-outline"
                >
                  Reopen
                </button>
                <button phx-click="close_detail" class="btn btn-sm">Close</button>
              </div>
            </div>

            <div>
              <h4 class="font-semibold text-sm mb-1">
                Entries ({@detail.entry_count})
              </h4>
              <div class="overflow-x-auto">
                <table class="table table-xs">
                  <thead>
                    <tr>
                      <th>Leader</th>
                      <th>State</th>
                      <th>Bracket</th>
                      <th>Seed</th>
                      <th>Wins</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={entry <- @detail.entries}>
                      <td class="text-xs">
                        {Map.get(@detail.names, entry.leader_id, entry.leader_id)}
                      </td>
                      <td>{entry.state}</td>
                      <td>{entry.bracket_index}</td>
                      <td>{entry.seed}</td>
                      <td>{entry.wins}</td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>

            <div :if={@detail.entry_pages > 1} class="flex items-center gap-2">
              <button
                phx-click="detail_prev"
                class="btn btn-xs"
                disabled={@detail.entry_page <= 1}
              >
                Prev
              </button>
              <span class="text-xs">Page {@detail.entry_page} of {@detail.entry_pages}</span>
              <button
                phx-click="detail_next"
                class="btn btn-xs"
                disabled={@detail.entry_page >= @detail.entry_pages}
              >
                Next
              </button>
            </div>

            <div :if={@detail.brackets != []} class="flex items-center gap-2 flex-wrap">
              <span class="text-sm font-semibold">Brackets:</span>
              <button
                :for={b <- @detail.brackets}
                phx-click="select_bracket"
                phx-value-index={b.index}
                class={[
                  "btn btn-xs",
                  if(@detail.selected_bracket == b.index, do: "btn-primary", else: "btn-outline")
                ]}
              >
                {b.index + 1} ({b.size})
              </button>
              <.link
                :if={@detail.selected_bracket != nil}
                navigate={
                  ~p"/tournaments/#{@detail.tournament.id}/brackets/#{@detail.selected_bracket}"
                }
                class="btn btn-xs btn-outline"
              >
                View bracket tree →
              </.link>
            </div>

            <div :if={@detail.matches != []}>
              <h4 class="font-semibold text-sm mb-1">
                Matches — bracket {(@detail.selected_bracket || 0) + 1}
              </h4>
              <div class="overflow-x-auto">
                <table class="table table-xs">
                  <thead>
                    <tr>
                      <th>Round</th>
                      <th>Slot</th>
                      <th>A</th>
                      <th>B</th>
                      <th>Winner</th>
                      <th>Deadline</th>
                      <th></th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={match <- @detail.matches}>
                      <td>{match.round}</td>
                      <td>{match.slot}</td>
                      <td class="text-xs">{leader_of(@detail, match.a_entry_id)}</td>
                      <td class="text-xs">{leader_of(@detail, match.b_entry_id)}</td>
                      <td class="text-xs">
                        {if match.winner_entry_id,
                          do: leader_of(@detail, match.winner_entry_id),
                          else: if(match.resolved_at, do: "no winner", else: "—")}
                      </td>
                      <td class="text-xs">{match.deadline_at}</td>
                      <td class="flex gap-1">
                        <button
                          :if={match.resolved_at == nil and match.a_entry_id}
                          phx-click="force_resolve"
                          phx-value-match={match.id}
                          phx-value-winner={match.a_entry_id}
                          class="btn btn-xs btn-outline"
                        >
                          A wins
                        </button>
                        <button
                          :if={match.resolved_at == nil and match.b_entry_id}
                          phx-click="force_resolve"
                          phx-value-match={match.id}
                          phx-value-winner={match.b_entry_id}
                          class="btn btn-xs btn-outline"
                        >
                          B wins
                        </button>
                        <button
                          :if={match.resolved_at == nil}
                          phx-click="force_resolve"
                          phx-value-match={match.id}
                          phx-value-winner="no_winner"
                          class="btn btn-xs btn-error btn-outline"
                        >
                          No winner
                        </button>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # ── Events ────────────────────────────────────────────────────────────────

  @impl true
  def handle_event("filter_state", %{"state" => state}, socket) do
    {:noreply, socket |> assign(:state_filter, state) |> assign(:page, 1) |> reload()}
  end

  def handle_event("prev_page", _params, socket) do
    {:noreply, socket |> assign(:page, max(socket.assigns.page - 1, 1)) |> reload()}
  end

  def handle_event("next_page", _params, socket) do
    {:noreply, socket |> assign(:page, socket.assigns.page + 1) |> reload()}
  end

  def handle_event("new_tournament", _params, socket) do
    changeset =
      Tournaments.change_tournament(%Tournament{
        round_window_sec: 3600,
        bracket_size: 8,
        team_size: 1
      })

    {:noreply, socket |> assign(:selected, nil) |> assign(:form, to_form(changeset))}
  end

  def handle_event("edit_tournament", %{"id" => id}, socket) do
    case Tournaments.get_tournament(id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Not found")}

      tournament ->
        {:noreply,
         socket
         |> assign(:selected, tournament)
         |> assign(:form, to_form(Tournaments.change_tournament(tournament)))}
    end
  end

  def handle_event("cancel_form", _params, socket) do
    {:noreply, socket |> assign(:form, nil) |> assign(:selected, nil)}
  end

  def handle_event("save_tournament", %{"tournament" => params}, socket) do
    result =
      case socket.assigns.selected do
        nil -> Tournaments.create_tournament(params)
        tournament -> Tournaments.update_tournament(tournament, params)
      end

    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Saved")
         |> assign(:form, nil)
         |> assign(:selected, nil)
         |> reload()}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("delete_tournament", %{"id" => id}, socket) do
    with %Tournament{} = tournament <- Tournaments.get_tournament(id),
         {:ok, _} <- Tournaments.delete_tournament(tournament) do
      {:noreply, socket |> put_flash(:info, "Deleted") |> assign(:detail, nil) |> reload()}
    else
      _ -> {:noreply, put_flash(socket, :error, "Delete failed")}
    end
  end

  def handle_event("open_detail", %{"id" => id}, socket) do
    {:noreply, load_detail(socket, id)}
  end

  def handle_event("close_detail", _params, socket) do
    {:noreply, assign(socket, :detail, nil)}
  end

  def handle_event("force_registration", _params, socket) do
    with_detail(socket, fn tournament ->
      Tournaments.update_tournament(tournament, %{state: "registration"})
    end)
  end

  def handle_event("force_draw", _params, socket) do
    with_detail(socket, fn tournament ->
      # Pull starts_at to now; the lifecycle pass performs the draw.
      with {:ok, tournament} <-
             Tournaments.update_tournament(tournament, %{starts_at: DateTime.utc_now()}) do
        {:ok, Tournaments.advance_lifecycle(tournament)}
      end
    end)
  end

  def handle_event("force_finish", _params, socket) do
    with_detail(socket, fn tournament ->
      with {:ok, tournament} <-
             Tournaments.update_tournament(tournament, %{ends_at: DateTime.utc_now()}) do
        {:ok, Tournaments.advance_lifecycle(tournament)}
      end
    end)
  end

  def handle_event("force_cancel", _params, socket) do
    with_detail(socket, &Tournaments.cancel_tournament/1)
  end

  def handle_event("detail_prev", _params, socket) do
    d = socket.assigns.detail
    {:noreply, load_detail(socket, d.tournament.id, max(d.entry_page - 1, 1))}
  end

  def handle_event("detail_next", _params, socket) do
    d = socket.assigns.detail
    {:noreply, load_detail(socket, d.tournament.id, min(d.entry_page + 1, d.entry_pages))}
  end

  def handle_event("select_bracket", %{"index" => index}, socket) do
    d = socket.assigns.detail
    index = String.to_integer(index)
    socket = assign(socket, :detail, Map.put(d, :selected_bracket, index))
    {:noreply, load_detail(socket, d.tournament.id, d.entry_page)}
  end

  def handle_event("force_reopen", _params, socket) do
    with_detail(socket, &Tournaments.reopen_tournament/1)
  end

  def handle_event("force_resolve", %{"match" => match_id, "winner" => winner}, socket) do
    verdict = if winner == "no_winner", do: :no_winner, else: winner

    case Tournaments.resolve_match(match_id, verdict) do
      {:ok, _} ->
        {:noreply, refresh_detail(put_flash(socket, :info, "Resolved"))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Resolve failed: #{inspect(reason)}")}
    end
  end

  # ── Helpers ───────────────────────────────────────────────────────────────

  defp reload(socket) do
    opts =
      [page: socket.assigns.page, page_size: socket.assigns.page_size]
      |> then(fn opts ->
        case socket.assigns.state_filter do
          "all" -> opts
          state -> Keyword.put(opts, :state, state)
        end
      end)

    socket
    |> assign(:tournaments, Tournaments.list_tournaments(opts))
    |> assign(:count, Tournaments.count_tournaments(Keyword.drop(opts, [:page, :page_size])))
  end

  @detail_page_size 25

  defp load_detail(socket, id, page \\ 1) do
    case Tournaments.get_tournament(id) do
      nil ->
        put_flash(socket, :error, "Not found")

      tournament ->
        entry_count = Tournaments.count_entries(tournament.id)

        entries =
          Tournaments.list_entries(tournament.id, page: page, page_size: @detail_page_size)

        brackets = Tournaments.list_brackets(tournament.id)

        # Matches are shown per bracket so a large field stays readable; the
        # bracket tree itself lives on the public page.
        selected_bracket =
          socket.assigns[:detail][:selected_bracket] ||
            (List.first(brackets) && List.first(brackets).index)

        matches =
          if selected_bracket,
            do: Tournaments.list_matches(tournament.id, bracket_index: selected_bracket),
            else: []

        names =
          (Enum.map(entries, & &1.leader_id) ++
             Enum.flat_map(matches, &[&1.a_entry_id, &1.b_entry_id, &1.winner_entry_id]))
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq()
          |> entry_names(tournament.id)

        assign(socket, :detail, %{
          tournament: tournament,
          entries: entries,
          entry_count: entry_count,
          entry_page: page,
          entry_pages: ceil_div(entry_count, @detail_page_size),
          brackets: brackets,
          selected_bracket: selected_bracket,
          matches: matches,
          names: names
        })
    end
  end

  # Maps both entry ids and user ids to a display label, so match rows and
  # entry rows can share one lookup.
  defp entry_names(ids, tournament_id) do
    entries = Tournaments.entries_by_id(tournament_id, ids)

    leader_labels =
      entries
      |> Map.values()
      |> Enum.map(& &1.leader_id)
      |> Enum.concat(ids)
      |> Enum.uniq()
      |> Map.new(fn user_id -> {user_id, user_label(user_id)} end)

    Map.new(entries, fn {entry_id, entry} ->
      {entry_id, Map.get(leader_labels, entry.leader_id, entry.leader_id)}
    end)
    |> Map.merge(leader_labels)
  end

  defp user_label(user_id) do
    case GameServer.Accounts.get_user(user_id) do
      %{display_name: name} when is_binary(name) and name != "" -> name
      %{username: username} when is_binary(username) and username != "" -> username
      %{email: email} when is_binary(email) and email != "" -> email
      _ -> user_id
    end
  end

  defp ceil_div(_num, 0), do: 0
  defp ceil_div(num, den), do: div(num + den - 1, den)

  defp refresh_detail(socket) do
    case socket.assigns.detail do
      %{tournament: %{id: id}} = d -> load_detail(socket, id, d[:entry_page] || 1)
      _ -> socket
    end
  end

  defp with_detail(socket, fun) do
    case socket.assigns.detail do
      %{tournament: tournament} ->
        case fun.(tournament) do
          {:ok, _} -> {:noreply, socket |> load_detail(tournament.id) |> reload()}
          {:error, reason} -> {:noreply, put_flash(socket, :error, inspect(reason))}
          %Tournament{} -> {:noreply, socket |> load_detail(tournament.id) |> reload()}
        end

      _ ->
        {:noreply, socket}
    end
  end

  defp leader_of(_detail, nil), do: "—"

  defp leader_of(detail, entry_id) do
    Map.get(detail.names, entry_id, "—")
  end

  defp state_badge(state) do
    base = "badge badge-sm ml-2 "

    base <>
      case state do
        "running" -> "badge-success"
        "registration" -> "badge-info"
        "finished" -> "badge-neutral"
        "cancelled" -> "badge-error"
        _ -> "badge-ghost"
      end
  end
end
