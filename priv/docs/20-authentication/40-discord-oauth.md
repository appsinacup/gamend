---
icon: hero-chat-bubble-left-right
---

# Discord OAuth Setup

[Discord Developer Portal](https://discord.com/developers/applications)

## Create Discord Application

Go to the [Discord Developer Portal](https://discord.com/developers/applications)

1. Click "New Application" in the top right
2. Give your app a name (e.g., "Game Server")
3. Go to the "OAuth2" → "General" tab

## Configure Redirect URIs

In the OAuth2 General settings, add these redirect URIs:

```yaml
Development: http://localhost:4000/auth/discord/callback
Production: https://example.com/auth/discord/callback
```

These are the URLs Discord will redirect users back to after authorization.

## Get Application Credentials

From the OAuth2 General tab, copy these values:

Client ID

Found at the top of OAuth2 General

```text
123456789012345678
```

Client Secret

Click "Reset Secret" to generate

```text
abcdefghijklmnopqrstuvwx
```

## Configure Application Secrets

Set these environment variables:

```bash
GAMEND_OAUTH_DISCORD_CLIENT_ID="your_client_id_here"
GAMEND_OAUTH_DISCORD_CLIENT_SECRET="your_client_secret_here"
```

## Test Discord Login

After deploying with the secrets:

1. Go to your app's login page
2. Click "Sign in with Discord"
3. Authorize the application on Discord
4. You should be redirected back and logged in
