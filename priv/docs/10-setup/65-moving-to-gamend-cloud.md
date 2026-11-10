---
icon: hero-arrow-up-tray-solid
---

# Moving to Gamend Cloud

Move a server you host yourself to Gamend Cloud from its website: export up to three files, upload them on the new server's **Backups** tab, and press **Import**. The old server keeps running until you stop it.

## Before you start

Create the server on Gamend Cloud first, with the same database as the old one: a Postgres dump cannot go onto a SQLite server, or the other way. Use your own repository when you create it if the old server runs your own code, on the same Gamend version or a newer one.

| File | Holds | Where it comes from |
|---|---|---|
| `gamend.env` | Settings, with secrets in the clear | **Download .env** on `/admin/settings` |
| `gamend.dump` | A Postgres database | `pg_dump -Fc` |
| `gamend.db` | A SQLite database | `gamend export` |
| `files.tar` | Stored files, with `storage/` inside | `gamend export` |

Every file is optional and can be as large as the server's disk. A database must be named `.dump` or `.db` and stored files `.tar`.

## Export

On Postgres, dump the database where it runs:

```bash
pg_dump -Fc -U <user> <database> > gamend.dump
```

With Docker Compose:

```bash
docker compose exec -T db pg_dump -Fc -U <user> <database> > gamend.dump
```

For a SQLite database and the stored files, use whichever fits how you run the server. It works while the server is running. On Postgres it writes only `files.tar`.

```bash
gamend export /path/to/export                               # the download
bin/my_app eval 'Gamend.Release.export("/path/to/export")'  # a release
mix host.export /path/to/export                             # an Elixir host
```

A host deployed with `rebuild.sh` writes all of them with one command: see [Moving to another host](/docs/deployment#moving-to-another-host).

### Stored files on S3

A server on S3, Cloudflare R2 included, has no stored files to export. Its `GAMEND_STORAGE_*` settings come in with the settings file and the new server reads the same bucket, so leave out `files.tar`.

To put them on the new server's own disk instead, leave those settings out, copy the bucket into a folder named `storage` and pack that. For R2:

```bash
aws s3 sync s3://my-bucket storage --endpoint-url https://<account>.r2.cloudflarestorage.com
```

```bash
tar -cf files.tar storage
```

Links already saved with your `GAMEND_STORAGE_PUBLIC_URL` keep pointing there, so leave that bucket up.

## Import

1. Open the new server's **Backups** tab. Under **Import**, upload each file on its row. An upload you never import is deleted after a day.
2. Press **Import**. The server stops, its database, stored files and settings are replaced, and it starts again. The uploads are then deleted.
3. Sign in with an account from the old server. Its accounts replace the ones the new server had.

| In the settings file | What happens |
|---|---|
| A setting the **Settings** tab lists | Set on the server |
| `GAMEND_AUTH_SECRET_KEY_BASE` | Kept, so players stay signed in |
| An empty value | Skipped |
| Database, address, TLS, cluster, `GAMEND_STORAGE_DIR` | Ignored: Gamend Cloud sets these |
| `GAMEND_SECRETS_KEYS` | Ignored, so what a plugin saved with `Gamend.Secrets` cannot be read |

## Try it before you switch

You can import as often as you like, so make a test copy while the old server runs. Leave out its waiting jobs, or the copy sends the same mail and webhooks again:

```bash
pg_dump -Fc --exclude-table-data=public.oban_jobs -U <user> <database> > gamend.dump
```

On SQLite, run this on the exported `gamend.db`, never the live one:

```bash
sqlite3 gamend.db 'DELETE FROM oban_jobs'
```

Test it at `https://your-server.gamend.cloud`. The copy holds your live keys, so make no real purchases, and on S3 it uses your live bucket, so delete nothing. To sign in through a provider, add `https://your-server.gamend.cloud/auth/<provider>/callback` to that provider's callback addresses.

## Switch over

1. Stop the old server, so nothing is written after the last copy.
2. Export again, with the jobs this time, and import.
3. Attach your domain as in [Custom Domains](/docs/custom-domains). So that links and sign-in use it, turn off `your-server.gamend.cloud` on the **Domain** tab.
4. Move the DNS record. Until you do, starting the old server puts everything back.
5. Delete the exported files. They hold your secrets.

## For an operator

Files too large for a browser, or a server that must be trusted, go through the machine instead: copy them to `GAMEND_CLOUD_IMPORTS_DIR/<slug>/` and use **Import a server** on `/admin/cloud_servers`. It reads the same files and creates the server.
