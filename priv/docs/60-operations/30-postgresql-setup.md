---
icon: hero-circle-stack
---

# PostgreSQL Setup

[Download PostgreSQL](https://www.postgresql.org)

## Database URL Configuration

Set the GAMEND_DB_URL environment variable:

```bash
GAMEND_DB_URL="postgresql://username:password@host:port/database"
# Example:
GAMEND_DB_URL="postgresql://myuser:mypass@localhost:5432/game_server_prod"
```

The app will automatically detect PostgreSQL when GAMEND_DB_URL is set or when GAMEND_DB_POSTGRES_HOST and GAMEND_DB_POSTGRES_USER environment variables are configured.

## Individual Environment Variables (Alternative)

You can also set individual database connection variables:

```bash
GAMEND_DB_POSTGRES_HOST="your-postgres-host"
GAMEND_DB_POSTGRES_PORT="5432"
GAMEND_DB_POSTGRES_USER="your-username"
GAMEND_DB_POSTGRES_PASSWORD="your-password"
GAMEND_DB_POSTGRES_DB="your-database-name"
```

## Deployment Considerations

Popular PostgreSQL hosting options:

| Host | Notes |
|---|---|
| [Supabase](https://supabase.com) | Free tier available |
| [Neon](https://neon.tech) | Serverless PostgreSQL |
| [Fly.io Postgres](https://fly.io/docs/postgres/) | Managed PostgreSQL |
