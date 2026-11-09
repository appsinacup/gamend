defmodule GamendWeb.Features do
  @moduledoc """
  Toggles for the public, unauthenticated surface.

  Each flag gates a listing endpoint *and* the matching realtime channel and
  browser page together, so switching one off closes the whole route rather
  than leaving a second way in. All default to on; a deployment that does not
  want third parties browsing or scraping its data turns off what it does not
  need.

  A page a product does not have is not a flag: leave it out of the router
  (`except:` in `GamendWeb.Router.Shared`).

  Read through `GamendWeb.Plugs.FeatureGate`, which 404s a disabled route.
  """

  use Gamend.Settings.Provider,
    app: :gamend_web,
    group: :features,
    label: "Public features"

  setting(:list_users, :boolean,
    default: true,
    doc: "GET /api/v1/users and /users/:id."
  )

  setting(:user_image_uploads, :boolean,
    default: true,
    doc:
      "Player-supplied images: avatars (POST /api/v1/me/avatar*, the upload form on the account tab, and the copy of a sign-in provider's picture made by `Gamend.Accounts.AvatarMirror`) and group icons (POST /api/v1/groups/:id/icon*). The site's icons, to pick instead (`Gamend.Icons`), stay. Objects land in public storage and are served without authentication, so on a service children can reach this is an unscreened image surface — turn it off unless the game actually uses it and you have a way to screen what arrives."
  )

  setting(:public_user_metadata_keys, :list,
    default: [],
    doc:
      "Top-level `user.metadata` keys GET /api/v1/users and /users/:id may return. Empty means none. Those endpoints are unauthenticated, so anything named here is world-readable and findable by name prefix — never list a key holding position, routing or contact data."
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
    doc:
      "Public GET /api/v1/quests*, the /quests page and the \"Quests and rewards\" row on the Notifications tab. Achievements are quests of kind `achievement`, so this is them too."
  )

  setting(:list_tournaments, :boolean,
    default: true,
    doc: "Public GET /api/v1/tournaments* and the /tournaments pages."
  )

  setting(:list_matchmaking, :boolean,
    default: true,
    doc: "GET /api/v1/matchmaking/stats. Own-ticket endpoints stay."
  )

  setting(:public_stats, :boolean,
    default: true,
    doc:
      "The unauthenticated stats endpoints: GET /api/v1/stats, /api/v1/users/stats, /api/v1/lobbies/stats, /api/v1/parties/stats, /api/v1/quests/stats, /api/v1/signaling/stats and /api/v1/matchmaking/stats, plus the /stats page. Aggregate counts only, never per-row data — but they do reveal how busy the server is."
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
    Gamend.Settings.get(__MODULE__, feature) != false
  end

  @doc """
  Top-level `user.metadata` keys the public user endpoints may return.

  Default-deny: an empty list — the default — strips metadata entirely. A host
  that wants a badge on a search result opts that one section back in rather
  than the whole map.
  """
  @spec public_user_metadata_keys() :: [String.t()]
  def public_user_metadata_keys do
    case Gamend.Settings.get(__MODULE__, :public_user_metadata_keys) do
      keys when is_list(keys) -> Enum.filter(keys, &is_binary/1)
      _other -> []
    end
  end
end
