FROM elixir:1.20-slim

# Install git and other build dependencies
RUN apt-get update && \
    # Install build tools + sqlite dev headers so Exqlite NIF builds in-image
    # libssl-dev is required by ex_dtls (WebRTC DTLS encryption)
    apt-get install -y git build-essential libsqlite3-dev sqlite3 pkg-config ca-certificates curl libssl-dev && \
    rm -rf /var/lib/apt/lists/*

# Install Rust toolchain (required by ex_sctp for WebRTC DataChannels)
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

# Install hex and rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Set working directory
WORKDIR /app

# Set environment to production
ENV MIX_ENV=prod

# Database adapter for compile-time selection (sqlite or postgres).
# Set to "postgres" when deploying with PostgreSQL.
ARG GAMEND_DB_ADAPTER=sqlite
ENV GAMEND_DB_ADAPTER=${GAMEND_DB_ADAPTER}

# Plugin build configuration
ARG GAMEND_CONTENT_PLUGINS_DIR=modules/plugins_examples
ENV GAMEND_CONTENT_PLUGINS_DIR=${GAMEND_CONTENT_PLUGINS_DIR}

COPY mix.exs mix.lock ./

# Umbrella apps: include their mix.exs files so deps can be resolved in a cached layer
COPY apps/game_server_web/mix.exs apps/game_server_web/mix.exs
COPY apps/game_server_core/mix.exs apps/game_server_core/mix.exs

# Install dependencies
RUN mix deps.get

# Compile-time config must be present before deps compile (mdex reads its
# syntax highlighter from config). Copied on its own so the layer only busts
# when config changes, not on every source commit.
COPY config config

# Compile external deps (hex + git, including the Rust NIFs) in a cached
# layer. Without this, `COPY . .` below invalidated `mix compile` on every
# commit and all ~140 deps rebuilt from scratch each CI run. Local path deps
# (apps/*) are skipped: their sources arrive with COPY and compile next.
RUN mix deps.compile --skip-local-deps

COPY . .

# Build any plugins that ship with the repository. Copy paste this to your own Dockerfile
RUN if [ -d "${GAMEND_CONTENT_PLUGINS_DIR}" ]; then \
        for plugin_path in ${GAMEND_CONTENT_PLUGINS_DIR}/*; do \
            if [ -d "${plugin_path}" ] && [ -f "${plugin_path}/mix.exs" ]; then \
                echo "Building plugin ${plugin_path}"; \
                (cd "${plugin_path}" && mix deps.get && mix compile && mix plugin.bundle --verbose); \
            fi; \
        done; \
    else \
        echo "Plugin sources dir ${GAMEND_CONTENT_PLUGINS_DIR} missing, skipping plugin builds"; \
    fi

# Compile the application FIRST (generates phoenix-colocated hooks)
RUN mix compile

# Build and digest static assets for production for the root host app.
RUN mix assets.deploy

# Version last, deliberately. It is `1.0.<commit_count>`, so it changes on
# every commit — and an ARG/ENV invalidates every layer below it, which would
# rebuild dependencies, NIFs and assets on every build for nothing.
#
# The cost of declaring it here is that the compiled OTP `vsn` keeps mix.exs's
# default. That is only a fallback: the reported version comes from the
# `content.app_version` setting, which this ENV supplies at runtime and which
# takes precedence (see GameServerWeb.ApiSpec.api_version/0).
ARG GAMEND_CONTENT_APP_VERSION=1.0.0
ENV GAMEND_CONTENT_APP_VERSION=${GAMEND_CONTENT_APP_VERSION}
RUN echo -n "${GAMEND_CONTENT_APP_VERSION}" > /app/VERSION

# Expose ports (HTTP + HTTPS)
EXPOSE 4000 443

# Default command - create DB (if needed), run migrations, and start server
CMD ["sh", "-c", "mix ecto.create --quiet -r GameServer.Repo 2>/dev/null; mix db.migrate && mix phx.server"]
