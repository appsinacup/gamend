defmodule Gamend.Payments.StripeSetup do
  @moduledoc """
  The Stripe account set up the way this code reads it, from a script
  (`mix gamend.stripe.setup`, a host's own task for its prices), never by
  hand-copying a checklist:

    * the **webhook endpoint**: the URL, the API version this server pins
      (`ProviderConfig.stripe_api_version/0`) and exactly the events
      `Gamend.Payments.StripeEvents` handles (`webhook_events/0`);
    * the **customer portal**'s default configuration: cancel at the period
      end with no proration, card update, invoice history, and no plan
      switching (a plan is changed through the host's own page);
    * a **product** and its **prices**, for a host that describes them
      (`ensure_product/2`, `ensure_price/2`).

  Every function compares what Stripe holds with what is wanted, and changes
  it only when called with `apply: true`. A step answers a list of findings,
  `%{area, status, message}`:

    * `:ok` — Stripe holds what is wanted;
    * `:pending` — it does not, and `apply: true` would fix it;
    * `:changed` — it did not, and it was fixed;
    * `:manual` — it does not, and only a person can fix it (in the
      Dashboard, or with an option that replaces something);
    * `:error` — Stripe answered an error.

  Two things Stripe allows only once, and the steps say so instead of
  guessing: a webhook endpoint's API version is set when it is created (a new
  version is a new endpoint, `recreate: true`, with a new signing secret), and
  a price's amount, currency, interval and tax behaviour never change (a new
  price takes the old one's lookup key, and the old one is archived).

  Calls go through the `:stripe_client` the adapter uses, on the pinned API
  version, as maps.
  """

  alias Gamend.Payments.ProviderConfig

  # Exactly what `StripeEvents.process_stripe_event/1` handles. A new handler
  # adds its event here, or the endpoint never sends it.
  @webhook_events ~w(
    checkout.session.completed
    checkout.session.async_payment_succeeded
    checkout.session.async_payment_failed
    checkout.session.expired
    charge.succeeded
    charge.refunded
    refund.created
    refund.updated
    charge.refund.updated
    charge.dispute.created
    charge.dispute.funds_withdrawn
    charge.dispute.closed
    customer.subscription.updated
    customer.subscription.deleted
  )

  @portal_features %{
    "subscription_cancel" => %{
      "enabled" => true,
      "mode" => "at_period_end",
      "proration_behavior" => "none"
    },
    "payment_method_update" => %{"enabled" => true},
    "invoice_history" => %{"enabled" => true},
    # Plans change through the host's page, which picks the price (a country
    # band) and the first charge; the portal would do neither.
    "subscription_update" => %{"enabled" => false}
  }

  @type status :: :ok | :pending | :changed | :manual | :error
  @type finding :: %{area: String.t(), status: status(), message: String.t()}

  @doc "The events the webhook endpoint must send: the ones this server handles."
  @spec webhook_events() :: [String.t()]
  def webhook_events, do: @webhook_events

  @doc "What the customer portal's default configuration must hold."
  @spec portal_features() :: map()
  def portal_features, do: @portal_features

  @doc "Whether a list of findings needs anything: a pending, manual or failed one."
  @spec drift?([finding()]) :: boolean()
  def drift?(findings), do: Enum.any?(findings, &(&1.status in [:pending, :manual, :error]))

  # ── Webhook ──────────────────────────────────────────────────────────────

  @doc """
  The webhook endpoint for `url`. Options: `apply:` (make changes),
  `recreate:` (with `apply:`, replace an endpoint on another API release:
  a new endpoint, the old one disabled). A new endpoint's signing secret is
  in its finding's message, the only time Stripe shows it.
  """
  @spec ensure_webhook(String.t(), keyword()) :: [finding()]
  def ensure_webhook(url, opts \\ []) when is_binary(url) do
    case call(:list_webhook_endpoints, [%{limit: 100}]) do
      {:ok, %{"data" => endpoints}} ->
        # A disabled endpoint at the same URL is the one `recreate: true`
        # replaced: harmless, named so it can be deleted.
        {enabled, disabled} =
          endpoints
          |> Enum.filter(&(&1["url"] == url))
          |> Enum.split_with(&(&1["status"] != "disabled"))

        target =
          case {enabled, disabled} do
            {[], []} ->
              create_webhook(url, opts)

            {[endpoint], _disabled} ->
              check_webhook(endpoint, url, opts) ++ Enum.map(disabled, &replaced_note/1)

            {[], [endpoint]} ->
              check_webhook(endpoint, url, opts)

            {several, _disabled} ->
              [
                manual(
                  "webhook",
                  "#{length(several)} endpoints share #{url}: keep one in the Dashboard"
                )
              ]
          end

        target ++ strays(endpoints, url)

      {:error, reason} ->
        [error("webhook", reason)]
    end
  end

  defp replaced_note(endpoint),
    do: ok("webhook", "#{endpoint["id"]} at the same URL is disabled: delete it in the Dashboard")

  # Another endpoint on the same host is an old one (a wrong path, a test):
  # it is never matched, so it would go on receiving events beside the right
  # one and failing them. Deleting is a person's call, in the Dashboard; one
  # this script disabled when it replaced it is already harmless.
  defp strays(endpoints, url) do
    host = URI.parse(url).host

    for %{"url" => other} = endpoint <- endpoints,
        other != url,
        URI.parse(other).host == host,
        endpoint["status"] != "disabled" do
      manual(
        "webhook",
        "another endpoint on #{host}: #{endpoint["id"]} at #{other}, still enabled. " <>
          "Delete it in the Dashboard if it is an old one"
      )
    end
  end

  defp create_webhook(url, opts) do
    if opts[:apply] do
      case call(:create_webhook_endpoint, [webhook_params(url)]) do
        {:ok, endpoint} ->
          # The signing secret rides apart from the message, so whoever prints
          # the findings decides where it goes (`--secret-file`).
          created =
            changed(
              "webhook",
              "created #{endpoint["id"]} for #{url} on #{endpoint["api_version"]}, " <>
                "#{length(@webhook_events)} events. Its signing secret is shown only now: " <>
                "set it as the webhook secret in .env"
            )

          [Map.put(created, :secret, endpoint["secret"])]

        {:error, reason} ->
          [error("webhook", reason)]
      end
    else
      [pending("webhook", "no endpoint for #{url}: would create one on #{api_version()}")]
    end
  end

  defp webhook_params(url) do
    %{
      url: url,
      enabled_events: @webhook_events,
      api_version: api_version(),
      description: "Gamend payments"
    }
  end

  # Status and events are read only off an endpoint that stays: a replaced
  # one is disabled, and one on the wrong version is to be replaced.
  defp check_webhook(endpoint, url, opts) do
    case version_finding(endpoint, url, opts) do
      [%{status: :ok}] = right ->
        right ++ [status_finding(endpoint, opts), events_finding(endpoint, opts)]

      replaced_or_manual ->
        replaced_or_manual
    end
  end

  defp version_finding(endpoint, url, opts) do
    version = endpoint["api_version"]
    wanted = ProviderConfig.stripe_api_release(api_version())

    cond do
      is_binary(version) and ProviderConfig.stripe_api_release(version) == wanted ->
        [ok("webhook", "#{endpoint["id"]} on #{version}")]

      opts[:apply] && opts[:recreate] ->
        replace_webhook(endpoint, url)

      true ->
        [
          manual(
            "webhook",
            "#{endpoint["id"]} is on #{version || "the account's default version"}, not the #{wanted} release. " <>
              "Stripe sets an endpoint's version only when it is created: rerun with --recreate --apply " <>
              "(a new endpoint and a new signing secret; the old one is disabled)"
          )
        ]
    end
  end

  defp replace_webhook(endpoint, url) do
    with [%{status: :changed} = created] <- create_webhook(url, apply: true),
         {:ok, _} <- call(:update_webhook_endpoint, [endpoint["id"], %{disabled: true}]) do
      [
        created,
        changed(
          "webhook",
          "disabled the old endpoint #{endpoint["id"]}: delete it in the Dashboard"
        )
      ]
    else
      [%{} | _] = findings -> findings
      {:error, reason} -> [error("webhook", reason)]
    end
  end

  defp status_finding(%{"status" => "enabled"} = endpoint, _opts),
    do: ok("webhook", "#{endpoint["id"]} is enabled")

  defp status_finding(endpoint, opts) do
    if opts[:apply] do
      case call(:update_webhook_endpoint, [endpoint["id"], %{disabled: false}]) do
        {:ok, _} -> changed("webhook", "enabled #{endpoint["id"]}")
        {:error, reason} -> error("webhook", reason)
      end
    else
      pending("webhook", "#{endpoint["id"]} is #{endpoint["status"]}: would enable it")
    end
  end

  defp events_finding(endpoint, opts) do
    current = endpoint["enabled_events"] || []
    missing = @webhook_events -- current
    extra = current -- @webhook_events

    cond do
      missing == [] and extra == [] ->
        ok(
          "webhook",
          "#{endpoint["id"]} sends exactly the #{length(@webhook_events)} events handled"
        )

      opts[:apply] ->
        case call(:update_webhook_endpoint, [endpoint["id"], %{enabled_events: @webhook_events}]) do
          {:ok, _} ->
            changed("webhook", "events set; added #{list(missing)}, removed #{list(extra)}")

          {:error, reason} ->
            error("webhook", reason)
        end

      true ->
        pending("webhook", "events: missing #{list(missing)}, extra #{list(extra)}")
    end
  end

  # ── Customer portal ──────────────────────────────────────────────────────

  @doc """
  The customer portal's default configuration against `portal_features/0`.
  Stripe makes the default one when the portal is activated in the
  Dashboard; without it the portal cannot open, and that is a manual step.
  """
  @spec ensure_portal(keyword()) :: [finding()]
  def ensure_portal(opts \\ []) do
    case call(:list_portal_configurations, [%{is_default: true, limit: 1}]) do
      {:ok, %{"data" => [config | _]}} ->
        check_portal(config, opts)

      {:ok, _none} ->
        [
          manual(
            "portal",
            "not activated: Settings -> Billing -> Customer portal -> Activate, then rerun"
          )
        ]

      {:error, reason} ->
        [error("portal", reason)]
    end
  end

  defp check_portal(config, opts) do
    features = config["features"] || %{}

    wrong =
      for {feature, wanted} <- @portal_features,
          {key, value} <- wanted,
          get_in(features, [feature, key]) != value,
          do:
            "#{feature}.#{key}=#{inspect(get_in(features, [feature, key]))} (want #{inspect(value)})"

    cond do
      wrong == [] ->
        [
          ok(
            "portal",
            "#{config["id"]}: cancel at period end, card update, invoices, no plan switching"
          )
        ]

      opts[:apply] ->
        case call(:update_portal_configuration, [config["id"], %{features: @portal_features}]) do
          {:ok, _} -> [changed("portal", "#{config["id"]}: set #{Enum.join(wrong, ", ")}")]
          {:error, reason} -> [error("portal", reason)]
        end

      true ->
        [pending("portal", "#{config["id"]}: #{Enum.join(wrong, ", ")}")]
    end
  end

  # ── Product and prices ───────────────────────────────────────────────────

  @doc """
  A product by its fixed id (`id`, `name`, `tax_code`, optional
  `metadata`), its name, tax code and `active` brought in line. When there is
  no product with that id, `adopt:` (a product id already in use, e.g. the
  one the configured prices are on) is used instead, so a product made by
  hand is kept rather than doubled; only with neither is one created.

  Returns `{product_id | nil, findings}`: the product the prices belong on.
  On a check that would create it, the id it would get.
  """
  @spec ensure_product(map(), keyword()) :: {String.t() | nil, [finding()]}
  def ensure_product(%{id: id} = wanted, opts \\ []) do
    case fetch(:retrieve_product, id) do
      {:ok, product} -> {id, check_product(product, wanted, opts)}
      :missing -> adopt_or_create_product(wanted, opts)
      {:error, reason} -> {nil, [error("product", reason)]}
    end
  end

  defp adopt_or_create_product(%{adopt: adopt} = wanted, opts) when is_binary(adopt) do
    case fetch(:retrieve_product, adopt) do
      {:ok, product} ->
        note =
          ok(
            "product",
            "no #{wanted.id}; using #{adopt}, the product the configured prices are on"
          )

        {adopt, [note | check_product(product, wanted, opts)]}

      :missing ->
        create_product(wanted, opts)

      {:error, reason} ->
        {nil, [error("product", reason)]}
    end
  end

  defp adopt_or_create_product(wanted, opts), do: create_product(wanted, opts)

  defp create_product(wanted, opts) do
    if opts[:apply] do
      case call(:create_product, [Map.take(wanted, [:id, :name, :tax_code, :metadata])]) do
        {:ok, product} ->
          {product["id"],
           [
             changed(
               "product",
               "created #{product["id"]} (#{product["name"]}, #{product["tax_code"]})"
             )
           ]}

        {:error, reason} ->
          {nil, [error("product", reason)]}
      end
    else
      {wanted.id,
       [
         pending(
           "product",
           "no product #{wanted.id}: would create #{wanted.name}, tax code #{wanted.tax_code}"
         )
       ]}
    end
  end

  @doc "The product a price is on, or nil when the price does not exist."
  @spec price_product(String.t()) :: String.t() | nil
  def price_product(price_id) when is_binary(price_id) do
    case fetch(:retrieve_price, price_id) do
      {:ok, price} -> object_id(price["product"])
      _missing_or_error -> nil
    end
  end

  defp check_product(product, wanted, opts) do
    current = %{
      name: product["name"],
      tax_code: object_id(product["tax_code"]),
      active: product["active"]
    }

    target = %{name: wanted.name, tax_code: wanted.tax_code, active: true}
    wrong = for {key, value} <- target, current[key] != value, do: {key, value}

    cond do
      wrong == [] ->
        [ok("product", "#{product["id"]}: #{product["name"]}, #{current.tax_code}")]

      opts[:apply] ->
        case call(:update_product, [product["id"], Map.new(wrong)]) do
          {:ok, _} -> [changed("product", "#{product["id"]}: set #{describe(wrong)}")]
          {:error, reason} -> [error("product", reason)]
        end

      true ->
        [pending("product", "#{product["id"]}: #{describe(wrong, current)}")]
    end
  end

  @doc """
  A price found by its `lookup_key`, against `product`, `unit_amount`,
  `currency`, `recurring` (`%{interval: "year"}`, or nil for one payment)
  and `tax_behavior`. Missing: created. Archived: unarchived. Different in
  anything Stripe never changes on a price: a new price takes the lookup key
  and the old one is archived (with `apply: true`).

  Returns `{price_id | nil, findings}`: the id that holds the lookup key
  after the step, for the host's list of price ids.
  """
  @spec ensure_price(map(), keyword()) :: {String.t() | nil, [finding()]}
  def ensure_price(%{lookup_key: key} = wanted, opts \\ []) do
    case call(:list_prices, [%{lookup_keys: [key], limit: 1}]) do
      {:ok, %{"data" => [price | _]}} -> check_price(price, wanted, opts)
      {:ok, _none} -> adopt_or_create_price(wanted, opts)
      {:error, reason} -> {nil, [error("price #{key}", reason)]}
    end
  end

  # No price holds the lookup key yet. A price already in use (`adopt:`, the
  # id the host's config names) that is what is wanted gets the key, and
  # nothing new is made: prices set up by hand before this script existed
  # stay, with the ids already in the config.
  defp adopt_or_create_price(%{adopt: adopt} = wanted, opts) when is_binary(adopt) do
    area = "price #{wanted.lookup_key}"

    case fetch(:retrieve_price, adopt) do
      {:ok, price} ->
        case fixed_differences(price, wanted) do
          [] ->
            adopt_price(price, wanted, opts)

          fixed ->
            {id, findings} = create_price(wanted, opts, false)
            note = "the configured #{adopt} differs (#{Enum.join(fixed, ", ")}), so a new price"
            {id, [%{hd(findings) | message: note <> ": " <> hd(findings).message} | tl(findings)]}
        end

      :missing ->
        {id, findings} = create_price(wanted, opts, false)
        {id, [manual(area, "the configured #{adopt} does not exist on this account") | findings]}

      {:error, reason} ->
        {nil, [error(area, reason)]}
    end
  end

  defp adopt_or_create_price(wanted, opts), do: create_price(wanted, opts, false)

  defp adopt_price(price, wanted, opts) do
    area = "price #{wanted.lookup_key}"

    if opts[:apply] do
      params =
        wanted
        |> Map.take([:lookup_key, :nickname, :metadata])
        |> Map.reject(fn {_key, value} -> is_nil(value) end)
        |> Map.merge(%{transfer_lookup_key: true})
        |> Map.merge(mutable_fixes(price, wanted))

      case call(:update_price, [price["id"], params]) do
        {:ok, _} ->
          {price["id"],
           [
             changed(
               area,
               "adopted #{price["id"]} (#{price_summary(price)}): gave it the lookup key"
             )
           ]}

        {:error, reason} ->
          {price["id"], [error(area, reason)]}
      end
    else
      {price["id"],
       [
         pending(
           area,
           "would adopt #{price["id"]} (#{price_summary(price)}): give it the lookup key"
         )
       ]}
    end
  end

  defp create_price(wanted, opts, transfer?) do
    area = "price #{wanted.lookup_key}"

    if opts[:apply] do
      params =
        wanted
        |> Map.take([
          :lookup_key,
          :product,
          :unit_amount,
          :currency,
          :recurring,
          :tax_behavior,
          :nickname,
          :metadata
        ])
        |> Map.reject(fn {_key, value} -> is_nil(value) end)
        |> Map.put(:transfer_lookup_key, transfer?)

      case call(:create_price, [params]) do
        {:ok, price} ->
          {price["id"], [changed(area, "created #{price["id"]}: #{price_summary(price)}")]}

        {:error, reason} ->
          {nil, [error(area, reason)]}
      end
    else
      {nil, [pending(area, "would create #{wanted_summary(wanted)}")]}
    end
  end

  defp check_price(price, wanted, opts) do
    area = "price #{wanted.lookup_key}"
    fixed = fixed_differences(price, wanted)

    cond do
      fixed != [] and opts[:apply] ->
        with {new_id, [%{status: :changed} = created]} <- create_price(wanted, opts, true),
             {:ok, _} <- call(:update_price, [price["id"], %{active: false}]) do
          {new_id,
           [created, changed(area, "archived #{price["id"]} (#{Enum.join(fixed, ", ")})")]}
        else
          {:error, reason} -> {price["id"], [error(area, reason)]}
          other -> other
        end

      fixed != [] ->
        {price["id"],
         [
           pending(
             area,
             "#{price["id"]} differs (#{Enum.join(fixed, ", ")}): would replace it with a new price"
           )
         ]}

      (fixes = mutable_fixes(price, wanted)) != %{} and opts[:apply] ->
        case call(:update_price, [price["id"], fixes]) do
          {:ok, _} -> {price["id"], [changed(area, "#{price["id"]}: set #{describe(fixes)}")]}
          {:error, reason} -> {price["id"], [error(area, reason)]}
        end

      (fixes = mutable_fixes(price, wanted)) != %{} ->
        {price["id"], [pending(area, "#{price["id"]}: would set #{describe(fixes)}")]}

      true ->
        {price["id"], [ok(area, "#{price["id"]}: #{price_summary(price)}")]}
    end
  end

  # What may still change on a price: an archived one comes back, and a tax
  # behaviour left "unspecified" (a price made in the Dashboard without
  # choosing) may be set, once.
  defp mutable_fixes(price, wanted) do
    %{}
    |> then(&if(price["active"] != true, do: Map.put(&1, :active, true), else: &1))
    |> then(fn fixes ->
      if price["tax_behavior"] == "unspecified" and is_binary(wanted[:tax_behavior]),
        do: Map.put(fixes, :tax_behavior, wanted[:tax_behavior]),
        else: fixes
    end)
  end

  # What a price never changes after it is created. An "unspecified" tax
  # behaviour is not among them (`mutable_fixes/2` sets it).
  defp fixed_differences(price, wanted) do
    tax =
      if price["tax_behavior"] == "unspecified",
        do: price["tax_behavior"],
        else: wanted[:tax_behavior] || price["tax_behavior"]

    [
      {"product", object_id(price["product"]), wanted.product},
      {"amount", price["unit_amount"], wanted.unit_amount},
      {"currency", price["currency"], String.downcase(wanted.currency)},
      {"interval", get_in(price, ["recurring", "interval"]), recurring_interval(wanted)},
      {"tax_behavior", price["tax_behavior"], tax}
    ]
    |> Enum.reject(fn {_name, have, want} -> have == want end)
    |> Enum.map(fn {name, have, want} -> "#{name} #{inspect(have)} not #{inspect(want)}" end)
  end

  defp recurring_interval(%{recurring: %{interval: interval}}), do: interval
  defp recurring_interval(_wanted), do: nil

  defp price_summary(price) do
    interval = get_in(price, ["recurring", "interval"])

    "#{price["unit_amount"]} #{price["currency"]}#{if interval, do: " / " <> interval, else: " once"}, " <>
      "tax #{price["tax_behavior"]}"
  end

  defp wanted_summary(wanted) do
    interval = recurring_interval(wanted)

    "#{wanted.unit_amount} #{wanted.currency}#{if interval, do: " / " <> interval, else: " once"}, " <>
      "tax #{wanted[:tax_behavior]} on #{wanted.product}"
  end

  # ── Calls ────────────────────────────────────────────────────────────────

  defp call(function, args) do
    with {:ok, secret_key} <- secret_key() do
      opts = [api_key: secret_key, api_version: api_version(), response_as: :map]

      case apply(client(), function, Enum.concat(args, [opts])) do
        {:ok, result} -> {:ok, normalize(result)}
        {:error, reason} -> {:error, reason}
      end
    end
  rescue
    exception -> {:error, Exception.message(exception)}
  end

  defp client,
    do: Application.get_env(:gamend_core, :stripe_setup_client, __MODULE__.Client)

  defp api_version, do: ProviderConfig.stripe_api_version()

  defp secret_key do
    case ProviderConfig.stripe_secret_key() do
      key when is_binary(key) and key != "" -> {:ok, key}
      _ -> {:error, "no Stripe secret key for the #{ProviderConfig.environment()} environment"}
    end
  end

  # Stripe's 404: `resource_missing` in the raw error, or the status alone.
  # A read that may find nothing: `:missing` for Stripe's 404.
  defp fetch(function, id) do
    case call(function, [id]) do
      {:ok, object} -> {:ok, object}
      {:error, reason} -> if missing?(reason), do: :missing, else: {:error, reason}
    end
  end

  defp missing?(%{extra: %{raw_error: %{"code" => "resource_missing"}}}), do: true
  defp missing?(%{extra: %{http_status: 404}}), do: true
  defp missing?(%{"code" => "resource_missing"}), do: true
  defp missing?(_reason), do: false

  defp normalize(%_struct{} = struct), do: struct |> Map.from_struct() |> normalize()

  defp normalize(map) when is_map(map),
    do: Map.new(map, fn {k, v} -> {to_string(k), normalize(v)} end)

  defp normalize(list) when is_list(list), do: Enum.map(list, &normalize/1)
  defp normalize(value), do: value

  defp object_id(%{"id" => id}), do: id
  defp object_id(id), do: id

  defp list([]), do: "none"
  defp list(items), do: Enum.join(items, ", ")

  defp describe(pairs),
    do: Enum.map_join(pairs, ", ", fn {key, value} -> "#{key}=#{inspect(value)}" end)

  defp describe(pairs, current),
    do:
      Enum.map_join(pairs, ", ", fn {key, value} ->
        "#{key} #{inspect(current[key])} not #{inspect(value)}"
      end)

  defp ok(area, message), do: %{area: area, status: :ok, message: message}
  defp pending(area, message), do: %{area: area, status: :pending, message: message}
  defp changed(area, message), do: %{area: area, status: :changed, message: message}
  defp manual(area, message), do: %{area: area, status: :manual, message: message}

  defp error(area, %{message: message}) when is_binary(message), do: error(area, message)

  defp error(area, reason) when is_binary(reason),
    do: %{area: area, status: :error, message: reason}

  defp error(area, reason), do: %{area: area, status: :error, message: inspect(reason)}

  defmodule Client do
    @moduledoc false
    # The SDK calls the setup makes; a test sets `:stripe_setup_client`.

    alias Stripe.BillingPortal.Configuration
    alias Stripe.WebhookEndpoint

    def list_webhook_endpoints(params, opts), do: WebhookEndpoint.list(params, opts)
    def create_webhook_endpoint(params, opts), do: WebhookEndpoint.create(params, opts)

    def update_webhook_endpoint(id, params, opts),
      do: WebhookEndpoint.update(id, params, opts)

    def list_portal_configurations(params, opts),
      do: Configuration.list(params, opts)

    def update_portal_configuration(id, params, opts),
      do: Configuration.update(id, params, opts)

    def retrieve_product(id, opts), do: Stripe.Product.retrieve(id, %{}, opts)
    def create_product(params, opts), do: Stripe.Product.create(params, opts)
    def update_product(id, params, opts), do: Stripe.Product.update(id, params, opts)
    def list_prices(params, opts), do: Stripe.Price.list(params, opts)
    def retrieve_price(id, opts), do: Stripe.Price.retrieve(id, %{}, opts)
    def create_price(params, opts), do: Stripe.Price.create(params, opts)
    def update_price(id, params, opts), do: Stripe.Price.update(id, params, opts)
  end
end
