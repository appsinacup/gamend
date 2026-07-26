defmodule GameServerWeb.Auth.OptionalPipeline do
  @moduledoc """
  Guardian pipeline for optional API JWT authentication.

  Unlike `GameServerWeb.Auth.Pipeline`, this pipeline does NOT require
  authentication — it simply loads the user if a valid Bearer token is
  present in the Authorization header, otherwise continues with
  `current_scope` set to an anonymous scope.

  Use this on public endpoints that can optionally enrich responses when the
  caller is authenticated (e.g. showing user progress on quests).
  """

  use Guardian.Plug.Pipeline,
    otp_app: :game_server_web,
    module: GameServerWeb.Auth.Guardian,
    error_handler: GameServerWeb.Auth.ErrorHandler

  plug Guardian.Plug.VerifyHeader, scheme: "Bearer", allow_blank: true
  plug Guardian.Plug.LoadResource, allow_blank: true
  plug GameServerWeb.Auth.AssignCurrentScope
end
