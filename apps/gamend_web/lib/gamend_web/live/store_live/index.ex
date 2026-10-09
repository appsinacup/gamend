defmodule GamendWeb.StoreLive.Index do
  use GamendWeb, :live_view

  alias Gamend.Accounts.Scope
  alias Gamend.Payments
  alias Gamend.Payments.ProviderConfig
  alias GamendWeb.LiveHelpers

  @impl true
  def mount(_params, _session, socket) do
    unless GamendWeb.Features.enabled?(:web_store) do
      raise GamendWeb.NotFoundError
    end

    user = Scope.user(socket.assigns.current_scope)

    {:ok,
     socket
     |> assign(:page_title, gettext("Store"))
     |> assign(:catalog, Payments.list_catalog())
     |> assign(:owned_entitlement_keys, owned_entitlement_keys(user))
     # Setup details (the payment environment, how to add products, which
     # products only a game client can buy) are for whoever runs the store.
     |> assign(:admin?, match?(%{is_admin: true}, user))
     |> assign(:payment_environment, ProviderConfig.environment())
     |> assign(:success_purchase, nil)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, assign_success_purchase(socket, params)}
  end

  @impl true
  def handle_event("buy", %{"id" => id}, socket) do
    success_url = url(~p"/store/success") <> "?session_id={CHECKOUT_SESSION_ID}"
    cancel_url = url(~p"/store/cancel")

    attrs = %{
      "provider_product_id" => id,
      "quantity" => 1,
      "success_url" => success_url,
      "cancel_url" => cancel_url
    }

    case Payments.create_stripe_checkout(Scope.user(socket.assigns.current_scope), attrs) do
      {:ok, %{checkout_url: checkout_url}} ->
        {:noreply, redirect(socket, external: checkout_url)}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, checkout_error(reason))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="flex flex-col gap-6">
        <div class="flex flex-col gap-3 md:flex-row md:items-end md:justify-between">
          <div>
            <div class="flex items-center gap-3">
              <.back_link href={home_path()} />
              <h1 class="text-4xl font-black text-base-content">{gettext("Store")}</h1>
            </div>
            <div class="mt-2 flex flex-wrap items-center gap-2 text-sm text-muted">
              <span :if={@admin?} class="badge badge-outline">{@payment_environment}</span>
              <span>{gettext("Subscriptions, one-time items, and consumables.")}</span>
            </div>
          </div>
          <div class="flex flex-wrap gap-2">
            <.link navigate={~p"/users/settings?tab=payments"} class="btn btn-surface btn-sm">
              {gettext("Payments")}
            </.link>
          </div>
        </div>

        <%= if @live_action == :success do %>
          <div class="alert alert-success">
            <div>
              <div class="font-semibold">{gettext("Checkout returned.")}</div>
              <div class="text-sm">
                {success_purchase_message(@success_purchase)}
              </div>
            </div>
          </div>
        <% end %>

        <%= if @live_action == :cancel do %>
          <div class="alert alert-warning">
            <div>
              <div class="font-semibold">{gettext("Checkout cancelled.")}</div>
              <div class="text-sm">{gettext("No purchase was fulfilled.")}</div>
            </div>
          </div>
        <% end %>

        <%= if @catalog == [] do %>
          <div :if={@admin?} class="card bg-base-200 p-6 rounded-lg">
            <div class="font-semibold">{gettext("No products configured.")}</div>
            <div class="mt-2 text-sm text-muted">
              {gettext("Create products and provider SKUs in Admin -> Payments.")}
            </div>
          </div>
          <div :if={!@admin?} class="card bg-base-200 p-6 rounded-lg">
            <div class="font-semibold">{gettext("Nothing is for sale right now.")}</div>
          </div>
        <% else %>
          <div class="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
            <div :for={provider_product <- @catalog} id={"store-item-#{provider_product.id}"}>
              <div class="card bg-base-200 p-4 rounded-lg h-full">
                <div class="flex h-full flex-col gap-4">
                  <div class="flex items-start justify-between gap-3">
                    <div>
                      <div class="font-semibold text-lg">{provider_product.product.title}</div>
                      <div class="font-mono text-xs text-muted">
                        {provider_product.product.sku}
                      </div>
                    </div>
                    <span class={["badge badge-sm", kind_badge_class(provider_product.product.kind)]}>
                      {LiveHelpers.payment_kind_label(provider_product.product.kind)}
                    </span>
                  </div>

                  <p class="text-sm text-muted min-h-10">
                    {provider_product.product.description || gettext("Store item")}
                  </p>

                  <%!-- What a game says about its own product. A SKU whose
                        contents the server decides — a rotating bundle, say —
                        has a fixed title and price in the store and nothing
                        here without this. --%>
                  <div :if={detail = product_detail(provider_product.product)} class="space-y-1">
                    <ul class="text-sm space-y-0.5">
                      <li :for={line <- detail.lines} class="flex items-center gap-1.5">
                        <.icon name="hero-check" class="size-3.5 text-success" />
                        {line}
                      </li>
                    </ul>
                    <p :if={detail.closes_at} class="text-xs font-medium text-warning">
                      {closes_in(detail.closes_at)}
                    </p>
                  </div>

                  <div class="grid grid-cols-2 gap-2 text-sm">
                    <div>
                      <div class="text-xs uppercase text-muted">{gettext("Provider")}</div>
                      <div class="font-medium">
                        {LiveHelpers.payment_provider_label(provider_product.provider)}
                      </div>
                    </div>
                    <div>
                      <div class="text-xs uppercase text-muted">{gettext("Price")}</div>
                      <div class="font-medium">{format_amount(provider_product, @admin?)}</div>
                    </div>
                    <div>
                      <div class="text-xs uppercase text-muted">{gettext("SKU")}</div>
                      <div class="font-mono text-xs break-all">{provider_product.external_id}</div>
                    </div>
                    <div>
                      <div class="text-xs uppercase text-muted">{gettext("Status")}</div>
                      <div>
                        {if provider_product.active, do: gettext("Active"), else: gettext("Inactive")}
                      </div>
                    </div>
                  </div>

                  <div class="mt-auto flex items-center justify-between gap-2 pt-2">
                    <span class="text-xs text-muted">
                      {download_hint(provider_product.product, @admin?)}
                    </span>
                    <button
                      :if={owned?(provider_product, @owned_entitlement_keys)}
                      class="btn btn-sm btn-disabled"
                      disabled
                    >
                      {gettext("Owned")}
                    </button>
                    <button
                      :if={
                        provider_product.provider == "stripe" and
                          not owned?(provider_product, @owned_entitlement_keys) and
                          not closed?(provider_product.product)
                      }
                      phx-click="buy"
                      phx-value-id={provider_product.id}
                      class="btn btn-primary btn-sm"
                    >
                      {gettext("Buy")}
                    </button>
                    <%!-- A window the host says is shut. `before_purchase` also
                          refuses it, but a button that only fails when pressed
                          is a worse way to learn that. --%>
                    <button
                      :if={closed?(provider_product.product)}
                      class="btn btn-sm btn-disabled"
                      disabled
                    >
                      {gettext("Closed")}
                    </button>
                    <button
                      :if={
                        provider_product.provider != "stripe" and
                          not owned?(provider_product, @owned_entitlement_keys)
                      }
                      class="btn btn-sm btn-disabled"
                      disabled
                    >
                      {if @admin?, do: gettext("API only"), else: gettext("Buy in the game")}
                    </button>
                  </div>
                </div>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp assign_success_purchase(%{assigns: %{live_action: :success}} = socket, params) do
    user = Scope.user(socket.assigns.current_scope)

    purchase =
      case params["session_id"] do
        session_id when is_binary(session_id) and session_id != "" ->
          case Payments.get_purchase_by_provider_transaction("stripe", session_id) do
            %{user_id: user_id} = purchase when user_id == user.id -> purchase
            _ -> nil
          end

        _ ->
          nil
      end

    assign(socket, :success_purchase, purchase)
  end

  defp assign_success_purchase(socket, _params), do: assign(socket, :success_purchase, nil)

  defp success_purchase_message(nil) do
    gettext("Your payment is still being processed. Refresh this page in a moment.")
  end

  defp success_purchase_message(%{order_id: order_id, status: "completed"}) do
    gettext("Order %{order_id} completed.", order_id: order_id)
  end

  defp success_purchase_message(%{order_id: order_id, status: status})
       when status in ["pending", "requires_action"] do
    gettext("Order %{order_id} is waiting for payment confirmation.", order_id: order_id)
  end

  defp success_purchase_message(%{order_id: order_id, status: "failed"}) do
    gettext("Order %{order_id} failed before payment was completed.", order_id: order_id)
  end

  defp success_purchase_message(%{order_id: order_id}) do
    gettext("Order %{order_id} returned from checkout.", order_id: order_id)
  end

  defp checkout_error(%Ecto.Changeset{}), do: gettext("Checkout failed.")

  defp checkout_error(:already_owned), do: gettext("You already own this item.")

  defp checkout_error(:purchase_already_in_progress) do
    gettext("Checkout is already open for this item. Finish or cancel that checkout first.")
  end

  defp checkout_error(:quantity_not_allowed), do: gettext("This item can only be bought once.")
  defp checkout_error(:stripe_not_configured), do: gettext("Stripe is not configured.")

  defp checkout_error({:stripe_error, %{"message" => message}}) when is_binary(message) do
    gettext("Checkout failed: %{reason}", reason: message)
  end

  defp checkout_error({:stripe_error, %{"user_message" => message}}) when is_binary(message) do
    gettext("Checkout failed: %{reason}", reason: message)
  end

  # A `before_purchase` hook that refuses with a string is the game's own words.
  defp checkout_error(reason) when is_binary(reason) and reason != "",
    do: gettext("Checkout failed: %{reason}", reason: reason)

  defp checkout_error({reason, _details}) when is_atom(reason), do: checkout_error(reason)

  # Never the raw atom or `inspect/1`: a known reason in words, else the plain
  # failure.
  defp checkout_error(reason),
    do: LiveHelpers.failure_message(gettext("Checkout failed."), reason)

  # No price on file: the platform store (Apple, Google, Steam) sets it.
  defp format_amount(%{unit_amount: nil}, true), do: gettext("Provider")
  defp format_amount(%{unit_amount: nil}, _admin?), do: "-"
  defp format_amount(amount, _admin?), do: format_amount(amount)

  defp format_amount(%{currency: nil, unit_amount: amount}), do: Integer.to_string(amount)

  defp format_amount(%{currency: currency, unit_amount: amount}) do
    major = div(amount, 100)
    minor = amount |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{String.upcase(currency)} #{major}.#{minor}"
  end

  defp kind_badge_class("subscription"), do: "badge-info"
  defp kind_badge_class("consumable"), do: "badge-warning"
  defp kind_badge_class(_kind), do: "badge-primary"

  defp owned?(%{product: %{kind: kind} = product}, owned_entitlement_keys)
       when kind in ["entitlement", "subscription"] do
    MapSet.member?(owned_entitlement_keys, Payments.product_entitlement_key(product))
  end

  defp owned?(_provider_product, _owned_entitlement_keys), do: false

  defp owned_entitlement_keys(user) do
    user.id
    |> Payments.list_user_entitlements()
    |> Enum.map(& &1.key)
    |> MapSet.new()
  end

  # A game's own answer about one of its products: the lines to list under the
  # description, and when the offer shuts. Configure with
  #
  #     config :gamend_web, :store_product_detail, {MyApp.Store, :detail}
  #
  # returning `nil` for products it has nothing to add about. Core cannot know
  # what is in a bundle whose contents the game rotates server-side, and a
  # fixed `description` cannot say it either.
  defp product_detail(product) do
    case Application.get_env(:gamend_web, :store_product_detail) do
      {module, fun} ->
        case apply(module, fun, [product]) do
          %{lines: lines} = detail when is_list(lines) and lines != [] ->
            Map.put_new(detail, :closes_at, nil)

          _other ->
            nil
        end

      _unset ->
        nil
    end
  rescue
    # A game's display helper must never take the store down with it.
    _error -> nil
  end

  defp closed?(product) do
    case product_detail(product) do
      %{closes_at: closes_at} when is_integer(closes_at) ->
        closes_at <= System.system_time(:second)

      _other ->
        false
    end
  end

  defp closes_in(closes_at) do
    case closes_at - System.system_time(:second) do
      seconds when seconds <= 0 -> gettext("Closed")
      seconds when seconds < 3600 -> gettext("Closes in under an hour")
      seconds when seconds < 86_400 -> gettext("Closes in %{n}h", n: div(seconds, 3600))
      seconds -> closes_in_days(div(seconds, 86_400))
    end
  end

  defp closes_in_days(days),
    do: ngettext("Closes in %{count} day", "Closes in %{count} days", days)

  # "Grant" (the item is granted in-game, not downloaded) is setup language.
  defp download_hint(product, admin?) do
    cond do
      download_config(product) -> gettext("Downloadable")
      admin? -> gettext("Grant")
      true -> nil
    end
  end

  defp download_config(product) do
    map_value(product.grant_config, "download") || map_value(product.metadata, "download")
  end

  defp map_value(nil, _key), do: nil
  defp map_value(map, key) when is_map(map), do: map[key] || atom_map_value(map, key)
  defp map_value(_value, _key), do: nil

  defp atom_map_value(map, "download"), do: map[:download]
  defp atom_map_value(_map, _key), do: nil
end
