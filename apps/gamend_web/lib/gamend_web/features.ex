defmodule GamendWeb.Features do
  @moduledoc """
  Toggles for the public, unauthenticated surface.

  Each flag gates a listing endpoint *and* the matching realtime channel and
  browser page together, so switching one off closes the whole route rather
  than leaving a second way in. All default to on; a deployment that does not
  want third parties browsing or scraping its data turns off what it does not
  need.

  `web_groups`, `web_friends`, `web_chat`, `web_tournaments` and `web_store`
  are website-only: they close a page and every link to it (`drop_disabled/1`)
  and leave the API to the game client, so a host can park a feature on the
  site without breaking the game.

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
      "Player-supplied images: avatars (POST /api/v1/me/avatar*) and group icons (POST /api/v1/groups/:id/icon*). Objects land in public storage and are served without authentication, so on a service children can reach this is an unscreened image surface — turn it off unless the game actually uses it and you have a way to screen what arrives."
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

  setting(:web_groups, :boolean,
    default: true,
    doc:
      "Groups on the website: the /groups pages, the Groups tab in account settings, and every nav, footer or page link marked `\"feature\": \"web_groups\"`. The groups API and the game client are untouched — `list_groups` gates the public listing."
  )

  setting(:web_chat, :boolean,
    default: true,
    doc:
      "Chat on the website: the /chat page, its link in the account menu, the Open links on chat notifications, and every link marked `\"feature\": \"web_chat\"`. The chat API and the game client are untouched."
  )

  setting(:web_friends, :boolean,
    default: true,
    doc:
      "Friends on the website: the Friends tab in account settings, the View link on friend-request notifications, and the \"Friends and groups\" row on the Notifications tab (shown while `web_friends` or `web_groups` is on). The friends API and the game client are untouched."
  )

  setting(:web_tournaments, :boolean,
    default: true,
    doc:
      "Tournaments on the website: the /tournaments pages and every nav, footer or page link marked `\"feature\": \"web_tournaments\"`. The tournaments API and the game client are untouched — `list_tournaments` gates the public listing."
  )

  setting(:web_store, :boolean,
    default: true,
    doc:
      "The store on the website: the /store pages (every active product, any provider row), the Open Store button in account settings, and every link marked `\"feature\": \"web_store\"`. Off for a host that sells through its own page instead. The payments API and the game client are untouched."
  )

  setting(:list_payments_catalog, :boolean,
    default: true,
    doc:
      "Public GET /api/v1/payments/catalog: every active product with its provider row, id and price. Off for a host that sells through its own page, where the price shown depends on who asks (a country band) — the listing names every row, cheaper ones included."
  )

  setting(:stripe_checkout_api, :boolean,
    default: true,
    doc:
      "POST /api/v1/payments/checkout/stripe: a signed-in client opens a Stripe Checkout for any active Stripe row it names. Off for a host that sells only through its own page (which calls `Gamend.Payments.create_stripe_checkout/3` itself and picks the row), so a client cannot pick a row the page would not offer. Webhooks, the store page (`web_store`) and the other providers are untouched."
  )

  setting(:list_leaderboards, :boolean,
    default: true,
    doc: "Public GET/resolve /api/v1/leaderboards* and the /leaderboards pages."
  )

  setting(:list_quests, :boolean,
    default: true,
    doc: "Public GET /api/v1/quests* and the /quests page."
  )

  setting(:list_tournaments, :boolean,
    default: true,
    doc: "Public GET /api/v1/tournaments* and the /tournaments pages."
  )

  setting(:play, :boolean,
    default: true,
    doc:
      "The /play page, which hands a signed-in player a token for the game client. Off, it also closes every theme page and link marked `\"feature\": \"play\"` and every guide whose front matter says `feature: play` (a collection registered with `visible: {GamendWeb.Features, :doc_visible?}`): a host whose game is not out yet hides it from the site in one switch. The game client's API is untouched."
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
  Drops every map whose `"feature"` names a switched-off flag, at any depth:
  a list item, or a map's value (a whole theme page under `"pages"`, which
  then answers 404).

  Theme config (navigation, footer, page buttons) is host-authored, so a link
  to a page a flag closes carries `"feature": "web_groups"` and disappears with
  the page. An unknown name keeps the entry: hiding on a typo would be silent.
  """
  @spec drop_disabled(term()) :: term()
  def drop_disabled(list) when is_list(list) do
    for item <- list, not disabled_entry?(item), do: drop_disabled(item)
  end

  def drop_disabled(map) when is_map(map) and not is_struct(map) do
    for {key, value} <- map,
        not disabled_entry?(value),
        into: %{},
        do: {key, drop_disabled(value)}
  end

  def drop_disabled(other), do: other

  @doc "The flags as configured, for cache keys that depend on them."
  @spec configured() :: keyword()
  def configured, do: Application.get_env(:gamend_web, __MODULE__, [])

  defp disabled_entry?(%{"feature" => name}) when is_binary(name) do
    case Enum.find(__settings__(), &(Atom.to_string(&1.key) == name)) do
      %{key: key, type: :boolean} -> not enabled?(key)
      _ -> false
    end
  end

  defp disabled_entry?(_item), do: false

  @doc """
  Whether a guide is shown: false when its front matter names a switched-off
  flag (`feature: play`). The `:visible` hook of a `Gamend.Content`
  collection, so a page about a feature the site has closed goes with it.
  """
  @spec doc_visible?(map()) :: boolean()
  def doc_visible?(%{meta: %{"feature" => name}}) when is_binary(name),
    do: not disabled_entry?(%{"feature" => name})

  def doc_visible?(_doc), do: true

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
