# syntax=docker/dockerfile:1
# gamend-builder: everything a Gamend server or a host app built on it needs
# to compile, so an app's Dockerfile holds only its own steps:
#
#   FROM ghcr.io/appsinacup/gamend-builder:elixir-1.20 AS builder
#   COPY mix.exs mix.lock ./
#   RUN mix deps.get
#   COPY config config
#   RUN mix deps.compile
#   COPY . .
#   RUN mix compile && mix assets.deploy && gamend-copy-static my_app
#   CMD ["gamend-start"]
#
# Published by core's CI (.github/workflows/base-images.yml) for linux/amd64
# and linux/arm64, on every push to main and weekly for Debian's security
# fixes. docker/README.md lists the images, their tags and the helper
# commands in bin/.
ARG ELIXIR_IMAGE=elixir:1.20-slim
FROM ${ELIXIR_IMAGE}

# What Gamend and its dependencies compile and serve with:
#   build-essential, pkg-config, libssl-dev   NIFs in C (argon2, bcrypt, crc, …)
#   libsqlite3-dev, sqlite3                   the SQLite adapter
#   libsrtp2-dev                              WebRTC's SRTP, when built from source
#   libsctp1                                  opened by ERTS's socket NIF, which warns at boot without it
#   git, git-lfs                              git dependencies, and repositories a host clones
#   optipng, pngquant, imagemagick            image optimisation at build time
#   brotli                                    the .br copies `phx.digest` does not make
#   podman-remote, as `podman`                Gamend.Containers, from inside a container,
#                                             through the host's socket (CONTAINER_HOST)
RUN apt-get update && \
    apt-get install -y git git-lfs build-essential pkg-config ca-certificates curl libssl-dev \
      libsqlite3-dev sqlite3 libsrtp2-dev libsctp1 optipng pngquant imagemagick brotli podman-remote && \
    ln -s /usr/bin/podman-remote /usr/local/bin/podman && \
    rm -rf /var/lib/apt/lists/*

# Rust: NIFs with no prebuilt binary for the platform compile from source
# (ex_sctp, through WebRTC, always; mdex_native when its download fails).
RUN curl https://sh.rustup.rs -sSf | sh -s -- -y --profile minimal
ENV PATH="/root/.cargo/bin:${PATH}"

RUN mix local.hex --force && \
    mix local.rebar --force

# gamend-build-plugins, gamend-copy-static, gamend-start: the steps every
# Gamend image repeated, written once (docker/README.md).
COPY --chmod=0755 bin/ /usr/local/bin/

WORKDIR /app
