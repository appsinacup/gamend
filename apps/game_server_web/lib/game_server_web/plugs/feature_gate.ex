defmodule GameServerWeb.Plugs.FeatureGate do
  @moduledoc """
  Plug that gates routes behind a `GameServerWeb.Features` flag.

  ## Usage

      plug GameServerWeb.Plugs.FeatureGate, feature: :openapi

  When the feature is off, requests are rejected with `404 Not Found` — the
  route reads as nonexistent rather than forbidden, so a disabled endpoint
  leaks nothing about what the deployment runs.
  """

  import Plug.Conn

  alias GameServerWeb.Features

  @behaviour Plug

  @impl true
  def init(opts), do: %{feature: Keyword.fetch!(opts, :feature)}

  @impl true
  def call(conn, %{feature: feature}) do
    if Features.enabled?(feature) do
      conn
    else
      conn
      |> send_resp(404, "Not Found")
      |> halt()
    end
  end

  @doc "Whether the feature is enabled. Delegates to `GameServerWeb.Features`."
  @spec enabled?(atom()) :: boolean()
  defdelegate enabled?(feature), to: Features
end
