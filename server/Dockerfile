# syntax=docker/dockerfile:1

# Base images are pinned by version and digest (multi-arch index), so builds
# are reproducible and a re-pushed tag cannot change them. To update, pick
# new tags and look up their digests, e.g.
#   docker buildx imagetools inspect dart:3.13.5-sdk
#   docker buildx imagetools inspect debian:bookworm-20261005-slim

# ---- Build stage -----------------------------------------------------------
FROM dart:3.13.5-sdk@sha256:8604cbd137b6d67c24f49b916f2aa9b67d71b539576e0178bf161d831c9e344f AS build
WORKDIR /app

# Resolve dependencies first for better layer caching.
COPY pubspec.yaml pubspec.lock ./
RUN dart pub get --enforce-lockfile

COPY . .
# `dart compile exe` does not support packages with build hooks (sqlite3 3.x
# uses one to bundle SQLite), so build an AOT CLI bundle instead:
#   /out/bundle/bin/server  + /out/bundle/lib/libsqlite3.so
# The sqlite3 build hook downloads a checksum-verified prebuilt SQLite from
# the package's GitHub releases, so this step needs network access.
RUN dart build cli --target bin/server.dart -o /out

# ---- Runtime stage ---------------------------------------------------------
FROM debian:bookworm-20261005-slim@sha256:7c7b2c966bc9ee8cedfeef67e0e279108992c77681fa595db4a9d65c06ccc587
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --uid 10001 --home-dir /nonexistent --shell /usr/sbin/nologin len \
 && mkdir -p /data && chown len:len /data

# The executable finds lib/libsqlite3.so relative to itself, so keep the
# bundle layout intact.
COPY --from=build /out/bundle /opt/len-sync

USER len
ENV LEN_DB_PATH=/data/len.db \
    PORT=8080 \
    HOST=0.0.0.0
VOLUME ["/data"]
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
  CMD curl -fsS "http://127.0.0.1:${PORT}/v1/health" || exit 1
ENTRYPOINT ["/opt/len-sync/bin/server"]
