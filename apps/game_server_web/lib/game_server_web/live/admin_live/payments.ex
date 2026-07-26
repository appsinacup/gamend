defmodule GameServerWeb.AdminLive.Payments do
  use GameServerWeb, :live_view

  alias GameServer.Payments
  alias GameServer.Payments.Product
  alias GameServer.Payments.ProviderProduct

  @sections ~w(products provider_products purchases entitlements provider_events reconciliation_cursors)a
  @default_page_size 25

  @impl true
  def mount(_params, _session, socket) do
    pages = Map.new(@sections, &{&1, 1})
    page_sizes = Map.new(@sections, &{&1, @default_page_size})

    {:ok,
     socket
     |> assign(:pages, pages)
     |> assign(:page_sizes, page_sizes)
     |> assign(:counts, %{})
     |> assign(:total_pages, %{})
     |> assign(:product_form, nil)
     |> assign(:selected_product, nil)
     |> assign(:provider_product_form, nil)
     |> assign(:selected_provider_product, nil)
     |> reload_all()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} current_path={assigns[:current_path]}>
      <div class="space-y-6">
        <.link navigate={~p"/admin"} class="btn btn-outline mb-4">&larr; Back to Admin</.link>

        <div class="flex flex-wrap items-start justify-between gap-4">
          <div>
            <h1 class="text-3xl font-bold">Payments</h1>
            <p class="mt-1 text-sm text-base-content/70">
              Payment configuration, catalog, purchases, entitlements, and provider events.
            </p>
          </div>
          <div class="flex flex-wrap gap-2">
            <a href="/api/docs" class="btn btn-outline btn-sm">OpenAPI</a>
            <a href="/admin/config" class="btn btn-outline btn-sm">Provider config</a>
            <a
              href="https://docs.stripe.com/keys"
              target="_blank"
              rel="noreferrer"
              class="btn btn-outline btn-sm"
            >
              Stripe keys
            </a>
            <a
              href="https://docs.stripe.com/webhooks"
              target="_blank"
              rel="noreferrer"
              class="btn btn-outline btn-sm"
            >
              Stripe webhooks
            </a>
          </div>
        </div>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-4">
          <div class="card bg-base-200">
            <div class="card-body">
              <h2 class="card-title">Payment Providers</h2>
              <div class="space-y-2 text-sm">
                <div :for={adapter <- @store_adapters} class="flex items-center justify-between gap-3">
                  <div>
                    <div class="font-semibold capitalize">{adapter.provider}</div>
                    <div class="font-mono text-xs text-base-content/60">
                      {inspect(adapter.module)}
                    </div>
                    <div class="mt-1 text-xs text-base-content/70">
                      {adapter_status_summary(adapter.status)}
                    </div>
                  </div>
                  <div class="flex flex-wrap justify-end gap-2">
                    <span
                      :if={adapter.provider == "stripe"}
                      class={["badge", mode_badge_class(adapter.status.mode)]}
                    >
                      {adapter.status.mode}
                    </span>
                    <span class={[
                      "badge",
                      if(adapter.configured, do: "badge-success", else: "badge-warning")
                    ]}>
                      {if(adapter.configured, do: "configured", else: "missing")}
                    </span>
                  </div>
                </div>
                <div class="text-xs text-base-content/60">
                  Provider secrets and exact environment variables live in Admin > Config.
                </div>
              </div>
            </div>
          </div>

          <div class="card bg-base-200">
            <div class="card-body">
              <h2 class="card-title">Totals</h2>
              <div class="grid grid-cols-2 gap-2 text-sm">
                <div>Products</div>
                <div class="font-mono text-right">{@stats.products}</div>
                <div>Provider SKUs</div>
                <div class="font-mono text-right">{@stats.provider_products}</div>
                <div>Purchases</div>
                <div class="font-mono text-right">{@stats.purchases}</div>
                <div>Completed</div>
                <div class="font-mono text-right">{@stats.completed_purchases}</div>
                <div>Entitlements</div>
                <div class="font-mono text-right">{@stats.entitlements}</div>
                <div>Provider events</div>
                <div class="font-mono text-right">{@stats.provider_events}</div>
              </div>
            </div>
          </div>
        </div>

        <div class="card bg-base-200">
          <div class="card-body">
            <div class="flex flex-wrap items-center justify-between gap-3">
              <h2 class="card-title">Products ({@counts.products || 0})</h2>
              <button type="button" phx-click="new_product" class="btn btn-primary btn-sm">
                + Product
              </button>
            </div>

            <div class="overflow-x-auto mt-4">
              <table class="table table-zebra w-full min-w-[60rem]">
                <thead>
                  <tr>
                    <th>ID</th>
                    <th>SKU</th>
                    <th>Title</th>
                    <th>Kind</th>
                    <th>Active</th>
                    <th>Grant config</th>
                    <th>Created</th>
                    <th>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={product <- @products} id={"admin-payment-product-#{product.id}"}>
                    <td class="font-mono text-xs">{product.id}</td>
                    <td class="font-mono text-xs break-all">{product.sku}</td>
                    <td class="text-sm">{product.title}</td>
                    <td><span class="badge badge-outline">{product.kind}</span></td>
                    <td>{active_badge(product.active)}</td>
                    <td>
                      <pre class="text-xs font-mono whitespace-pre-wrap max-h-24 overflow-auto bg-base-100/60 rounded p-2">{json_preview(product.grant_config)}</pre>
                    </td>
                    <td class="font-mono text-xs">
                      <.timestamp at={product.inserted_at} format="full" />
                    </td>
                    <td>
                      <button
                        type="button"
                        phx-click="edit_product"
                        phx-value-id={product.id}
                        class="btn btn-xs btn-outline btn-info"
                      >
                        Edit
                      </button>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
            <.section_pager
              section="products"
              page={@pages.products}
              total_pages={@total_pages.products || 1}
              count={@counts.products || 0}
            />
          </div>
        </div>

        <div class="card bg-base-200">
          <div class="card-body">
            <div class="flex flex-wrap items-center justify-between gap-3">
              <h2 class="card-title">Provider Products ({@counts.provider_products || 0})</h2>
              <button type="button" phx-click="new_provider_product" class="btn btn-primary btn-sm">
                + Provider SKU
              </button>
            </div>

            <div class="overflow-x-auto mt-4">
              <table class="table table-zebra w-full min-w-[64rem]">
                <thead>
                  <tr>
                    <th>ID</th>
                    <th>Provider</th>
                    <th>External ID</th>
                    <th>Product</th>
                    <th>Price</th>
                    <th>Active</th>
                    <th>Metadata</th>
                    <th>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={pp <- @provider_products} id={"admin-provider-product-#{pp.id}"}>
                    <td class="font-mono text-xs">{pp.id}</td>
                    <td>
                      <span class={["badge", provider_badge_class(pp.provider)]}>{pp.provider}</span>
                    </td>
                    <td class="font-mono text-xs break-all">{pp.external_id}</td>
                    <td>
                      <div class="font-mono text-xs">{pp.product && pp.product.sku}</div>
                      <div class="text-xs text-base-content/60">#{pp.product_id}</div>
                    </td>
                    <td class="font-mono text-xs">{format_amount(pp.unit_amount, pp.currency)}</td>
                    <td>{active_badge(pp.active)}</td>
                    <td>
                      <pre class="text-xs font-mono whitespace-pre-wrap max-h-24 overflow-auto bg-base-100/60 rounded p-2">{json_preview(pp.metadata)}</pre>
                    </td>
                    <td>
                      <button
                        type="button"
                        phx-click="edit_provider_product"
                        phx-value-id={pp.id}
                        class="btn btn-xs btn-outline btn-info"
                      >
                        Edit
                      </button>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
            <.section_pager
              section="provider_products"
              page={@pages.provider_products}
              total_pages={@total_pages.provider_products || 1}
              count={@counts.provider_products || 0}
            />
          </div>
        </div>

        <div class="card bg-base-200">
          <div class="card-body">
            <h2 class="card-title">Purchases ({@counts.purchases || 0})</h2>
            <div class="overflow-x-auto mt-4">
              <table class="table table-zebra w-full min-w-[76rem]">
                <thead>
                  <tr>
                    <th>ID</th>
                    <th>Order</th>
                    <th>User</th>
                    <th>Provider</th>
                    <th>Product</th>
                    <th>Status</th>
                    <th>Amount</th>
                    <th>Provider TX</th>
                    <th>Purchased</th>
                    <th>Revoked</th>
                    <th>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={p <- @purchases} id={"admin-purchase-#{p.id}"}>
                    <td class="font-mono text-xs">{p.id}</td>
                    <td class="font-mono text-xs break-all">{p.order_id}</td>
                    <td class="text-xs" title={p.user_id}>{user_display(p.user)}</td>
                    <td>
                      <span class={["badge", provider_badge_class(p.provider)]}>{p.provider}</span>
                    </td>
                    <td class="font-mono text-xs">{p.product && p.product.sku}</td>
                    <td><span class={["badge", status_badge_class(p.status)]}>{p.status}</span></td>
                    <td class="font-mono text-xs">{format_amount(p.amount, p.currency)}</td>
                    <td class="font-mono text-xs break-all">{p.provider_transaction_id}</td>
                    <td class="font-mono text-xs">
                      <.timestamp at={p.purchased_at || p.inserted_at} format="full" />
                    </td>
                    <td class="font-mono text-xs"><.timestamp at={p.revoked_at} format="full" /></td>
                    <td>
                      <button
                        :if={stripe_reconcile_available?(p)}
                        type="button"
                        phx-click="reconcile_stripe_purchase"
                        phx-value-id={p.id}
                        class="btn btn-xs btn-outline btn-primary"
                      >
                        Reconcile Stripe
                      </button>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
            <.section_pager
              section="purchases"
              page={@pages.purchases}
              total_pages={@total_pages.purchases || 1}
              count={@counts.purchases || 0}
            />
          </div>
        </div>

        <div class="card bg-base-200">
          <div class="card-body">
            <h2 class="card-title">Entitlements ({@counts.entitlements || 0})</h2>
            <div class="overflow-x-auto mt-4">
              <table class="table table-zebra w-full min-w-[64rem]">
                <thead>
                  <tr>
                    <th>ID</th>
                    <th>User</th>
                    <th>Key</th>
                    <th>Status</th>
                    <th>Product</th>
                    <th>Purchase</th>
                    <th>Starts</th>
                    <th>Expires</th>
                    <th>Revoked</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={e <- @entitlements} id={"admin-entitlement-#{e.id}"}>
                    <td class="font-mono text-xs">{e.id}</td>
                    <td class="text-xs" title={e.user_id}>{user_display(e.user)}</td>
                    <td class="font-mono text-xs break-all">{e.key}</td>
                    <td>
                      <span class={["badge", entitlement_badge_class(e.status)]}>{e.status}</span>
                    </td>
                    <td class="font-mono text-xs">{e.product && e.product.sku}</td>
                    <td class="font-mono text-xs">{e.source_purchase_id}</td>
                    <td class="font-mono text-xs"><.timestamp at={e.starts_at} format="full" /></td>
                    <td class="font-mono text-xs"><.timestamp at={e.expires_at} format="full" /></td>
                    <td class="font-mono text-xs"><.timestamp at={e.revoked_at} format="full" /></td>
                  </tr>
                </tbody>
              </table>
            </div>
            <.section_pager
              section="entitlements"
              page={@pages.entitlements}
              total_pages={@total_pages.entitlements || 1}
              count={@counts.entitlements || 0}
            />
          </div>
        </div>

        <div class="grid grid-cols-1 xl:grid-cols-2 gap-4">
          <div class="card bg-base-200">
            <div class="card-body">
              <h2 class="card-title">Provider Events ({@counts.provider_events || 0})</h2>
              <div class="overflow-x-auto mt-4">
                <table class="table table-zebra w-full min-w-[52rem]">
                  <thead>
                    <tr>
                      <th>ID</th>
                      <th>Provider</th>
                      <th>Event ID</th>
                      <th>Type</th>
                      <th>Processed</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr :for={event <- @provider_events} id={"admin-provider-event-#{event.id}"}>
                      <td class="font-mono text-xs">{event.id}</td>
                      <td>
                        <span class={["badge", provider_badge_class(event.provider)]}>
                          {event.provider}
                        </span>
                      </td>
                      <td class="font-mono text-xs break-all">{event.event_id}</td>
                      <td class="font-mono text-xs break-all">{event.event_type}</td>
                      <td class="font-mono text-xs">
                        <.timestamp at={event.processed_at} format="full" />
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
              <.section_pager
                section="provider_events"
                page={@pages.provider_events}
                total_pages={@total_pages.provider_events || 1}
                count={@counts.provider_events || 0}
              />
            </div>
          </div>
        </div>

        <div class="card bg-base-200">
          <div class="card-body">
            <h2 class="card-title">Reconciliation Cursors ({@counts.reconciliation_cursors || 0})</h2>
            <div class="overflow-x-auto mt-4">
              <table class="table table-zebra w-full min-w-[48rem]">
                <thead>
                  <tr>
                    <th>ID</th>
                    <th>Provider</th>
                    <th>Name</th>
                    <th>Cursor</th>
                    <th>Updated</th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    :for={cursor <- @reconciliation_cursors}
                    id={"admin-reconciliation-cursor-#{cursor.id}"}
                  >
                    <td class="font-mono text-xs">{cursor.id}</td>
                    <td>
                      <span class={["badge", provider_badge_class(cursor.provider)]}>
                        {cursor.provider}
                      </span>
                    </td>
                    <td class="font-mono text-xs">{cursor.name}</td>
                    <td>
                      <pre class="text-xs font-mono whitespace-pre-wrap max-h-24 overflow-auto bg-base-100/60 rounded p-2">{json_preview(cursor.cursor)}</pre>
                    </td>
                    <td class="font-mono text-xs">
                      <.timestamp at={cursor.updated_at} format="full" />
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
            <.section_pager
              section="reconciliation_cursors"
              page={@pages.reconciliation_cursors}
              total_pages={@total_pages.reconciliation_cursors || 1}
              count={@counts.reconciliation_cursors || 0}
            />
          </div>
        </div>
      </div>
    </Layouts.app>

    <%= if @product_form do %>
      <div class="modal modal-open">
        <div class="modal-box max-w-4xl">
          <h3 class="font-bold text-lg">
            {if(@selected_product, do: "Edit Product", else: "New Product")}
          </h3>
          <.form
            for={@product_form}
            id="admin-payment-product-form"
            phx-submit="save_product"
            class="space-y-3 mt-4"
          >
            <input type="hidden" name={@product_form[:id].name} value={@product_form[:id].value} />
            <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
              <.input field={@product_form[:sku]} type="text" label="SKU" required />
              <.input field={@product_form[:title]} type="text" label="Title" required />
              <.input
                field={@product_form[:kind]}
                type="select"
                label="Kind"
                options={Product.kinds()}
              />
              <.input field={@product_form[:active]} type="checkbox" label="Active" />
            </div>
            <.input
              field={@product_form[:description]}
              type="textarea"
              label="Description"
              class="w-full textarea min-h-20"
            />
            <div class="grid grid-cols-1 lg:grid-cols-2 gap-3">
              <.input
                field={@product_form[:grant_config_json]}
                type="textarea"
                label="Grant config JSON"
                class="w-full textarea font-mono text-xs min-h-32"
                required
              />
              <.input
                field={@product_form[:metadata_json]}
                type="textarea"
                label="Metadata JSON"
                class="w-full textarea font-mono text-xs min-h-32"
                required
              />
            </div>
            <div class="modal-action">
              <button type="button" phx-click="close_product_modal" class="btn">Cancel</button>
              <button type="submit" class="btn btn-primary">Save</button>
            </div>
          </.form>
        </div>
      </div>
    <% end %>

    <%= if @provider_product_form do %>
      <div class="modal modal-open">
        <div class="modal-box max-w-4xl">
          <h3 class="font-bold text-lg">
            {if(@selected_provider_product, do: "Edit Provider SKU", else: "New Provider SKU")}
          </h3>
          <.form
            for={@provider_product_form}
            id="admin-payment-provider-product-form"
            phx-submit="save_provider_product"
            class="space-y-3 mt-4"
          >
            <input
              type="hidden"
              name={@provider_product_form[:id].name}
              value={@provider_product_form[:id].value}
            />
            <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
              <.input
                field={@provider_product_form[:product_id]}
                type="select"
                label="Product"
                options={product_options(@all_products)}
                required
              />
              <.input
                field={@provider_product_form[:provider]}
                type="select"
                label="Provider"
                options={ProviderProduct.providers()}
              />
              <.input
                field={@provider_product_form[:external_id]}
                type="text"
                label="External ID / Stripe price ID"
                required
              />
              <.input
                field={@provider_product_form[:currency]}
                type="text"
                label="Currency (USD, EUR)"
                maxlength="3"
              />
              <.input
                field={@provider_product_form[:unit_amount]}
                type="number"
                label="Unit amount in minor units"
                min="0"
              />
              <.input field={@provider_product_form[:active]} type="checkbox" label="Active" />
            </div>
            <.input
              field={@provider_product_form[:metadata_json]}
              type="textarea"
              label="Metadata JSON"
              class="w-full textarea font-mono text-xs min-h-32"
              required
            />
            <div class="modal-action">
              <button type="button" phx-click="close_provider_product_modal" class="btn">
                Cancel
              </button>
              <button type="submit" class="btn btn-primary">Save</button>
            </div>
          </.form>
        </div>
      </div>
    <% end %>
    """
  end

  @impl true
  def handle_event("section_page", %{"section" => section, "dir" => dir}, socket) do
    section = section_atom(section)
    page = socket.assigns.pages[section] || 1
    total_pages = socket.assigns.total_pages[section] || 1

    next_page =
      case dir do
        "prev" -> max(1, page - 1)
        "next" -> min(total_pages, page + 1)
        _ -> page
      end

    {:noreply,
     socket
     |> assign(:pages, Map.put(socket.assigns.pages, section, next_page))
     |> reload_section(section)}
  end

  @impl true
  def handle_event("new_product", _params, socket) do
    {:noreply, assign_product_form(socket, nil)}
  end

  @impl true
  def handle_event("edit_product", %{"id" => id}, socket) do
    product_id = parse_id(id)

    case product_id && Payments.get_product(product_id) do
      nil -> {:noreply, put_flash(socket, :error, "Product not found")}
      product -> {:noreply, assign_product_form(socket, product)}
    end
  end

  @impl true
  def handle_event("close_product_modal", _params, socket) do
    {:noreply, socket |> assign(:product_form, nil) |> assign(:selected_product, nil)}
  end

  @impl true
  def handle_event("save_product", %{"product" => params}, socket) do
    case product_attrs(params) do
      {:ok, attrs} ->
        result =
          case parse_id(params["id"]) do
            nil ->
              Payments.create_product(attrs)

            id ->
              case Payments.get_product(id) do
                nil -> {:error, :not_found}
                product -> Payments.update_product(product, attrs)
              end
          end

        case result do
          {:ok, _product} ->
            {:noreply,
             socket
             |> put_flash(:info, "Product saved")
             |> assign(:product_form, nil)
             |> assign(:selected_product, nil)
             |> reload_all()}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply,
             put_flash(socket, :error, "Save failed: #{changeset_error_summary(changeset)}")}

          {:error, :not_found} ->
            {:noreply, put_flash(socket, :error, "Product not found")}
        end

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, reason)}
    end
  end

  @impl true
  def handle_event("new_provider_product", _params, socket) do
    {:noreply, assign_provider_product_form(socket, nil)}
  end

  @impl true
  def handle_event("edit_provider_product", %{"id" => id}, socket) do
    provider_product_id = GameServer.UUIDv7.cast_or_nil(id)

    case provider_product_id && Payments.get_provider_product(provider_product_id) do
      nil -> {:noreply, put_flash(socket, :error, "Provider SKU not found")}
      provider_product -> {:noreply, assign_provider_product_form(socket, provider_product)}
    end
  end

  @impl true
  def handle_event("close_provider_product_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:provider_product_form, nil)
     |> assign(:selected_provider_product, nil)}
  end

  @impl true
  def handle_event("save_provider_product", %{"provider_product" => params}, socket) do
    case provider_product_attrs(params) do
      {:ok, attrs} ->
        result =
          case parse_id(params["id"]) do
            nil ->
              Payments.create_provider_product(attrs)

            id ->
              case Payments.get_provider_product(id) do
                nil -> {:error, :not_found}
                provider_product -> Payments.update_provider_product(provider_product, attrs)
              end
          end

        case result do
          {:ok, _provider_product} ->
            {:noreply,
             socket
             |> put_flash(:info, "Provider SKU saved")
             |> assign(:provider_product_form, nil)
             |> assign(:selected_provider_product, nil)
             |> reload_all()}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply,
             put_flash(socket, :error, "Save failed: #{changeset_error_summary(changeset)}")}

          {:error, :not_found} ->
            {:noreply, put_flash(socket, :error, "Provider SKU not found")}
        end

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, reason)}
    end
  end

  @impl true
  def handle_event("reconcile_stripe_purchase", %{"id" => id}, socket) do
    result =
      with purchase_id when is_binary(purchase_id) <- parse_id(id),
           %Payments.Purchase{} = purchase <- Payments.get_purchase(purchase_id) do
        Payments.reconcile_stripe_purchase(purchase)
      else
        _ -> {:error, :purchase_not_found}
      end

    case result do
      {:ok, %{result: reconcile_result}} ->
        {:noreply,
         socket
         |> put_flash(:info, stripe_reconcile_message(reconcile_result))
         |> reload_all()}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Stripe reconcile failed: #{admin_error(reason)}")
         |> reload_all()}
    end
  end

  defp section_pager(assigns) do
    ~H"""
    <div class="mt-4 flex flex-wrap items-center justify-between gap-3 text-sm">
      <div class="text-base-content/60">
        Page {@page} / {@total_pages} · {@count} total
      </div>
      <div class="join">
        <button
          type="button"
          class="btn btn-sm join-item"
          phx-click="section_page"
          phx-value-section={@section}
          phx-value-dir="prev"
          disabled={@page <= 1}
        >
          Prev
        </button>
        <button
          type="button"
          class="btn btn-sm join-item"
          phx-click="section_page"
          phx-value-section={@section}
          phx-value-dir="next"
          disabled={@page >= @total_pages}
        >
          Next
        </button>
      </div>
    </div>
    """
  end

  defp reload_all(socket) do
    socket
    |> assign(:store_adapters, Payments.provider_adapter_statuses())
    |> assign(:stats, Payments.admin_stats())
    |> assign(:all_products, Payments.list_products(include_inactive: true))
    |> reload_section(:products)
    |> reload_section(:provider_products)
    |> reload_section(:purchases)
    |> reload_section(:entitlements)
    |> reload_section(:provider_events)
    |> reload_section(:reconciliation_cursors)
  end

  defp reload_section(socket, section) do
    page = socket.assigns.pages[section] || 1
    page_size = socket.assigns.page_sizes[section] || @default_page_size
    opts = [page: page, page_size: page_size]

    {items, count} =
      case section do
        :products ->
          {Payments.list_admin_products(opts), Payments.count_products()}

        :provider_products ->
          {Payments.list_admin_provider_products(opts), Payments.count_provider_products()}

        :purchases ->
          {Payments.list_admin_purchases(opts), Payments.count_purchases()}

        :entitlements ->
          {Payments.list_admin_entitlements(opts), Payments.count_entitlements()}

        :provider_events ->
          {Payments.list_provider_events(opts), Payments.count_provider_events()}

        :reconciliation_cursors ->
          {Payments.list_reconciliation_cursors(opts), Payments.count_reconciliation_cursors()}
      end

    total_pages = max(1, div(count + page_size - 1, page_size))

    socket
    |> assign(section, items)
    |> assign(:counts, Map.put(socket.assigns.counts, section, count))
    |> assign(:total_pages, Map.put(socket.assigns.total_pages, section, total_pages))
  end

  defp assign_product_form(socket, nil) do
    params = %{
      "id" => "",
      "sku" => "",
      "title" => "",
      "description" => "",
      "kind" => "entitlement",
      "active" => "true",
      "grant_config_json" => "{}",
      "metadata_json" => "{}"
    }

    socket
    |> assign(:selected_product, nil)
    |> assign(:product_form, to_form(params, as: :product))
  end

  defp assign_product_form(socket, %Product{} = product) do
    params = %{
      "id" => product.id,
      "sku" => product.sku,
      "title" => product.title,
      "description" => product.description,
      "kind" => product.kind,
      "active" => product.active,
      "grant_config_json" => pretty_json(product.grant_config),
      "metadata_json" => pretty_json(product.metadata)
    }

    socket
    |> assign(:selected_product, product)
    |> assign(:product_form, to_form(params, as: :product))
  end

  defp assign_provider_product_form(socket, nil) do
    product_id = socket.assigns.all_products |> List.first() |> then(&(&1 && &1.id))

    params = %{
      "id" => "",
      "product_id" => product_id || "",
      "provider" => "stripe",
      "external_id" => "",
      "currency" => "USD",
      "unit_amount" => "",
      "active" => "true",
      "metadata_json" => "{}"
    }

    socket
    |> assign(:selected_provider_product, nil)
    |> assign(:provider_product_form, to_form(params, as: :provider_product))
  end

  defp assign_provider_product_form(socket, %ProviderProduct{} = provider_product) do
    params = %{
      "id" => provider_product.id,
      "product_id" => provider_product.product_id,
      "provider" => provider_product.provider,
      "external_id" => provider_product.external_id,
      "currency" => provider_product.currency,
      "unit_amount" => provider_product.unit_amount,
      "active" => provider_product.active,
      "metadata_json" => pretty_json(provider_product.metadata)
    }

    socket
    |> assign(:selected_provider_product, provider_product)
    |> assign(:provider_product_form, to_form(params, as: :provider_product))
  end

  defp product_attrs(params) do
    with {:ok, grant_config} <- decode_json_object(params["grant_config_json"], "Grant config"),
         {:ok, metadata} <- decode_json_object(params["metadata_json"], "Metadata") do
      {:ok,
       %{
         "sku" => params["sku"],
         "title" => params["title"],
         "description" => params["description"] || "",
         "kind" => params["kind"],
         "active" => parse_bool(params["active"]),
         "grant_config" => grant_config,
         "metadata" => metadata
       }}
    end
  end

  defp provider_product_attrs(params) do
    with {:ok, metadata} <- decode_json_object(params["metadata_json"], "Metadata") do
      {:ok,
       %{
         "product_id" => parse_id(params["product_id"]),
         "provider" => params["provider"],
         "external_id" => params["external_id"],
         "currency" => normalize_blank(params["currency"]),
         "unit_amount" => parse_int(params["unit_amount"]),
         "active" => parse_bool(params["active"]),
         "metadata" => metadata
       }}
    end
  end

  defp product_options(products) do
    Enum.map(products, fn product -> {"#{product.sku} (##{product.id})", product.id} end)
  end

  defp section_atom(section) when is_binary(section) do
    String.to_existing_atom(section)
  end

  defp parse_id(value), do: GameServer.UUIDv7.cast_or_nil(value)

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil
  defp parse_int(value) when is_integer(value), do: value

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_int(_value), do: nil

  defp parse_bool(value) when value in [true, "true", "on", "1", 1], do: true
  defp parse_bool(_value), do: false

  defp normalize_blank(nil), do: nil
  defp normalize_blank(""), do: nil
  defp normalize_blank(value) when is_binary(value), do: String.upcase(value)
  defp normalize_blank(value), do: value

  defp decode_json_object(value, _label) when value in [nil, ""], do: {:ok, %{}}

  defp decode_json_object(value, label) do
    case Jason.decode(value) do
      {:ok, map} when is_map(map) -> {:ok, map}
      {:ok, _} -> {:error, "#{label} must be a JSON object"}
      {:error, _} -> {:error, "#{label} is invalid JSON"}
    end
  end

  defp pretty_json(value) when is_map(value), do: Jason.encode!(value, pretty: true)
  defp pretty_json(_value), do: "{}"

  defp json_preview(nil), do: ""

  defp json_preview(value) when is_map(value),
    do: value |> Jason.encode!() |> String.slice(0, 2048)

  defp json_preview(_value), do: ""

  defp format_amount(nil, currency), do: "- #{currency || ""}"
  defp format_amount(amount, nil), do: to_string(amount)
  defp format_amount(amount, currency), do: "#{amount} #{currency}"

  defp active_badge(true),
    do: Phoenix.HTML.raw(~s(<span class="badge badge-success">active</span>))

  defp active_badge(false),
    do: Phoenix.HTML.raw(~s(<span class="badge badge-ghost">inactive</span>))

  defp provider_badge_class("stripe"), do: "badge-primary"
  defp provider_badge_class("apple"), do: "badge-neutral"
  defp provider_badge_class("google"), do: "badge-success"
  defp provider_badge_class("steam"), do: "badge-info"
  defp provider_badge_class(_provider), do: "badge-ghost"

  defp adapter_status_summary(%{provider: "stripe"} = status) do
    "checkout=#{yes_no(status.secret_key_configured)} webhook=#{yes_no(status.webhook_secret_configured)} env=#{status.environment}"
  end

  defp adapter_status_summary(%{provider: "google"} = status) do
    "package=#{yes_no(status.package_name_configured)} service_account=#{yes_no(status.service_account_configured)} rtdn=#{yes_no(status.rtdn_token_configured)} auto_ack=#{yes_no(status.auto_acknowledge)}"
  end

  defp adapter_status_summary(%{provider: "apple"} = status) do
    "bundle=#{yes_no(status.bundle_id_configured)} issuer=#{yes_no(status.issuer_id_configured)} key=#{yes_no(status.key_id_configured)} private_key=#{yes_no(status.private_key_configured)} env=#{status.environment}"
  end

  defp adapter_status_summary(%{provider: "steam"} = status) do
    "api_key=#{yes_no(status.api_key_configured)} app_id=#{yes_no(status.app_id_configured)} env=#{status.environment}"
  end

  defp adapter_status_summary(_status), do: "custom adapter"

  defp yes_no(true), do: "yes"
  defp yes_no(_value), do: "no"

  defp status_badge_class("completed"), do: "badge-success"
  defp status_badge_class(status) when status in ["refunded", "revoked"], do: "badge-error"

  defp status_badge_class(status) when status in ["pending", "requires_action"],
    do: "badge-warning"

  defp status_badge_class(_status), do: "badge-ghost"

  defp stripe_reconcile_available?(
         %{provider: "stripe", provider_transaction_id: "cs_" <> _rest} = p
       ) do
    p.status in ["pending", "requires_action", "failed", "cancelled"] or
      stripe_completed_subscription?(p)
  end

  defp stripe_reconcile_available?(_purchase), do: false

  defp stripe_completed_subscription?(%{status: "completed", product: %{kind: "subscription"}}),
    do: true

  defp stripe_completed_subscription?(_purchase), do: false

  defp stripe_reconcile_message(:fulfilled), do: "Stripe purchase fulfilled"
  defp stripe_reconcile_message(:cancelled), do: "Stripe purchase cancelled"
  defp stripe_reconcile_message(:failed), do: "Stripe purchase failed"
  defp stripe_reconcile_message(:still_open), do: "Stripe checkout still open"
  defp stripe_reconcile_message(:payment_processing), do: "Stripe payment still processing"
  defp stripe_reconcile_message(:already_completed), do: "Stripe purchase already completed"
  defp stripe_reconcile_message(:unchanged), do: "Stripe purchase left unchanged"
  defp stripe_reconcile_message(result), do: "Stripe reconcile finished: #{result}"

  defp admin_error(%Ecto.Changeset{} = changeset), do: changeset_error_summary(changeset)
  defp admin_error({:stripe_error, %{"message" => message}}) when is_binary(message), do: message
  defp admin_error(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp admin_error(reason), do: inspect(reason)

  defp entitlement_badge_class("active"), do: "badge-success"
  defp entitlement_badge_class("revoked"), do: "badge-error"
  defp entitlement_badge_class(_status), do: "badge-ghost"

  defp mode_badge_class("live"), do: "badge-success"
  defp mode_badge_class("test"), do: "badge-info"
  defp mode_badge_class(_mode), do: "badge-ghost"

  defp changeset_error_summary(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
    |> Enum.map_join("; ", fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
  end
end
