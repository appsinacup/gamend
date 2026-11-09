---
icon: hero-play-circle-solid
---

# Steam OpenID Setup

[Steam Dev Portal](https://steamcommunity.com/dev)

## Get a Steam Web API key

Visit the Steam Web API page at [https://steamcommunity.com/dev](https://steamcommunity.com/dev) and register your domain to get an **API key**.

## Configure the redirect domain

Steam uses OpenID for sign-in. When registering your domain at [steamcommunity.com/dev](https://steamcommunity.com/dev), enter your domain (e.g., `example.com` for production or `localhost:4000` for development).

| Environment | Domain to register |
|---|---|
| Development | `localhost:4000` |
| Production | `your-domain.com` |

## Configure environment variables

Set these environment variables:

```bash
GAMEND_OAUTH_STEAM_API_KEY="your_steam_api_key_here"
GAMEND_OAUTH_STEAM_APP_ID="your_steam_app_id"
```

Browser sign-in needs only the API key. Game clients that sign in with a Steam
auth ticket (`POST /api/v1/auth/steam/callback`) also need the App ID: your
game's Steamworks App ID.

## Test Steam login

After configuring the API key:

1. Go to your app's login page
2. Click "Log in with Steam"
3. Authorize with your Steam account
4. You should be redirected back and logged in

**Note:** For linking Steam to an existing account, go to `/users/settings` and click "Link" next to Steam.
