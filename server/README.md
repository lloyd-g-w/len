# Len sync server

A tiny self-hosted sync server for Len. It is a generic last-write-wins
record store with a change feed, implementing
[`docs/SYNC_PROTOCOL.md`](../docs/SYNC_PROTOCOL.md) (protocol v1). Records live
in a single SQLite file; binary attachments (e.g. imported PDFs) are stored as
content-addressed files in a blob directory next to it.

## Self-hosting in 3 steps

1. **Create a token.** In this directory:

   ```sh
   cp .env.example .env
   sed -i "s/^LEN_SYNC_TOKEN=.*/LEN_SYNC_TOKEN=$(openssl rand -hex 32)/" .env
   ```

2. **Start the server.**

   ```sh
   docker compose up -d --build
   curl http://127.0.0.1:8080/v1/health   # {"status":"ok","protocol":1,…}
   ```

   Data is stored in the named volume `len-data` (mounted at `/data`): the
   database `len.db` and the blob directory `blobs/`.

   **Or use the prebuilt image** instead of building: every release publishes
   `ghcr.io/lloyd-g-w/len-sync` (tags `latest`, `X.Y`, `X.Y.Z`; amd64 and
   arm64, e.g. a Raspberry Pi). With Compose, point `image:` at it and drop
   `build:`:

   ```yaml
   services:
     len-sync:
       image: ghcr.io/lloyd-g-w/len-sync:latest   # or pin a version: :0.1
   ```

   then `docker compose pull && docker compose up -d`. Without Compose:

   ```sh
   docker run -d --name len-sync --restart unless-stopped --env-file .env \
     -p 127.0.0.1:8080:8080 -v len-data:/data \
     ghcr.io/lloyd-g-w/len-sync:latest
   ```

   (`.env` from step 1.) Update with `docker compose pull && docker compose
   up -d` (data lives in the volume and survives).

   **A host folder instead of a volume, as another user** (e.g. a NAS
   dataset owned by uid/gid 568): the server needs no root, so run it as the
   folder's owner and bind-mount the folder at `/data`:

   ```yaml
   services:
     len-sync:
       image: ghcr.io/lloyd-g-w/len-sync:latest
       user: "568:568"
       volumes:
         - /mnt/main/stacks/len-sync:/data
   ```

3. **Put it behind HTTPS.** The token travels in every request, so never
   expose the server over plain HTTP. Compose only binds to `127.0.0.1:8080`;
   use a reverse proxy such as [Caddy](https://caddyserver.com), which gets
   certificates automatically. Minimal `Caddyfile`:

   ```caddyfile
   sync.example.com {
       request_body {
           max_size 200MB
       }
       reverse_proxy 127.0.0.1:8080
   }
   ```

   Blob uploads (`PUT /v1/blobs/…`) can be up to `LEN_BLOB_MAX_BYTES`
   (200 MiB by default), so raise your proxy's request body limit to match:
   `request_body { max_size 200MB }` in Caddy as above, or
   `client_max_body_size 200m;` in nginx (whose default is only 1 MB).

   Then in the Len app, enter `https://sync.example.com` and the token from
   `.env`.

   **Live sync through the proxy.** Devices keep a WebSocket open (`GET /v1/live`) over
   which edits reach the other devices within a fraction of a second. A proxy must pass the
   WebSocket upgrade on and keep the connection open:

   - **Caddy**: nothing to do (`reverse_proxy` passes WebSockets on).
   - **nginx**: pass the upgrade headers and keep the read timeout above the 20 s heartbeat
     (the default 60 s is fine):

     ```nginx
     location / {
         proxy_pass http://127.0.0.1:8080;
         proxy_http_version 1.1;
         proxy_set_header Upgrade $http_upgrade;
         proxy_set_header Connection $connection_upgrade;
         proxy_set_header Host $host;
         proxy_read_timeout 120s;
         client_max_body_size 200m;
     }
     ```

     with, in the `http` block,
     `map $http_upgrade $connection_upgrade { default upgrade; '' close; }`.
   - **Apache** (`mod_proxy_wstunnel`): `RewriteEngine on`,
     `RewriteCond %{HTTP:Upgrade} websocket [NC]`,
     `RewriteRule ^/v1/live$ ws://127.0.0.1:8080/v1/live [P,L]` before the `ProxyPass`.
   - **Cloudflare** and similar CDNs pass WebSockets on (enable *WebSockets* in the dashboard
     where it is a setting); their idle timeout (100 s) is well above the heartbeat.

   Where WebSockets don't get through, devices fall back to a Server-Sent Events stream
   (`GET /v1/events`), which tells them within seconds that something changed. A proxy must
   pass it on unbuffered and keep it open:

   - **Caddy**: nothing to do (it flushes `text/event-stream` responses at once).
   - **nginx**: the server sends `X-Accel-Buffering: no`, which turns response buffering off
     for the stream; `proxy_buffering off;` in its `location` does the same if your setup
     ignores that header. Don't `gzip` `text/event-stream`.
   - **Apache** (`mod_proxy`): `ProxyPass / http://127.0.0.1:8080/ flushpackets=on`, and no
     `mod_deflate` for `text/event-stream`.

   A proxy that passes neither costs nothing but speed: devices still sync every couple of
   minutes and a few seconds after they write, leave or return to the app.

   Browsers (the Len web app) open the WebSocket with a one-time ticket in the URL
   (`/v1/live?ticket=…`, valid for 30 s and one connection), as they cannot send the token in
   a header there; the token itself never appears in a URL or a proxy's access log.

## Behind authentik with Traefik (sign in with the browser)

With a sign-in proxy in front (here [authentik](https://goauthentik.io)'s forward auth through
Traefik), devices get the token by signing in in the browser: Settings → Sync → enter the
server's address → **Sign in with browser…**. The page asks "Allow Len to sync?" as the
authentik user; on *Allow* the app gets the token (desktops: a redirect to a listener of the
app on `127.0.0.1`; Android: a `len://signin` link; the web app: a code to paste). Details:
[`docs/SYNC_PROTOCOL.md`](../docs/SYNC_PROTOCOL.md#browser-sign-in).

What the proxy guards and what it lets through:

| Path | Through authentik? | Why |
|---|---|---|
| `/signin` (and everything else outside `/v1/`) | **yes** | The sign-in page: authentik signs the user in and passes `X-authentik-username`. |
| `/v1/…` (API, `/v1/live` WebSocket, `/v1/events`, `/v1/signin/token`) | **no** | The server checks its own token there (or a one-time sign-in code); apps can't do authentik's login on every request. |
| `/outpost.goauthentik.io/…` | to authentik | authentik's own callback (single-application mode). |

1. **authentik**: *Applications → Providers → Create → Proxy Provider*, mode *Forward auth
   (single application)*, external host `https://sync.example.com`. Create an *Application*
   for it (bind the users or groups who may sync to it), and add it to the *authentik Embedded
   Outpost* (or your own proxy outpost). Instead of the separate Traefik router below, you can
   also exempt the API in the provider (*Advanced protocol settings → Unauthenticated Paths*):
   `^/v1/` (in *Forward auth (domain level)* mode the full URL:
   `^https://sync\.example\.com/v1/`).
2. **len-sync**: set `LEN_SIGNIN_USER_HEADER=X-authentik-username`, don't publish its port (only
   Traefik must reach it), and give it two routers: the default one through authentik, and one
   for `/v1/` without it, at a higher priority:

   ```yaml
   services:
     len-sync:
       image: ghcr.io/lloyd-g-w/len-sync:latest
       restart: unless-stopped
       environment:
         LEN_SYNC_TOKEN: ${LEN_SYNC_TOKEN:?set LEN_SYNC_TOKEN in .env}
         LEN_SIGNIN_USER_HEADER: X-authentik-username
       volumes:
         - len-data:/data
       networks: [traefik]
       # no "ports:": reachable only through Traefik
       labels:
         traefik.enable: "true"
         traefik.http.services.len-sync.loadbalancer.server.port: "8080"
         # The sign-in page and anything else: through authentik.
         traefik.http.routers.len-sync.rule: Host(`sync.example.com`)
         traefik.http.routers.len-sync.entrypoints: websecure
         traefik.http.routers.len-sync.tls.certresolver: letsencrypt
         traefik.http.routers.len-sync.middlewares: authentik@docker
         traefik.http.routers.len-sync.priority: "10"
         # The API (bearer token, WebSockets, SSE, sign-in codes): straight through.
         traefik.http.routers.len-sync-api.rule: Host(`sync.example.com`) && PathPrefix(`/v1/`)
         traefik.http.routers.len-sync-api.entrypoints: websecure
         traefik.http.routers.len-sync-api.tls.certresolver: letsencrypt
         traefik.http.routers.len-sync-api.service: len-sync
         traefik.http.routers.len-sync-api.priority: "20"
         # authentik's callback on this host (single-application mode).
         traefik.http.routers.len-sync-auth.rule: Host(`sync.example.com`) && PathPrefix(`/outpost.goauthentik.io/`)
         traefik.http.routers.len-sync-auth.entrypoints: websecure
         traefik.http.routers.len-sync-auth.tls.certresolver: letsencrypt
         traefik.http.routers.len-sync-auth.service: authentik
         traefik.http.routers.len-sync-auth.priority: "15"

   networks:
     traefik:
       external: true
   volumes:
     len-data:
   ```

   The `authentik@docker` middleware and `authentik` service are the usual ones from
   [authentik's Traefik docs](https://docs.goauthentik.io/add-secure-apps/providers/proxy/server_traefik/),
   as labels on the authentik server (embedded outpost) container:

   ```yaml
   traefik.http.services.authentik.loadbalancer.server.port: "9000"
   traefik.http.middlewares.authentik.forwardauth.address: http://authentik-server:9000/outpost.goauthentik.io/auth/traefik
   traefik.http.middlewares.authentik.forwardauth.trustForwardHeader: "true"
   traefik.http.middlewares.authentik.forwardauth.authResponseHeaders: X-authentik-username,X-authentik-groups,X-authentik-entitlements,X-authentik-email,X-authentik-name,X-authentik-uid,X-authentik-jwt,X-authentik-meta-jwks,X-authentik-meta-outpost,X-authentik-meta-provider,X-authentik-meta-app,X-authentik-meta-version
   ```

   (Body size: Traefik sets no request body limit by default, so blob uploads pass.
   WebSockets on `/v1/live` pass as they are.)
3. In Len: Settings → Sync → `https://sync.example.com` → **Sign in with browser…**. Typing the
   token (or a setup link) keeps working.

**Why the header can be trusted:** Traefik's forward auth replaces every header listed in
`authResponseHeaders` with authentik's answer, dropping one a client sent itself, so a request
reaching `/signin` through the guarded router carries the name authentik signed in. That only
holds if nothing reaches the server around the proxy (no published port, no other router to
`/signin`) and `X-authentik-username` is in `authResponseHeaders`; whoever can send the header
to the server directly can get the token. Keep Traefik's default path sanitising
(`entryPoints.<name>.http.sanitizePath`, on by default) so `/v1/../signin` can't take the
unguarded router. Without `LEN_SIGNIN_USER_HEADER` the sign-in is off and `/signin` is `404`.

What the app gets is the server's one `LEN_SYNC_TOKEN` (as with a setup link): taking a user
out of authentik doesn't stop a device that already signed in; change `LEN_SYNC_TOKEN` for that.
If the whole site is guarded (no `/v1/` exemption), the app says that a sign-in page answers
instead of the server.

## Configuration

| Variable         | Default        | Notes                                    |
|------------------|----------------|------------------------------------------|
| `LEN_SYNC_TOKEN` | (required)     | At least 16 characters; refuses to start otherwise. |
| `LEN_DB_PATH`    | `/data/len.db` | SQLite file (WAL mode).                  |
| `LEN_BLOB_DIR`   | `blobs/` next to `LEN_DB_PATH` (`/data/blobs`) | Blob files, `<first 2 hex>/<sha256>`; created at startup. |
| `LEN_BLOB_MAX_BYTES` | `209715200` (200 MiB) | Maximum size of one blob upload; positive integer. |
| `LEN_BLOB_IDLE_TIMEOUT` | `60` | Seconds a blob upload may send no data before it is abandoned (stalled clients); positive integer. |
| `LEN_CORS_ORIGINS` | `*`          | Browser origins allowed to call the API (CORS), see below. |
| `LEN_SIGNIN_USER_HEADER` | (off)  | Header a sign-in proxy passes the user's name in (e.g. `X-authentik-username`): turns on [browser sign-in](#behind-authentik-with-traefik-sign-in-with-the-browser). Only behind such a proxy. |
| `PORT`           | `8080`         |                                          |
| `HOST`           | `0.0.0.0`      |                                          |

**CORS** (for the Len web app, which runs in a browser): `LEN_CORS_ORIGINS`
is either `*` (the default, also used when the variable is unset or empty),
`none`, or a comma-separated list of origins such as
`https://len.example.com,http://localhost:5173` (scheme, host and optional
port; no path or trailing slash; an invalid entry stops the server from
starting).

- `*`: every response, including errors such as 401, carries
  `Access-Control-Allow-Origin: *`. This is safe because auth is a bearer
  token, not cookies; `Access-Control-Allow-Credentials` is never sent.
- A list: the request's `Origin` is echoed back if it is listed
  (case-insensitively), otherwise no CORS headers are sent, so browsers
  block the response. Every response carries `Vary: Origin`.
- `none`: no CORS headers at all and `OPTIONS` is not handled specially, for
  servers only used by the native apps.

Preflight `OPTIONS` requests are answered by the server itself without a
token: `204` with `Access-Control-Allow-Methods: GET, HEAD, POST, PUT,
OPTIONS`, `Access-Control-Allow-Headers: Authorization, Content-Type` and
`Access-Control-Max-Age: 86400`, or `403` without CORS headers if the origin
is not in the list. Other responses also expose `Content-Length` and
`Content-Type` (`Access-Control-Expose-Headers`). If your reverse proxy adds
its own CORS headers, disable one of the two.

**Backups:** back up both the database and the blob directory. Copy the
database with `sqlite3 len.db ".backup backup.db"` (safe while the server is
running) and copy `blobs/` (e.g. `rsync -a`; blobs are immutable and written
atomically, so this is safe while running too; `blobs/tmp/` holds in-flight
uploads and can be skipped; files there older than a day are leftovers of
interrupted uploads and are removed at startup). Alternatively stop the container and copy the
whole volume, including any `len.db-wal` file. Records reference blobs by
sha256, so a backup without the blob directory loses attachments.

**Restoring a backup:** stop the server, put the backed-up `len.db` (and
`blobs/`) in place, run `server new-id` (`docker compose run --rm len-sync
new-id`, or `dart run bin/server.dart new-id`), then start the server. The
new id makes every device upload its complete copy again, so changes made
after the backup was taken come back from the devices that have them. (The
server also notices by itself when a device has seen changes it no longer
has, but only if that device syncs before others have written as much.)
The same happens automatically when the address leads to a new, empty
server: devices recognise it by its id and upload everything.

**Live connections** (`/v1/live`): at most 1000 at a time (`503` beyond),
messages up to 4 MiB, rooms (one per open notebook) up to 8 per connection,
relayed messages (live ink, pointers) up to 16 KiB and 40 a second per connection.
Nothing sent in rooms is stored. A device that does not read (a stalled
network) gets at most 1 MiB queued, then one "resync" that makes it pull.

**Durability:** the database runs in WAL mode with `synchronous = FULL`, so a
push the server has answered survives a crash or power loss.

**Stopping:** on SIGTERM or SIGINT (`docker stop`) the server stops accepting
connections, ends the open event streams and closes the live connections
(WebSocket close `1001`; devices reconnect once it is back),
lets requests in flight finish for up to 8 s (within Docker's default 10 s
stop timeout), then closes the database.

## Blob garbage collection

Blobs that no record references anymore (deleted PDFs, images, recordings)
are not deleted automatically. Run the collector by hand or from cron:

```sh
docker compose exec len-sync /opt/len-sync/bin/server gc --dry-run   # report only
docker compose exec len-sync /opt/len-sync/bin/server gc             # mark / delete
# without Docker: LEN_DB_PATH=/path/len.db dart run bin/gc.dart [--dry-run]
```

A run marks blobs it finds unreferenced and deletes those that have been
unreferenced for the grace period (default 30 days, `--grace-days <n>`), so
nothing is deleted on the first run: schedule it daily, e.g. a crontab entry
`17 4 * * * docker compose -f /srv/len/docker-compose.yml exec -T len-sync
/opt/len-sync/bin/server gc`. It is safe while the server is running.

The server does not understand record contents, so it finds references by
scanning the JSON data of every live record for 64-character lowercase hex
strings that match a stored blob. This needs no help from the clients and
keeps blobs whenever in doubt; the trade-off is that a reference written in
some other form would not be seen (the app always writes plain sha256
strings). Deleted records (tombstones) do not count; notebooks in the app's
trash are still live and keep their attachments. After a run that deleted
blobs, clients re-check that the server still has every blob they
reference, and re-upload any that are missing. Details:
[`docs/SYNC_PROTOCOL.md`](../docs/SYNC_PROTOCOL.md#blob-garbage-collection).

## Development

Needs Dart ≥ 3.8 (on NixOS: `nix shell nixpkgs#dart`).

```sh
dart pub get
dart analyze
dart test
LEN_SYNC_TOKEN=$(openssl rand -hex 32) LEN_DB_PATH=/tmp/len.db dart run bin/server.dart
```

`package:sqlite3` bundles its own SQLite via a build hook (downloaded from the
package's GitHub releases on first build), so no system SQLite is needed. For
the same reason `dart compile exe` is not supported; build a standalone
bundle with `dart build cli` (`build/cli/<platform>/bundle/`, executable plus
`lib/libsqlite3.so`).

Layout: `bin/server.dart` (wiring), `lib/src/config.dart` (env config),
`lib/src/record.dart` (model, validation), `lib/src/record_store.dart`
(SQLite/LWW), `lib/src/api.dart` (routes, auth), `lib/src/cors.dart`
(CORS middleware), `lib/src/blob_store.dart` (content-addressed files),
`lib/src/blob_api.dart` (blob routes), `lib/src/change_events.dart`
(`/v1/events`), `lib/src/live_api.dart` (`/v1/live`: tickets, the WebSocket
upgrade), `lib/src/live_hub.dart` (live connections, fan-out, rooms),
`lib/src/live_connection.dart` (one connection: messages, bounded outbox,
limits), `lib/src/live_tickets.dart`, `lib/src/browser_signin.dart` (`/signin`, sign-in codes),
`lib/src/push_request.dart` (a push's
validation, shared by HTTP and live pushes), `lib/src/blob_gc.dart` (blob garbage
collection), `lib/src/gc_command.dart` with `bin/gc.dart` (its admin
command) and `lib/src/new_id_command.dart` (`server new-id`).
