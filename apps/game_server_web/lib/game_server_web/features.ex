defmodule GameServerWeb.Features do
  @moduledoc """
  Toggles for the public, unauthenticated surface.

  Each flag gates a listing endpoint *and* the matching realtime channel and
  browser page together, so switching one off closes the whole route rather
  than leaving a second way in. All default to on; a deployment that does not
  want third parties browsing or scraping its data turns off what it does not
  need.

  Read through `GameServerWeb.Plugs.FeatureGate`, which 404s a disabled route.
  """

  use GameServer.Settings.Provider,
    app: :game_server_web,
    group: :features,
    label: "Public features"

  setting(:list_users, :boolean,
    default: true,
    doc: "GET /api/v1/users and /users/:id."
  )

  setting(:list_lobbies, :boolean,
    default: true,
    doc: "GET /api/v1/lobbies and the \"lobbies\" channel."
  )

  setting(:list_groups, :boolean,
    default: true,
    doc: "GET /api/v1/groups*, the \"groups\" channel and the /groups pages."
  )

  setting(:list_leaderboards, :boolean,
    default: true,
    doc: "Public GET/resolve /api/v1/leaderboards* and the /leaderboards pages."
  )

  setting(:list_quests, :boolean,
    default: true,
    doc: "Public GET /api/v1/quests* and the /quests page."
  )

  setting(:list_matchmaking, :boolean,
    default: true,
    doc: "GET /api/v1/matchmaking/stats. Own-ticket endpoints stay."
  )

  setting(:mailbox_preview, :boolean,
    default: false,
    doc:
      "Serve the in-browser mailbox at /dev/mailbox outside dev. Every sent email is readable there."
  )

  setting(:openapi, :boolean,
    default: true,
    doc: "OpenAPI spec + Swagger UI. A complete map of your API — consider off in production."
  )

  @doc "Whether the feature is currently on."
  @spec enabled?(atom()) :: boolean()
  def enabled?(feature) when is_atom(feature) do
    GameServer.Settings.get(__MODULE__, feature) != false
  end
end
