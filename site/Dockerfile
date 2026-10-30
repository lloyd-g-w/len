# syntax=docker/dockerfile:1

# The Len web app (a static PWA) served by nginx: ghcr.io/<owner>/len-site.
#
# The site is built outside the image (Flutter is not in it), then passed in
# as the `web` build context. From the repo root:
#   (cd app && tool/build_web.sh)
#   docker build -f site/Dockerfile --build-context web=app/build/web -t len-site site
#
# No RUN steps, so multi-arch builds need no emulation. The base image is
# pinned by version and digest (multi-arch index); to update, pick a new tag
# and look up its digest, e.g.
#   crane digest nginxinc/nginx-unprivileged:1.31.7-alpine3.24
FROM nginxinc/nginx-unprivileged:1.31.7-alpine3.24@sha256:b5047b9b76845eac124358373c6852377c52e4b05834a47647e955dd91cb8f1e

# Runs as uid 101 by default, or any uid (`user: "568:568"`): nginx only
# writes to /tmp, and the site and config are world-readable.
COPY default.conf /etc/nginx/conf.d/default.conf
COPY --from=web --chmod=a+rX . /usr/share/nginx/html

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
  CMD wget -q --spider http://127.0.0.1:8080/ || exit 1
