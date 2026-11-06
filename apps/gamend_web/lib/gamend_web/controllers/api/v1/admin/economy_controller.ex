defmodule GamendWeb.Api.V1.Admin.EconomyController do
  @moduledoc """
  Admin control over wallets: grant/spend against any user's balance and browse
  wallets and the ledger.
  """
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gamend.Economy
  alias Gamend.Inventory
  alias GamendWeb.Schemas

  alias GamendWeb.Schemas.{
    AdminInventoryItemPage,
    AdminLedgerEntryPage,
    AdminWalletPage,
    ItemQuantityResponse,
    WalletBalanceResponse
  }

  alias OpenApiSpex.Schema

  tags(["Admin – Economy"])

  @mutate_body {
    "Wallet change",
    "application/json",
    %Schema{
      type: :object,
      properties: %{
        user_id: %Schema{type: :string, format: :uuid},
        currency: %Schema{type: :string},
        amount: %Schema{type: :integer, minimum: 1},
        reason: %Schema{type: :string},
        idempotency_key: %Schema{type: :string}
      },
      required: [:user_id, :currency, :amount]
    }
  }

  operation(:wallets,
    operation_id: "admin_list_wallets",
    summary: "List wallets (admin)",
    security: [%{"authorization" => []}],
    parameters: [
      user_id: [in: :query, schema: %Schema{type: :string, format: :uuid}, required: false],
      currency: [in: :query, schema: %Schema{type: :string}, required: false],
      page: [in: :query, schema: %Schema{type: :integer, default: 1}, required: false],
      page_size: [in: :query, schema: %Schema{type: :integer, default: 25}, required: false]
    ],
    responses: [
      ok: {"Wallets", "application/json", AdminWalletPage},
      unauthorized: Schemas.error("Not authenticated"),
      forbidden: Schemas.error("Admin required")
    ]
  )

  def wallets(conn, params) do
    {page, page_size} = GamendWeb.Pagination.params(params)

    filters = [
      user_id: params["user_id"],
      currency: params["currency"],
      page: page,
      page_size: page_size
    ]

    wallets = Economy.list_wallets(filters)
    total = Economy.count_wallets(filters)

    rows =
      Enum.map(
        wallets,
        &%{id: &1.id, user_id: &1.user_id, currency: &1.currency, balance: &1.balance}
      )

    reply_page(conn, rows, page, page_size, total)
  end

  operation(:ledger,
    operation_id: "admin_list_ledger",
    summary: "List ledger entries (admin)",
    security: [%{"authorization" => []}],
    parameters: [
      user_id: [in: :query, schema: %Schema{type: :string, format: :uuid}, required: false],
      currency: [in: :query, schema: %Schema{type: :string}, required: false],
      page: [in: :query, schema: %Schema{type: :integer, default: 1}, required: false],
      page_size: [in: :query, schema: %Schema{type: :integer, default: 25}, required: false]
    ],
    responses: [
      ok: {"Ledger, newest first", "application/json", AdminLedgerEntryPage},
      unauthorized: Schemas.error("Not authenticated"),
      forbidden: Schemas.error("Admin required")
    ]
  )

  def ledger(conn, params) do
    {page, page_size} = GamendWeb.Pagination.params(params)

    filters = [
      user_id: params["user_id"],
      currency: params["currency"],
      page: page,
      page_size: page_size
    ]

    entries = Economy.list_ledger(filters)
    total = Economy.count_ledger(filters)

    rows =
      Enum.map(entries, fn e ->
        %{
          id: e.id,
          user_id: e.user_id,
          currency: e.currency || "",
          delta: e.delta,
          balance_after: e.balance_after,
          reason: e.reason || "",
          metadata: e.metadata || %{},
          inserted_at: e.inserted_at
        }
      end)

    reply_page(conn, rows, page, page_size, total)
  end

  operation(:grant,
    operation_id: "admin_grant_currency",
    summary: "Grant currency to a user (admin)",
    security: [%{"authorization" => []}],
    request_body: @mutate_body,
    responses: [
      ok:
        {"Granted: the balance after, also for an idempotency_key already applied",
         "application/json", WalletBalanceResponse},
      bad_request: Schemas.error("Missing or invalid fields"),
      not_found: Schemas.error("No such user (user_not_found)"),
      unprocessable_entity: Schemas.error("The ledger row is invalid, e.g. a long reason"),
      unauthorized: Schemas.error("Not authenticated"),
      forbidden: Schemas.error("Admin required")
    ]
  )

  def grant(conn, params), do: mutate(conn, params, :grant)

  operation(:spend,
    operation_id: "admin_spend_currency",
    summary: "Spend currency from a user (admin)",
    security: [%{"authorization" => []}],
    request_body: @mutate_body,
    responses: [
      ok:
        {"Spent: the balance after, also for an idempotency_key already applied",
         "application/json", WalletBalanceResponse},
      bad_request: Schemas.error("Missing or invalid fields"),
      forbidden: Schemas.error("Admin required, or insufficient funds (insufficient_funds)"),
      not_found: Schemas.error("No such user (user_not_found)"),
      unprocessable_entity: Schemas.error("The ledger row is invalid, e.g. a long reason"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  def spend(conn, params), do: mutate(conn, params, :spend)

  defp mutate(conn, %{"user_id" => uid, "currency" => currency} = params, op)
       when is_binary(uid) and is_binary(currency) do
    amount = parse_amount(params["amount"])

    opts = [
      reason: params["reason"] || "admin_#{op}",
      idempotency_key: params["idempotency_key"]
    ]

    with {:ok, amount} <- positive(amount),
         {:ok, balance} <- apply(Economy, op, [uid, currency, amount, opts]) do
      reply_data(conn, %{user_id: uid, currency: currency, balance: balance})
    else
      :invalid_amount ->
        reply_error(conn, :bad_request, "invalid_amount", "amount must be a positive integer")

      {:error, reason} ->
        refusal(conn, reason)
    end
  end

  defp mutate(conn, _params, _op),
    do:
      reply_error(
        conn,
        :bad_request,
        "missing_param",
        "user_id, currency and amount are required"
      )

  operation(:items,
    operation_id: "admin_list_inventory",
    summary: "List inventory item stacks (admin)",
    security: [%{"authorization" => []}],
    parameters: [
      user_id: [in: :query, schema: %Schema{type: :string, format: :uuid}, required: false],
      item: [in: :query, schema: %Schema{type: :string}, required: false],
      page: [in: :query, schema: %Schema{type: :integer, default: 1}, required: false],
      page_size: [in: :query, schema: %Schema{type: :integer, default: 25}, required: false]
    ],
    responses: [
      ok: {"Items", "application/json", AdminInventoryItemPage},
      unauthorized: Schemas.error("Not authenticated"),
      forbidden: Schemas.error("Admin required")
    ]
  )

  def items(conn, params) do
    {page, page_size} = GamendWeb.Pagination.params(params)
    filters = [user_id: params["user_id"], item: params["item"], page: page, page_size: page_size]

    items = Inventory.list_items(filters)
    total = Inventory.count_items(filters)

    rows =
      Enum.map(
        items,
        &%{
          id: &1.id,
          user_id: &1.user_id,
          item: &1.item,
          quantity: &1.quantity,
          metadata: &1.metadata || %{}
        }
      )

    reply_page(conn, rows, page, page_size, total)
  end

  operation(:grant_item,
    operation_id: "admin_grant_item",
    summary: "Grant items to a user (admin)",
    security: [%{"authorization" => []}],
    request_body:
      {"Item change", "application/json",
       %Schema{
         type: :object,
         properties: %{
           user_id: %Schema{type: :string, format: :uuid},
           item: %Schema{type: :string},
           quantity: %Schema{type: :integer, minimum: 1}
         },
         required: [:user_id, :item, :quantity]
       }},
    responses: [
      ok: {"Granted: the quantity after", "application/json", ItemQuantityResponse},
      bad_request: Schemas.error("Missing or invalid fields"),
      not_found: Schemas.error("No such user (user_not_found)"),
      unprocessable_entity: Schemas.error("The item or ledger row is invalid"),
      unauthorized: Schemas.error("Not authenticated"),
      forbidden: Schemas.error("Admin required")
    ]
  )

  def grant_item(conn, params), do: item_mutate(conn, params, :grant_item)

  operation(:consume_item,
    operation_id: "admin_consume_item",
    summary: "Consume items from a user (admin)",
    security: [%{"authorization" => []}],
    responses: [
      ok: {"Consumed: the quantity after", "application/json", ItemQuantityResponse},
      bad_request: Schemas.error("Missing or invalid fields"),
      forbidden: Schemas.error("Admin required, or insufficient items (insufficient_items)"),
      not_found: Schemas.error("No such user (user_not_found)"),
      unprocessable_entity: Schemas.error("The ledger row is invalid"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  def consume_item(conn, params), do: item_mutate(conn, params, :consume_item)

  defp item_mutate(conn, %{"user_id" => uid, "item" => item} = params, op)
       when is_binary(uid) and is_binary(item) do
    qty = parse_amount(params["quantity"] || params["amount"])

    with {:ok, qty} <- positive(qty),
         {:ok, quantity} <- apply(Inventory, op, [uid, item, qty, []]) do
      reply_data(conn, %{user_id: uid, item: item, quantity: quantity})
    else
      :invalid_amount ->
        reply_error(conn, :bad_request, "invalid_amount", "quantity must be a positive integer")

      {:error, reason} ->
        refusal(conn, reason)
    end
  end

  defp item_mutate(conn, _params, _op),
    do:
      reply_error(conn, :bad_request, "missing_param", "user_id, item and quantity are required")

  # A refusal from `Gamend.Economy` / `Gamend.Inventory`, answered with the
  # status `GamendWeb.ErrorStatus` gives it: `invalid_currency` and
  # `invalid_item` 400, `insufficient_funds` and `insufficient_items` 403,
  # `user_not_found` 404. A replayed `idempotency_key` is no error: both
  # contexts answer it with the balance it left. A ledger or balance row the
  # database refused is a changeset under a tag, a ledger `reason` longer than
  # its 64 characters among them.
  defp refusal(conn, {tag, %Ecto.Changeset{} = changeset})
       when tag in [:ledger_error, :wallet_error, :item_error],
       do: unprocessable(conn, changeset)

  defp refusal(conn, reason), do: reply_reason(conn, reason)

  defp positive(amount) when is_integer(amount) and amount > 0, do: {:ok, amount}
  defp positive(_amount), do: :invalid_amount

  defp parse_amount(n) when is_integer(n), do: n

  defp parse_amount(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} -> n
      _ -> :error
    end
  end

  defp parse_amount(_), do: :error
end
