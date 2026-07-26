defmodule GameServerWeb.Api.V1.EconomyController do
  @moduledoc """
  Read-only wallet access for the current user. Balance mutations are
  server-authoritative (hooks / admin), never a raw client endpoint.
  """
  use GameServerWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias GameServer.Accounts.Scope
  alias GameServer.Economy
  alias GameServerWeb.Pagination
  alias OpenApiSpex.Schema

  tags(["Economy"])

  @error_schema %Schema{type: :object, properties: %{error: %Schema{type: :string}}}

  @ledger_entry_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      currency: %Schema{type: :string},
      delta: %Schema{type: :integer},
      balance_after: %Schema{type: :integer},
      reason: %Schema{type: :string},
      metadata: %Schema{type: :object},
      inserted_at: %Schema{type: :string, format: :"date-time"}
    }
  }

  operation(:wallet,
    operation_id: "get_current_user_wallet",
    summary: "Current user's currency balances",
    security: [%{"authorization" => []}],
    responses: [
      ok:
        {"Balances", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{type: :object, additionalProperties: %Schema{type: :integer}}
           }
         }},
      unauthorized: {"Not authenticated", "application/json", @error_schema}
    ]
  )

  def wallet(conn, _params) do
    user = Scope.user(conn.assigns.current_scope)
    json(conn, %{data: Economy.balances(user.id)})
  end

  operation(:ledger,
    operation_id: "list_current_user_ledger",
    summary: "Current user's ledger history",
    security: [%{"authorization" => []}],
    parameters: [
      currency: [in: :query, schema: %Schema{type: :string}, required: false],
      page: [in: :query, schema: %Schema{type: :integer, default: 1}, required: false],
      page_size: [in: :query, schema: %Schema{type: :integer, default: 25}, required: false]
    ],
    responses: [
      ok:
        {"Ledger", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{type: :array, items: @ledger_entry_schema},
             meta: %Schema{type: :object}
           }
         }},
      unauthorized: {"Not authenticated", "application/json", @error_schema}
    ]
  )

  def ledger(conn, params) do
    user = Scope.user(conn.assigns.current_scope)
    {page, page_size} = GameServerWeb.Pagination.params(params)

    filters = [user_id: user.id, currency: params["currency"], page: page, page_size: page_size]
    entries = Economy.list_ledger(filters)
    total = Economy.count_ledger(filters)

    json(conn, %{
      data: Enum.map(entries, &serialize/1),
      meta: Pagination.meta(page, page_size, length(entries), total)
    })
  end

  operation(:inventory,
    operation_id: "get_current_user_inventory",
    summary: "Current user's item quantities",
    security: [%{"authorization" => []}],
    responses: [
      ok:
        {"Inventory", "application/json",
         %Schema{
           type: :object,
           properties: %{
             data: %Schema{type: :object, additionalProperties: %Schema{type: :integer}}
           }
         }},
      unauthorized: {"Not authenticated", "application/json", @error_schema}
    ]
  )

  def inventory(conn, _params) do
    user = Scope.user(conn.assigns.current_scope)
    json(conn, %{data: GameServer.Inventory.inventory(user.id)})
  end

  defp serialize(entry) do
    %{
      id: entry.id,
      currency: entry.currency || "",
      delta: entry.delta,
      balance_after: entry.balance_after,
      reason: entry.reason,
      metadata: entry.metadata,
      inserted_at: entry.inserted_at
    }
  end
end
