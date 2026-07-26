defmodule GameServerWeb.UserLive.Settings.PaymentsTab do
  @moduledoc """
  Payments tab of the user settings page: purchase history, entitlements,
  downloads, and Stripe subscription management.
  """

  use GameServerWeb, :html
  import Phoenix.LiveView

  alias GameServer.Payments
  alias GameServerWeb.UserLive.Settings.Shared

  def assign_payment_data(socket) do
    user = Shared.current_user(socket)

    if user do
      socket
      |> assign(:payment_purchases, Payments.list_user_purchases(user.id, limit: 100))
      |> assign(:payment_entitlements, Payments.list_user_entitlements(user.id))
    else
      socket
      |> assign(:payment_purchases, [])
      |> assign(:payment_entitlements, [])
    end
  end

  def tab(assigns) do
    ~H"""
    <div :if={@settings_tab == "payments"} class="mt-6 space-y-6">
      <div class="card bg-base-200 p-4 rounded-lg">
        <div class="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
          <div>
            <div class="font-semibold text-lg">{gettext("Payments")}</div>
          </div>
          <.link navigate={~p"/store"} class="btn btn-sm btn-primary">
            {gettext("Open Store")}
          </.link>
        </div>
      </div>

      <div class="card bg-base-200 p-4 rounded-lg">
        <div>
          <div class="font-semibold text-lg">{gettext("Purchases")}</div>
        </div>

        <%= if @payment_purchases == [] do %>
          <div class="mt-4 rounded-lg border border-base-300 bg-base-100 p-4 text-sm text-base-content/70">
            {gettext("No results.")}
          </div>
        <% else %>
          <div class="overflow-x-auto mt-4">
            <table id="payment-purchases-table" class="table table-zebra w-full min-w-[64rem]">
              <thead>
                <tr>
                  <th>{gettext("Order")}</th>
                  <th>{gettext("Product")}</th>
                  <th>{gettext("Provider")}</th>
                  <th>{gettext("Status")}</th>
                  <th>{gettext("Amount")}</th>
                  <th>{gettext("Environment")}</th>
                  <th>{gettext("Date")}</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={purchase <- @payment_purchases} id={"payment-purchase-#{purchase.id}"}>
                  <td>
                    <div class="font-mono text-xs break-all">{purchase.order_id}</div>
                    <div class="font-mono text-xs text-base-content/50 break-all">
                      {purchase.provider_transaction_id || "-"}
                    </div>
                  </td>
                  <td>
                    <div class="font-medium">{payment_product_title(purchase)}</div>
                    <div class="font-mono text-xs text-base-content/60">
                      {payment_product_sku(purchase)}
                    </div>
                  </td>
                  <td>{purchase.provider}</td>
                  <td>
                    <span class={["badge badge-sm", payment_status_badge_class(purchase.status)]}>
                      {purchase.status}
                    </span>
                  </td>
                  <td>{payment_amount(purchase)}</td>
                  <td>{purchase.environment}</td>
                  <td class="whitespace-nowrap"><.timestamp at={purchase.inserted_at} /></td>
                </tr>
              </tbody>
            </table>
          </div>
        <% end %>
      </div>

      <div class="card bg-base-200 p-4 rounded-lg">
        <div>
          <div class="font-semibold text-lg">{gettext("Owned")}</div>
        </div>

        <%= if @payment_entitlements == [] do %>
          <div class="mt-4 rounded-lg border border-base-300 bg-base-100 p-4 text-sm text-base-content/70">
            {gettext("No results.")}
          </div>
        <% else %>
          <div class="grid grid-cols-1 md:grid-cols-2 gap-4 mt-4">
            <div
              :for={entitlement <- @payment_entitlements}
              id={"payment-entitlement-#{entitlement.id}"}
              class="rounded-lg border border-base-300 bg-base-100 p-4"
            >
              <div class="flex items-start justify-between gap-3">
                <div>
                  <div class="font-semibold">{payment_entitlement_title(entitlement)}</div>
                  <div class="font-mono text-xs text-base-content/60">{entitlement.key}</div>
                </div>
                <span class={["badge badge-sm", payment_status_badge_class(entitlement.status)]}>
                  {entitlement.status}
                </span>
              </div>

              <div class="mt-3 grid grid-cols-2 gap-2 text-sm">
                <div>
                  <div class="text-xs uppercase text-base-content/50">{gettext("Kind")}</div>
                  <div>{payment_entitlement_kind(entitlement)}</div>
                </div>
                <div>
                  <div class="text-xs uppercase text-base-content/50">
                    {payment_entitlement_period_label(entitlement)}
                  </div>
                  <div>
                    <%= if payment_auto_renews?(entitlement) do %>
                      {gettext("Auto-renews")}
                    <% else %>
                      <.timestamp at={entitlement.expires_at} />
                    <% end %>
                  </div>
                </div>
              </div>

              <div class="mt-4 flex flex-wrap justify-end gap-2">
                <button
                  :if={payment_stripe_subscription_cancelable?(entitlement)}
                  type="button"
                  phx-click="cancel_stripe_subscription"
                  phx-value-id={entitlement.id}
                  class="btn btn-sm btn-outline btn-warning"
                >
                  {gettext("Cancel renewal")}
                </button>
                <span
                  :if={payment_subscription_cancel_scheduled?(entitlement)}
                  class="badge badge-warning"
                >
                  {gettext("Cancels at period end")}
                </span>
                <.link
                  :if={payment_downloadable?(entitlement)}
                  href={~p"/payments/downloads/#{entitlement.id}"}
                  class="btn btn-sm btn-primary"
                >
                  {gettext("Download")}
                </.link>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>

    <%!-- Data tab --%>
    """
  end

  def handle_event("cancel_stripe_subscription", %{"id" => id}, socket) do
    user = Shared.current_user(socket)

    case Payments.cancel_stripe_subscription_at_period_end(user, parse_payment_id(id)) do
      {:ok, _result} ->
        {:noreply,
         socket
         |> put_flash(:info, gettext("Subscription will cancel at the end of the period."))
         |> assign_payment_data()}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, gettext("Failed") <> ": " <> payment_error(reason))}
    end
  end

  defp parse_payment_id(id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> uuid
      :error -> nil
    end
  end

  defp parse_payment_id(_id), do: nil

  defp payment_error(%Ecto.Changeset{}), do: gettext("Invalid payment state")

  defp payment_error({:stripe_error, %{"message" => message}}) when is_binary(message),
    do: message

  defp payment_error(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp payment_error(reason), do: inspect(reason)

  defp payment_product_title(%{product: %{title: title}}) when is_binary(title) and title != "",
    do: title

  defp payment_product_title(_purchase), do: "-"

  defp payment_product_sku(%{product: %{sku: sku}}) when is_binary(sku) and sku != "", do: sku
  defp payment_product_sku(_purchase), do: "-"

  defp payment_entitlement_title(%{product: %{title: title}})
       when is_binary(title) and title != "",
       do: title

  defp payment_entitlement_title(%{key: key}), do: key

  defp payment_entitlement_kind(%{product: %{kind: kind}}) when is_binary(kind), do: kind
  defp payment_entitlement_kind(_entitlement), do: "-"

  defp payment_entitlement_period_label(entitlement) do
    cond do
      payment_subscription_cancel_scheduled?(entitlement) ->
        gettext("Cancels")

      payment_entitlement_kind(entitlement) == "subscription" ->
        gettext("Renews")

      true ->
        gettext("Expires")
    end
  end

  defp payment_auto_renews?(entitlement) do
    payment_entitlement_kind(entitlement) == "subscription" and is_nil(entitlement.expires_at)
  end

  defp payment_amount(%{amount: nil}), do: "-"
  defp payment_amount(%{currency: nil, amount: amount}), do: Integer.to_string(amount)

  defp payment_amount(%{currency: currency, amount: amount}) when is_integer(amount) do
    major = div(amount, 100)
    minor = amount |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")
    "#{String.upcase(currency)} #{major}.#{minor}"
  end

  defp payment_status_badge_class("completed"), do: "badge-success"
  defp payment_status_badge_class("active"), do: "badge-success"
  defp payment_status_badge_class("requires_action"), do: "badge-info"
  defp payment_status_badge_class("pending"), do: "badge-warning"
  defp payment_status_badge_class("refunded"), do: "badge-warning"
  defp payment_status_badge_class("revoked"), do: "badge-error"
  defp payment_status_badge_class("failed"), do: "badge-error"
  defp payment_status_badge_class(_status), do: "badge-ghost"

  defp payment_downloadable?(entitlement), do: is_map(payment_download_config(entitlement))

  defp payment_stripe_subscription_cancelable?(entitlement) do
    ((payment_entitlement_kind(entitlement) == "subscription" and
        payment_current_entitlement?(entitlement) and
        entitlement.source_purchase) &&
       entitlement.source_purchase.provider == "stripe") and
      payment_stripe_subscription_id(entitlement.source_purchase) != nil and
      not payment_subscription_cancel_scheduled?(entitlement)
  end

  defp payment_current_entitlement?(%{status: "active", expires_at: nil}), do: true

  defp payment_current_entitlement?(%{status: "active", expires_at: %DateTime{} = expires_at}) do
    DateTime.compare(expires_at, DateTime.utc_now(:second)) == :gt
  end

  defp payment_current_entitlement?(_entitlement), do: false

  defp payment_subscription_cancel_scheduled?(entitlement) do
    payment_map_value(entitlement.metadata, "stripe_subscription_cancel_at_period_end") == true or
      payment_map_value(
        entitlement.source_purchase && entitlement.source_purchase.metadata,
        "stripe_subscription_cancel_at_period_end"
      ) ==
        true
  end

  defp payment_stripe_subscription_id(purchase) do
    payment_map_value(purchase.metadata, "stripe_subscription_id") ||
      payment_map_value(purchase.raw_provider_payload, "stripe_subscription_id") ||
      payment_nested_stripe_subscription_id(purchase.raw_provider_payload)
  end

  defp payment_nested_stripe_subscription_id(%{"stripe_subscription" => %{"id" => id}})
       when is_binary(id),
       do: id

  defp payment_nested_stripe_subscription_id(%{
         "stripe_session" => %{"subscription" => %{"id" => id}}
       })
       when is_binary(id),
       do: id

  defp payment_nested_stripe_subscription_id(%{"stripe_session" => %{"subscription" => id}})
       when is_binary(id),
       do: id

  defp payment_nested_stripe_subscription_id(_payload), do: nil

  defp payment_download_config(entitlement) do
    entitlement.metadata
    |> payment_map_value("download")
    |> payment_fallback(
      payment_map_value(entitlement.product && entitlement.product.grant_config, "download")
    )
    |> payment_fallback(
      payment_map_value(entitlement.product && entitlement.product.metadata, "download")
    )
  end

  defp payment_map_value(nil, _key), do: nil

  defp payment_map_value(map, key) when is_map(map),
    do: map[key] || payment_atom_map_value(map, key)

  defp payment_map_value(_value, _key), do: nil

  defp payment_atom_map_value(map, "download"), do: map[:download]
  defp payment_atom_map_value(map, "stripe_subscription_id"), do: map[:stripe_subscription_id]

  defp payment_atom_map_value(map, "stripe_subscription_cancel_at_period_end"),
    do: map[:stripe_subscription_cancel_at_period_end]

  defp payment_atom_map_value(_map, _key), do: nil

  defp payment_fallback(nil, value), do: value
  defp payment_fallback(value, _fallback), do: value
end
