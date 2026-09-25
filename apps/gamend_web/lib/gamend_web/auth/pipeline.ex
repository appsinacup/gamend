defmodule GamendWeb.Auth.Pipeline do
  @moduledoc """
  Guardian pipeline for API JWT authentication.

  This pipeline verifies JWT tokens from the Authorization header
  and loads the current user into the connection assigns.
  """

  use Guardian.Plug.Pipeline,
    otp_app: :gamend_web,
    module: GamendWeb.Auth.Guardian,
    error_handler: GamendWeb.Auth.ErrorHandler

  # A personal API token (`gamend_pat_…`) is verified first and put in place
  # as if it were an access token; everything below then runs on it as is.
  plug GamendWeb.Auth.ApiTokenAuth

  # `claims:` pins the token type. Without it Guardian verifies only the
  # signature, so a 30-day refresh token authenticated every API route as if it
  # were a 15-minute access token — which defeats the point of the short access
  # TTL. Every issuer sets the type explicitly (`token_type: "access"`).
  plug Guardian.Plug.VerifyHeader, scheme: "Bearer", claims: %{"typ" => "access"}
  plug Guardian.Plug.EnsureAuthenticated
  plug Guardian.Plug.LoadResource
  plug GamendWeb.Auth.AssignCurrentScope
end
