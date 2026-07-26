---
icon: hero-arrows-pointing-out
---

# Scaling

## 1 instance vs multiple instances

**Single instance** is the simplest and the default. When you scale out to multiple instances, you typically need:

- A shared database (PostgreSQL recommended)
- A shared cache (Redis recommended since L2 doesn't require Erlang distribution)

## Docker Compose (local / self-host)

Docker Compose is a simple way to run the app with PostgreSQL and Redis.

```bash
docker compose up

GAMEND_CACHE_MODE=multi
GAMEND_CACHE_L2=redis
GAMEND_CACHE_REDIS_URL="redis://redis:6379/0"
```

If you want to use `GAMEND_CACHE_L2=partitioned` under Compose, you also need to configure Erlang distribution + node discovery for your app containers.

## Rate Limiting

HTTP rate limiting is enforced per client IP using the Hammer library (ETS backend). It protects against brute-force attacks and API abuse.

Configuration is via environment variables. The server reads the real client IP from CF-Connecting-IP (Cloudflare), Fly-Client-IP, or X-Forwarded-For headers.

```bash
GAMEND_RATELIMIT_GENERAL_LIMIT=240
GAMEND_RATELIMIT_GENERAL_WINDOW=60000
GAMEND_RATELIMIT_AUTH_LIMIT=10
GAMEND_RATELIMIT_AUTH_WINDOW=60000
GAMEND_RATELIMIT_WS_LIMIT=60
GAMEND_RATELIMIT_WS_WINDOW=10000
GAMEND_RATELIMIT_DC_LIMIT=300
GAMEND_RATELIMIT_DC_WINDOW=10000

GAMEND_RATELIMIT_BACKEND=redis
GAMEND_RATELIMIT_REDIS_URL=redis://localhost:6379
```

When a client exceeds the limit, the server returns HTTP 429 Too Many Requests with a Retry-After header. With the default ETS backend each node counts separately; set GAMEND_RATELIMIT_BACKEND=redis so limits hold across all instances.

### WebSocket & WebRTC rate limiting

WebSocket channel messages are rate-limited per user (60 messages per 10 seconds by default). When exceeded, the channel is closed with a "rate_limited" error. WebRTC DataChannel messages have a separate, higher limit (300 messages per 10 seconds). Exceeding it disconnects the WebRTC peer connection. Unrecognized WebSocket events also close the channel immediately to prevent abuse.
