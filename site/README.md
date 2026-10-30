# Len web app image

`ghcr.io/lloyd-g-w/len-site`: the web build of Len (`app/tool/build_web.sh`,
an offline-capable PWA) served by unprivileged nginx on port 8080. It has
amd64 and arm64 images. Tags: `latest` and `sha-<short>` follow `main`
([site-image.yml](../.github/workflows/site-image.yml)); releases add `X.Y.Z`
and `X.Y` ([release.yml](../.github/workflows/release.yml)).

```yaml
services:
  len-site:
    image: ghcr.io/lloyd-g-w/len-site:latest
    container_name: len-site
    restart: unless-stopped
    user: "568:568"        # optional: any uid works (default 101)
    ports:
      - "8132:8080"
```

To update: `docker compose pull && docker compose up -d`. Open copies and
installed copies pick up the new version the next time they start.

- **HTTPS**: put it behind a reverse proxy with TLS. The service worker, and so
  offline use and installing the app, needs a secure context (or `localhost`).
- **Sync**: the sync server must allow the site's origin. `LEN_CORS_ORIGINS`
  defaults to `*`; if you restrict it, add the site's URL, e.g.
  `https://len.example.com`.
- **Data** stays in each browser (IndexedDB), so the container is stateless
  and needs no volume.
- **Caching** ([default.conf](default.conf)): the entry files and `sw.js` are
  `no-cache`, everything else is cached for an hour, and responses are gzipped.

To build it yourself, run this from the repo root:

```sh
(cd app && tool/build_web.sh)
docker build -f site/Dockerfile --build-context web=app/build/web -t len-site site
```
