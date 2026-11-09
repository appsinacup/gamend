---
icon: hero-code-bracket-solid
---

# GitHub OAuth Setup

[GitHub Developer Settings](https://github.com/settings/developers)

Either a **GitHub App** or an **OAuth App** works: both hand out the client
id and secret Gamend needs, and the login flow is the same. A GitHub App is
the one to pick when the server will also act on repositories on a player's
behalf; an OAuth App is enough for sign-in alone.

## Create a GitHub App

Go to [GitHub Apps](https://github.com/settings/apps) (or your organization's
Settings → Developer settings → GitHub Apps):

1. Click "New GitHub App"
2. Enter the app name (e.g., "Gamend") and homepage URL
3. Under "Identifying and authorizing users", set the callback URL (below)
   and tick "Request user authorization (OAuth) during installation" if the
   App is also installed on repositories
4. Under "Permissions" → "Account permissions", set "Email addresses" to
   "Read-only" so sign-in can read the player's primary email. Without it a
   player is created with no email, as Steam players are
5. Click "Create GitHub App"

## Or create an OAuth App

Go to [OAuth Apps](https://github.com/settings/developers):

1. Click "New OAuth App"
2. Enter the application name and homepage URL
3. Set the authorization callback URL (below)
4. Click "Register application"

An OAuth App reads emails through the `user:email` scope, which Gamend does not
request: it takes whatever the profile shows publicly.

## Configure the callback URL

Add the callback URL for each environment (a GitHub App accepts several, an
OAuth App one):

```text
Development: http://localhost:4000/auth/github/callback
Production:  https://example.com/auth/github/callback
```

## Get the app credentials

On the app's settings page:

1. Copy the "Client ID"
2. Click "Generate a new client secret" and copy it — GitHub shows it once

They look like this:

```text
Client ID:     Iv1.0123456789abcdef
Client secret: 0123456789abcdef0123456789abcdef01234567
```

## Configure environment variables

Set these environment variables:

```bash
GAMEND_OAUTH_GITHUB_CLIENT_ID="your_client_id"
GAMEND_OAUTH_GITHUB_CLIENT_SECRET="your_client_secret"
```

## Test GitHub login

After deploying with the secrets:

1. Go to your app's login page
2. Click "Log in with GitHub"
3. Authorize the application with your GitHub account
4. You should be redirected back and logged in

## What Gamend stores

The GitHub user id (`users.github_id`, GitHub's integer id as a string), the
name (falling back to the login), the avatar, and the primary email from
`/user/emails` when the App may read it — marked verified only when GitHub says
so, which is what lets the sign-in attach to an existing account with that
email. A profile whose email cannot be read signs in with no email.
