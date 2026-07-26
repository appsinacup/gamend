---
icon: hero-user-group
---

# Facebook OAuth Setup

[Facebook Developers Portal](https://developers.facebook.com/)

## Create Facebook App

Go to the [Facebook Developers Portal](https://developers.facebook.com/)

1. Click "My Apps" in the top right
2. Click "Create App"
3. Select the use case that fits your needs (often "Other" or "Authenticate and request data from users with Facebook Login")
4. Click "Next"
5. Select app type (usually "Business" for most web apps, or "None" if available)
6. Click "Next"
7. Enter app name (e.g., "Game Server")
8. Enter contact email
9. Click "Create App"

## Add Facebook Login Product

In your Facebook App dashboard:

1. Find "Facebook Login" in the product list
2. Click "Set Up"
3. Select "Web" as the platform
4. Enter your site URL (e.g., https://example.com)
5. Click "Save" and continue

## Configure OAuth Redirect URIs

Go to "Facebook Login" → "Settings":

1. Add these Valid OAuth Redirect URIs:
 Development: http://localhost:4000/auth/facebook/callback Production: https://example.com/auth/facebook/callback
2. Click "Save Changes"

## Get App Credentials

Go to "Settings" → "Basic":

1. Copy the "App ID" (this is your Client ID)
2. Click "Show" next to "App Secret" and copy it (this is your Client Secret)

Your Credentials

App ID: 1234567890123456

App Secret: abcdef1234567890abcdef1234567890

## Make App Public (Production)

For production use, switch to live mode:

1. Complete all required fields in "Settings" → "Basic"
2. Add a Privacy Policy URL
3. Add a Terms of Service URL (optional)
4. Select a category for your app
5. Toggle the switch at the top from "Development" to "Live"

## Configure Environment Variables

Set these environment variables:

```bash
GAMEND_OAUTH_FACEBOOK_CLIENT_ID="your_app_id"
GAMEND_OAUTH_FACEBOOK_CLIENT_SECRET="your_app_secret"
```

## Test Facebook Login

After deploying with the secrets:

1. Go to your app's login page
2. Click "Sign in with Facebook"
3. Authorize the application with your Facebook account
4. You should be redirected back and logged in
