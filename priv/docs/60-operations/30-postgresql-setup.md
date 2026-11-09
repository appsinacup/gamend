---
icon: hero-circle-stack-solid
---

# PostgreSQL Setup

[Download PostgreSQL](https://www.postgresql.org)

## Database URL configuration

Set the GAMEND_DB_URL environment variable:

```bash
GAMEND_DB_URL="postgresql://username:password@host:port/database"
# Example:
GAMEND_DB_URL="postgresql://myuser:mypass@localhost:5432/gamend_prod"
```

At runtime the app switches its Repo configuration to PostgreSQL when GAMEND_DB_URL is set or when GAMEND_DB_POSTGRES_HOST and GAMEND_DB_POSTGRES_USER environment variables are configured. The adapter itself is a compile-time choice, though, so a production build must also be made for PostgreSQL: set `GAMEND_DB_ADAPTER=postgres` when compiling, which for Docker is the build arg:

```bash
docker build --build-arg GAMEND_DB_ADAPTER=postgres .
```

An image built without it is a SQLite image, whatever the runtime variables say.

## Individual environment variables (alternative)

You can also set individual database connection variables:

```bash
GAMEND_DB_POSTGRES_HOST="your-postgres-host"
GAMEND_DB_POSTGRES_PORT="5432"
GAMEND_DB_POSTGRES_USER="your-username"
GAMEND_DB_POSTGRES_PASSWORD="your-password"
GAMEND_DB_POSTGRES_DB="your-database-name"
```

## Deployment considerations

Popular PostgreSQL hosting options:

| Host | Notes |
|---|---|
| [Supabase](https://supabase.com) | Free tier available |
| [Neon](https://neon.tech) | Serverless PostgreSQL |
| [Fly.io Postgres](https://fly.io/docs/postgres/) | Managed PostgreSQL |
