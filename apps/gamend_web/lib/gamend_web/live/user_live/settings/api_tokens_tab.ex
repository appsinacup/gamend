defmodule GamendWeb.UserLive.Settings.ApiTokensTab do
  @moduledoc """
  API tokens tab of the user settings page: create a personal token, see the
  ones that exist, revoke them (`Gamend.Accounts.ApiTokens`).

  A new token is shown once, in `@api_token_created`, and never again — the
  row keeps only a hash. Dismissing the notice drops it from the socket too.
  """

  use GamendWeb, :html
  import Phoenix.LiveView, only: [put_flash: 3]

  alias Gamend.Accounts.ApiToken
  alias Gamend.Accounts.ApiTokens
  alias GamendWeb.LiveHelpers

  @page_size 25

  def assign_defaults(socket) do
    socket
    |> assign(:api_tokens_page, 1)
    |> assign(:api_token_created, nil)
    |> assign(:api_token_form, blank_form())
    |> reload_api_tokens()
  end

  def tab(assigns) do
    ~H"""
    <div :if={@settings_tab == "api_tokens"}>
      <div class="card bg-base-200 p-4 rounded-lg mt-6 space-y-4">
        <div>
          <div class="font-semibold text-lg">{gettext("API tokens")}</div>
          <div class="text-sm text-base-content/70">
            {gettext(
              "For scripts and CI: send one as a Bearer token to any API route that takes an access token. A password or email change revokes them all."
            )}
          </div>
        </div>

        <div
          :if={@api_token_created}
          id="api-token-created"
          role="alert"
          class="alert alert-success flex-col items-start gap-2"
        >
          <div class="font-semibold">
            {gettext("Copy it now. It will not be shown again.")}
          </div>
          <code id="api-token-value" class="break-all select-all text-sm">
            {@api_token_created}
          </code>
          <button type="button" phx-click="api_token_dismiss" class="btn btn-sm">
            {gettext("Done")}
          </button>
        </div>

        <.form
          for={@api_token_form}
          id="api-token-form"
          phx-submit="api_token_create"
          class="flex flex-wrap items-end gap-3"
        >
          <div class="grow min-w-48">
            <.input
              field={@api_token_form[:name]}
              type="text"
              label={gettext("Name")}
              placeholder={gettext("e.g. release script")}
              required
            />
          </div>
          <div>
            <.input
              field={@api_token_form[:expires_in_days]}
              type="select"
              label={gettext("Expires")}
              options={expiry_options()}
            />
          </div>
          <button type="submit" class="btn btn-primary btn-sm mb-2">
            {gettext("Create token")}
          </button>
        </.form>

        <div :if={@api_tokens == []} class="text-sm text-base-content/60">
          {gettext("No API tokens.")}
        </div>

        <div :if={@api_tokens != []} class="overflow-x-auto">
          <table id="user-api-tokens-table" class="table table-zebra w-full min-w-[36rem]">
            <thead>
              <tr>
                <th>{gettext("Name")}</th>
                <th>{gettext("Token")}</th>
                <th>{gettext("Created")}</th>
                <th>{gettext("Last used")}</th>
                <th>{gettext("Expires")}</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={token <- @api_tokens} id={"user-api-token-" <> token.id}>
                <td class="text-sm">{token.name}</td>
                <td class="font-mono text-xs">{ApiTokens.prefix()}{token.hint}…</td>
                <td class="text-sm whitespace-nowrap"><.timestamp at={token.inserted_at} /></td>
                <td class="text-sm whitespace-nowrap">
                  <.timestamp at={token.last_used_at} empty={gettext("Never")} />
                </td>
                <td class="text-sm whitespace-nowrap">
                  <%= cond do %>
                    <% ApiTokens.superseded?(token, @user) -> %>
                      <span class="badge badge-ghost badge-sm">
                        {gettext("Revoked by a password or email change")}
                      </span>
                    <% ApiTokens.expired?(token) -> %>
                      <span class="badge badge-ghost badge-sm">{gettext("Expired")}</span>
                    <% is_nil(ApiTokens.expires_at(token)) -> %>
                      {gettext("Never")}
                    <% true -> %>
                      <.timestamp at={ApiTokens.expires_at(token)} />
                  <% end %>
                </td>
                <td class="text-end">
                  <button
                    type="button"
                    phx-click="api_token_revoke"
                    phx-value-id={token.id}
                    data-confirm={gettext("Revoke this token? Anything using it stops working.")}
                    class="btn btn-sm btn-outline btn-error"
                  >
                    {gettext("Revoke")}
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <div :if={@api_tokens_total_pages > 1}>
          <.pagination
            page={@api_tokens_page}
            total_pages={@api_tokens_total_pages}
            total_count={@api_tokens_count}
            on_prev="api_tokens_prev"
            on_next="api_tokens_next"
          />
        </div>
      </div>
    </div>
    """
  end

  def handle_event("api_token_create", %{"api_token" => params}, socket) do
    attrs = %{
      "name" => params["name"],
      "expires_in_days" => parse_days(params["expires_in_days"])
    }

    case ApiTokens.create(socket.assigns.user, attrs) do
      {:ok, token, _row} ->
        {:noreply,
         socket
         |> assign(:api_token_created, token)
         |> assign(:api_token_form, blank_form())
         |> assign(:api_tokens_page, 1)
         |> reload_api_tokens()}

      {:error, :limit_reached} ->
        {:noreply,
         put_flash(socket, :error, gettext("You have reached the token limit. Revoke one first."))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :api_token_form, to_form(changeset, as: :api_token))}
    end
  end

  def handle_event("api_token_dismiss", _params, socket) do
    {:noreply, assign(socket, :api_token_created, nil)}
  end

  def handle_event("api_token_revoke", %{"id" => id}, socket) do
    case ApiTokens.revoke(socket.assigns.user.id, to_string(id)) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, gettext("Token revoked.")) |> reload_api_tokens()}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Failed"))}
    end
  end

  def handle_event("api_tokens_prev", _params, socket) do
    page = max(1, (socket.assigns.api_tokens_page || 1) - 1)
    {:noreply, socket |> assign(:api_tokens_page, page) |> reload_api_tokens()}
  end

  def handle_event("api_tokens_next", _params, socket) do
    page = (socket.assigns.api_tokens_page || 1) + 1
    {:noreply, socket |> assign(:api_tokens_page, page) |> reload_api_tokens()}
  end

  @doc "Reloads the token list for the current page."
  def reload_api_tokens(socket) do
    page = socket.assigns[:api_tokens_page] || 1
    user = socket.assigns.user
    count = ApiTokens.count(user.id)

    socket
    |> assign(:api_tokens, ApiTokens.list(user.id, page: page, page_size: @page_size))
    |> assign(:api_tokens_count, count)
    |> assign(:api_tokens_total_pages, LiveHelpers.total_pages(count, @page_size))
  end

  defp blank_form do
    to_form(%{"name" => "", "expires_in_days" => default_expiry()}, as: :api_token)
  end

  # 90 days when it is offered, else the longest lifetime that expires.
  defp default_expiry do
    days = ApiToken.expiry_choices() |> Enum.reject(&is_nil/1)
    to_string(if 90 in days, do: 90, else: List.last(days))
  end

  defp expiry_options do
    Enum.map(ApiToken.expiry_choices(), fn
      nil -> {gettext("Never"), "never"}
      days -> {ngettext("In %{count} day", "In %{count} days", days), to_string(days)}
    end)
  end

  defp parse_days("never"), do: nil

  defp parse_days(value) when is_binary(value) do
    case Integer.parse(value) do
      {days, ""} -> days
      _ -> -1
    end
  end

  defp parse_days(_), do: -1
end
