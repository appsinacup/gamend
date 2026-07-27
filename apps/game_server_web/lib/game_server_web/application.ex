defmodule GameServerWeb.Application do
  @moduledoc """
  OTP application for the GameServerWeb Phoenix endpoint.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      GameServerWeb.SignalingServer
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: GameServerWeb.Supervisor)
  end
end
