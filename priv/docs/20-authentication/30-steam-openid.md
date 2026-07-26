---
icon: hero-play-circle
---

# Steam OpenID Setup

[Steam Dev Portal](https://steamcommunity.com/dev)

## Get a Steam Web API Key

Visit the Steam Web API page at [https://steamcommunity.com/dev](https://steamcommunity.com/dev) and register your domain to get an **API key**.

## Configure Redirect Domain

Steam uses OpenID for sign-in. When registering your domain at [steamcommunity.com/dev](https://steamcommunity.com/dev) , enter your domain (e.g., `example.com` for production or `localhost:4000` for development).

| Environment | Domain to register |
|---|---|
| Development | `localhost:4000` |
| Production | `your-domain.com` |

## Configure Environment Variables

Set the following environment variable:

```bash
GAMEND_OAUTH_STEAM_API_KEY="your_steam_api_key_here"
```

## Test Steam Login

After configuring the API key:

1. Go to your app's login page
2. Click "Sign in with Steam"
3. Authorize with your Steam account
4. You should be redirected back and logged in

**Note:** For linking Steam to an existing account, go to `/users/settings` and click "Link Steam".
