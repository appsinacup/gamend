---
icon: hero-globe-alt-solid
---

# Custom Domains

A server on Gamend Cloud can answer at a name of yours, such as `play.mygame.com`. You add two DNS records and press Check. There are no environment variables to set: Gamend Cloud tells the server its name.

## Set it up

1. Open your server's **Domain** tab, enter the full name and press **Save**. A server has one name.
2. At your DNS provider, add the two records below, with the values the tab shows. Keep them afterwards.
3. If your provider can proxy the name, turn that off. On Cloudflare that is the gray cloud, **DNS only**.
4. Press **Check**. Once the `TXT` record is found, the server restarts and answers at `https://play.mygame.com`. Its certificate is made on the first visit, so that visit takes a few seconds.

| Type | Name | Value |
|---|---|---|
| `CNAME` | `play.mygame.com` | `your-server.gamend.cloud` |
| `TXT` | `_gamend.play.mygame.com` | the token on the tab |

Most providers want the name without your domain: `play` and `_gamend.play`. The tab shows both forms.

A root domain such as `mygame.com` often cannot have a `CNAME`. Add the `A` record the tab shows instead. Use the `CNAME` where you can, because it follows the server when it moves.

## Your game's address

Point your game's clients at the new address. The server also keeps answering at `your-server.gamend.cloud`, and its links keep that name.

To answer only at your name, use **Gamend address** on the same tab once the name is verified. The server restarts and its links use your name. If players sign in through an OAuth provider, change the redirect URLs there to the new name.

## Changing or removing a name

A new name gets a new token, so it needs its own `TXT` record. Changing or removing a name detaches the old one at once and brings the `gamend.cloud` name back.

## When it does not work

| What you see | What to check |
|---|---|
| `TXT record not found yet.` | The record's name is `_gamend.` plus your full name, and its value is exactly the token on the tab |
| A certificate or connection error in the browser | The name is verified, it points at the server, and the record is DNS only |
| The page opens but keeps reconnecting | The server runs an older Gamend. Deploy a current version |

## Running Gamend yourself

Set `GAMEND_HTTP_HOST` to your name, and list any others in `GAMEND_HTTP_OTHER_HOSTS`. Your own proxy handles the certificates. See [Deployment](/docs/deployment).
