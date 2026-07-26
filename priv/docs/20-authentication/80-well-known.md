---
icon: hero-link
---

# Mobile app links / .well-known

## Where to put the files

Place them under the web app's static folder so they are served at the web root:

```text
apps/game_server_web/priv/static/.well-known/assetlinks.json
apps/game_server_web/priv/static/.well-known/apple-app-site-association
```

Example files are included in the repo with a .example suffix.

## Serving rules & notes

- Served at: https://your-domain/.well-known/assetlinks.json and https://your-domain/.well-known/apple-app-site-association
- After adding or updating these files, restart or redeploy so they are included in the release
