defmodule GamendWeb.Api.V1.PreferenceController do
  @moduledoc """
  `PUT /api/v1/me/preferences` (`key`, `value`): a preference the client
  sets on the signed-in account, as the site's page does with
  `PUT /preferences` (`Gamend.Accounts.Preferences.put_client/3`) — the
  theme, the device's time zone, and what the host allows. It reads them
  back as the row `preferences`, which moves with every change.
  """
  use GamendWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gamend.Accounts.Preferences
  alias Gamend.Accounts.Scope
  alias GamendWeb.Schemas
  alias GamendWeb.Schemas.OkResponse
  alias OpenApiSpex.Schema

  tags(["Users"])

  operation(:update,
    operation_id: "update_current_user_preference",
    summary: "Set one of the current user's preferences",
    description:
      "Saves `value` under `key` on the account: the theme (`dark`, `light`, or `system`, " <>
        "which removes it), `timezone` (the device's IANA zone, kept unless the user picked " <>
        "one by hand), or a key the host allows with one of its values. Read back as the KV " <>
        "row `preferences` (owner only). Answers 422 invalid_preference for a key or value " <>
        "not allowed.",
    request_body: {
      "Preference payload",
      "application/json",
      %Schema{
        type: :object,
        properties: %{
          key: %Schema{type: :string},
          value: %Schema{type: :string}
        },
        required: [:key, :value]
      }
    },
    security: [%{"authorization" => []}],
    responses: [
      ok: {"Saved", "application/json", OkResponse},
      unprocessable_entity: Schemas.error("A key or value not allowed"),
      unauthorized: Schemas.error("Not authenticated")
    ]
  )

  def update(conn, %{"key" => key, "value" => value}) when is_binary(key) and is_binary(value) do
    case Preferences.put_client(Scope.user(conn.assigns.current_scope), key, value) do
      {:ok, _user} -> reply_ok(conn)
      {:error, _reason} -> invalid(conn)
    end
  end

  def update(conn, _params), do: invalid(conn)

  defp invalid(conn), do: reply_error(conn, :unprocessable_entity, "invalid_preference")
end
