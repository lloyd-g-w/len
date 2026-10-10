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
   curl http://127.0.0.1:8080/v1/health   # {"status":"ok","protocol":1,"blobs":true}
   ```

   Data is stored in the named volume `len-data` (mounted at `/data`): the
   database `len.db` and the blob directory `blobs/`.

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

## Configuration

| Variable         | Default        | Notes                                    |
|------------------|----------------|------------------------------------------|
| `LEN_SYNC_TOKEN` | (required)     | At least 16 characters; refuses to start otherwise. |
| `LEN_DB_PATH`    | `/data/len.db` | SQLite file (WAL mode).                  |
| `LEN_BLOB_DIR`   | `blobs/` next to `LEN_DB_PATH` (`/data/blobs`) | Blob files, `<first 2 hex>/<sha256>`; created at startup. |
| `LEN_BLOB_MAX_BYTES` | `209715200` (200 MiB) | Maximum size of one blob upload; positive integer. |
| `PORT`           | `8080`         |                                          |
| `HOST`           | `0.0.0.0`      |                                          |

**Backups:** back up both the database and the blob directory. Copy the
database with `sqlite3 len.db ".backup backup.db"` (safe while the server is
running) and copy `blobs/` (e.g. `rsync -a`; blobs are immutable and written
atomically, so this is safe while running too; `blobs/tmp/` holds in-flight
uploads and can be skipped). Alternatively stop the container and copy the
whole volume, including any `len.db-wal` file. Records reference blobs by
sha256, so a backup without the blob directory loses attachments.

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
(SQLite/LWW), `lib/src/api.dart` (routes, auth), `lib/src/blob_store.dart`
(content-addressed files), `lib/src/blob_api.dart` (blob routes).
