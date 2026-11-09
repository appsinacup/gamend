---
icon: hero-link-solid
---

# Mobile app links / .well-known

## Where to put the files

Place them under the host app's static folder (repo root `priv/static`) so they are served at the web root:

```text
priv/static/.well-known/assetlinks.json
priv/static/.well-known/apple-app-site-association
```

Example files are included in that folder with a .example suffix.

## Serving rules & notes

- Served at: https://your-domain/.well-known/assetlinks.json and https://your-domain/.well-known/apple-app-site-association
- After adding or updating these files, restart or redeploy so they are included in the release
