# syntax=docker/dockerfile:1
# gamend-runtime: what an OTP release of Gamend, or of a host app built on it,
# needs at run time. The `release` stage of an app's Dockerfile:
#
#   FROM builder AS release-build
#   RUN mix release --overwrite
#
#   FROM ghcr.io/appsinacup/gamend-runtime:trixie AS release
#   COPY --from=release-build /app/_build/prod/rel/my_app ./
#   CMD ["gamend-release-start", "my_app"]
#
# gamend-builder is elixir:1.20-slim, Debian 13 (trixie), and a release carries
# ERTS and NIFs linked against that libc, so this tracks the same release.
# Published beside gamend-builder (.github/workflows/base-images.yml).
ARG DEBIAN_IMAGE=debian:trixie-slim
FROM ${DEBIAN_IMAGE}

# libstdc++6, libncurses6, openssl   ERTS and the crypto NIFs
# libsqlite3-0, libsrtp2-1           the SQLite adapter, WebRTC's SRTP
# libsctp1                           opened by ERTS's socket NIF, which warns at boot without it
# curl                               the image's healthcheck
# git, git-lfs                       hosts that clone repositories at run time
# podman-remote, as `podman`         Gamend.Containers, through the host's socket
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates curl libstdc++6 libncurses6 \
      openssl libsqlite3-0 libsrtp2-1 libsctp1 locales git git-lfs podman-remote && \
    ln -s /usr/bin/podman-remote /usr/local/bin/podman && \
    rm -rf /var/lib/apt/lists/*

ENV LANG=C.UTF-8 LANGUAGE=C:en LC_ALL=C.UTF-8
ENV GAMEND_HTTP_SERVER=true

COPY --chmod=0755 bin/ /usr/local/bin/

WORKDIR /app
EXPOSE 4000 443
