---
icon: hero-device-phone-mobile
---

# Apple Sign In Setup

[Apple Developer Portal](https://developer.apple.com/account/resources/identifiers/list)

## Apple Developer Account

You need an [Apple Developer Account](https://developer.apple.com/programs/) ($99/year)

## Create App ID

Go to [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list)

1. Click the "+" button to create a new identifier
2. Select "App IDs" and click Continue
3. Select "App" type and click Continue
4. Enter a description (e.g., "Game Server")
5. Enter a Bundle ID (e.g., com.yourcompany.gameserver)
6. Scroll down and check "Sign in with Apple"
7. Click Continue and Register

## Create Service ID (Client ID)

Back in Certificates, Identifiers & Profiles:

1. Click "+" to create new identifier
2. Select "Services IDs" and click Continue
3. Enter description (e.g., "Game Server Web")
4. Enter identifier (e.g., com.yourcompany.gameserver.web) - This is your CLIENT_ID
5. Check "Sign in with Apple"
6. Click "Configure" next to Sign in with Apple
7. Select your App ID as the Primary App ID
8. Add these domains and redirect URLs:
 Domain: example.com Return URL: https://example.com/auth/apple/callback
9. Click Save, then Continue, then Register

com.yourcompany.gameserver.web

## Create Private Key

In Certificates, Identifiers & Profiles, go to Keys:

1. Click "+" to create a new key
2. Enter a name (e.g., "Game Server Sign in with Apple Key")
3. Check "Sign in with Apple"
4. Click "Configure" next to Sign in with Apple
5. Select your App ID as the Primary App ID
6. Click Save, then Continue
7. Click Register
8. **Download the .p8 file** - you can only download this once!
9. Note the Key ID (e.g., ABC123XYZ) shown on the confirmation page

## Get Your Team ID

Find your Team ID:

1. Go to [Membership Details](https://developer.apple.com/account/#/membership/)
2. Your Team ID is listed there (10 characters, e.g., A1B2C3D4E5)

## Configure Environment Variables

Set these environment variables:

```bash
GAMEND_OAUTH_APPLE_CLIENT_ID="com.yourcompany.gameserver.web"
GAMEND_OAUTH_APPLE_IOS_CLIENT_ID="com.yourcompany.gameserver.ios"
GAMEND_OAUTH_APPLE_TEAM_ID="A1B2C3D4E5"
GAMEND_OAUTH_APPLE_KEY_ID="ABC123XYZ"
GAMEND_OAUTH_APPLE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----"
"MIGTAgEAMBMGByq...your key content..."
"-----END PRIVATE KEY-----"
```

## Test Apple Sign In

After deploying with the secrets:

1. Go to your app's login page
2. Click "Sign in with Apple"
3. Authorize the application with your Apple ID
4. You should be redirected back and logged in
