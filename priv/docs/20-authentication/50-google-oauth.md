---
icon: hero-globe-alt
---

# Google OAuth Setup

[Google Cloud Console](https://console.cloud.google.com/)

## Create a Google Cloud project

Go to the [Google Cloud Console](https://console.cloud.google.com/)

1. Click "Select a project" at the top
2. Click "New Project"
3. Enter a project name (e.g., "Gamend")
4. Click "Create"

## Enable People API

In your Google Cloud project:

1. Go to "APIs & Services" → "Library"
2. Search for "Google People API"
3. Click on it and click "Enable"

## Configure the OAuth consent screen

Go to "APIs & Services" → "OAuth consent screen":

1. Select "External" user type
2. Click "Create"
3. Fill in app name (e.g., "Gamend")
4. Add your email as user support email
5. Add authorized domains (e.g., example.com)
6. Add developer contact email
7. Click "Save and Continue"
8. Add scopes: email, profile
9. Click "Save and Continue"
10. Add test users if needed (optional for development)

## Create OAuth credentials

Go to "APIs & Services" → "Credentials":

1. Click "Create Credentials" → "OAuth client ID"
2. Select "Web application"
3. Enter a name (e.g., "Gamend Web")
4. Add authorized redirect URIs:
 Development: http://localhost:4000/auth/google/callback Production: https://example.com/auth/google/callback
5. Click "Create"
6. Copy the Client ID and Client Secret

## Configure environment variables

Set these environment variables:

```bash
GAMEND_OAUTH_GOOGLE_CLIENT_ID="your_client_id.apps.googleusercontent.com"
GAMEND_OAUTH_GOOGLE_CLIENT_SECRET="your_client_secret"
```

## Test Google login

After deploying with the secrets:

1. Go to your app's login page
2. Click "Sign in with Google"
3. Choose your Google account
4. You should be redirected back and logged in
