# Len Sync Protocol — v1

The server is a **generic last-write-wins record store with a change feed**. It knows nothing about
notebooks or strokes; it just stores opaque JSON records grouped by `collection`. This keeps the
server tiny and lets the app evolve its data model without server changes.

## Transport & auth

- HTTP + JSON (UTF-8). All endpoints except `/v1/health` require
  `Authorization: Bearer <token>`, where `<token>` equals the server's `LEN_SYNC_TOKEN`.
- Token comparison must be constant-time.

## Record

```json
{
  "collection": "strokes",          // [a-z_]{1,32}
  "id": "0b5c…",                    // 1..64 chars, unique within collection
  "updatedAt": 1760000000000,       // int, ms since epoch (client clock)
  "deviceId": "a1b2…",              // 1..64 chars; tie-breaker for equal updatedAt
  "deleted": false,                 // tombstone flag
  "data": { … } | null              // opaque JSON object; null when deleted
}
```

The server stores `data` opaquely (it accepts `null` for live records); the app treats a live
record without a `data` object as malformed.

Records returned by the server additionally contain `"seq": <int>` — a strictly increasing,
server-assigned change number.

### Conflict rule (LWW)

An incoming record replaces the stored one iff there is no stored record with the same
`(collection, id)`, or `(incoming.updatedAt, incoming.deviceId) > (stored.updatedAt, stored.deviceId)`
compared lexicographically (int compare, then string compare). Otherwise it is ignored.
Whenever a record is stored/replaced it gets a new `seq` (max seq + 1).

## Endpoints

### `GET /v1/health`
No auth.
`200 {"status":"ok","protocol":1,"blobs":true,"maxBlobBytes":209715200,"blobsCollectedAt":0}`

`blobs: true` means the server implements the [blob endpoints](#blobs). Clients must treat a
missing `blobs` field as `false` (older servers) and then neither upload nor download blobs.

`maxBlobBytes` (added later; absent on older servers) is the largest blob the server accepts
(`LEN_BLOB_MAX_BYTES`), so clients can skip blobs that are too large without sending them.
`blobsCollectedAt` (added later; absent → 0) is when (ms since epoch) the server last deleted
blobs by [garbage collection](#blob-garbage-collection), 0 if never. Clients must tolerate unknown
fields here.

### `POST /v1/push`
Body: `{"records": [Record, …]}` — at most 1000 records, body at most 32 MiB.

Applied atomically in one transaction. Response `200`:
```json
{"applied": 12, "ignored": 3, "serverSeq": 4711}
```
`serverSeq` is the current max seq after the push.

### `GET /v1/pull?since=<int>&limit=<int>`
`since` defaults to 0, `limit` defaults to 500, larger values are clamped to 1000. Returns records
with `seq > since` ordered by `seq` ascending. A page may hold fewer than `limit` records: the
server stops adding records once their payloads exceed ~8 MiB (always returning at least one), so
responses stay bounded when records are large.
```json
{"records": [Record+seq, …], "nextSince": 4711, "hasMore": false}
```
`nextSince` is the seq of the last returned record (or `since` if none). Clients repeat while
`hasMore` is true; a page with `hasMore: true` always advances `nextSince`.

### Errors
`401` missing/bad token, `400` malformed request (body `{"error": "…"}`), `413` too large,
`404` unknown route.

## Blobs

Binary payloads (PDFs used as page backgrounds, images, audio recordings) are stored as **content-addressed blobs**,
separately from records. A blob is identified by the SHA-256 of its bytes, written as 64
lowercase hex characters (`<sha256>`); any other identifier is rejected with `400`. Blobs are
immutable. All blob endpoints require the bearer token (`401` otherwise).

### `PUT /v1/blobs/<sha256>`
Body: the raw blob bytes (any content type), at most `LEN_BLOB_MAX_BYTES` (default 200 MiB =
209715200 bytes). The 32 MiB push limit does not apply.

- `200 {"sha256": "<sha256>", "size": <bytes>}` — the blob is stored. Returned both for a new
  blob and when it already existed (**idempotent**; an existing blob is not rewritten and the
  body may not be read).
- `400 {"error": "hash mismatch"}` — the SHA-256 of the body differs from `<sha256>`; nothing is
  stored.
- `400 {"error": "…"}` — `<sha256>` is not 64 lowercase hex characters.
- `413 {"error": "…"}` — `Content-Length` exceeds the limit (rejected before reading), or the
  streamed body exceeds it; nothing is stored. Retrying the same blob is pointless until the
  limit changes (a reverse proxy in front of the server may also answer `413` with its own,
  smaller limit).
- A **stalled** upload — no body data for `LEN_BLOB_IDLE_TIMEOUT` seconds (default 60) — is
  abandoned: nothing is stored, the temporary file is removed and the connection is closed (the
  server may answer `408 {"error": "upload stalled"}` first). Clients retry later.

The server hashes while streaming to a temporary file and atomically renames it into place, so a
blob is only ever visible complete and verified, and concurrent uploads of the same blob are safe. Temporary files
of interrupted uploads are removed at startup once they are older than a day (younger ones may
belong to another server process sharing the blob directory).

### `GET /v1/blobs/<sha256>`
`200` with the raw bytes, `Content-Type: application/octet-stream` and `Content-Length`.
`404 {"error": "not found"}` if the blob is not stored; `400` for an invalid identifier.

### `HEAD /v1/blobs/<sha256>`
Like `GET` without a body: `200` with `Content-Type` and `Content-Length` (the blob size) if
stored, `404` (empty body) if not.

### Client algorithm for blobs

- Records reference blobs by `<sha256>` inside their `data` (e.g. a page `background.blob`).
- **Upload before push.** Each sync cycle starts with `GET /v1/health`. Before pushing, the client
  uploads every locally stored blob that a live local row references and that it has not yet
  uploaded to the current server: `HEAD` to skip blobs the server already has, otherwise `PUT`. It
  remembers successfully uploaded blobs (and forgets those marks when the server's
  `blobsCollectedAt` changes, see [garbage collection](#blob-garbage-collection)). Blobs no live
  row references are not uploaded.
- **Too large.** A blob larger than the advertised `maxBlobBytes`, or answered with `413`, is
  marked "too large" for this server and skipped from then on, without blocking anything else:
  records referencing it are pushed normally, and other devices show their usual placeholder for a
  missing blob. The mark records the advertised limit at that time; it is dropped when the server
  advertises a larger limit that fits the blob, when the user retries (Settings → Sync), or when
  the server changes. The app reports such blobs ("1 file too large to sync").
- **Other failures.** If `/v1/health` or a `HEAD` cannot reach the server, or the token is
  rejected, the cycle aborts (nothing else would get through). Any other failure of one blob (an
  error status, or a connection breaking during a long upload) does not stop the other blobs; the
  blob stays pending and is retried on the next sync, and the cycle is reported as failed after
  pushing and pulling everything else. Records referencing a blob that is still pending are held
  back (stay dirty), so a record does not reach the server before its blob — but only for three
  consecutive failed attempts, after which they are pushed anyway, so one blob that can never be
  uploaded cannot keep its records from syncing.
- A server without blob support (no `"blobs": true` in `/v1/health`) answers `404` to blob
  requests, which surfaces as a failed upload once a device references a stored blob. When the
  server URL changes, the "uploaded" and "too large" marks are reset along with `lastPulledSeq`.
- **Lazy download.** Pulled records may reference blobs the client does not have; the client
  downloads them with `GET` only when they are needed (e.g. when a page is displayed) and verifies
  the SHA-256 before storing them. A missing blob (`404`) is treated as temporarily unavailable.
- **No deletion over the wire.** There is no endpoint to delete a blob; unreferenced blobs are
  removed by garbage collection on each side, see below.

### Blob garbage collection

**Server.** The server does not understand record payloads, so it finds references by scanning the
stored JSON `data` of every **live** record (tombstones do not count; a trashed notebook is still a
live record, so its pages keep their PDFs) for runs of lowercase hex characters and checking every
64-character window against the stored blobs. No protocol addition is needed and new kinds of
references in future app versions are covered automatically, provided they are written as plain
lowercase `<sha256>` strings (the convention for all blob references). The scan errs on the side
of keeping: any string that happens to equal a stored blob's id keeps it. Collection is an admin
command (`dart run bin/gc.dart`, or `server gc` in the Docker image), never automatic:

1. A run marks every stored blob no live record references with the time it was first found
   unreferenced, and clears the mark of blobs that are referenced again.
2. A blob is deleted only once it has been marked for at least the grace period (default 30 days),
   is still unreferenced in a second scan right before deletion, and its file was not stored or
   re-uploaded (an idempotent `PUT` refreshes it) within the grace period either.
3. When a run deletes anything, `blobsCollectedAt` in `/v1/health` is set to the time of the run.

The grace period protects devices that were offline with records still referencing a blob. As a
second safety net, a client whose last seen `blobsCollectedAt` differs from the server's forgets
its "uploaded" marks, so the next upload phase re-checks (`HEAD`) the blobs its live records
reference and uploads any the server lost.

**Client** (local, never visible to the server): a locally stored blob is deleted from the device
once no live local row references it (page backgrounds, image elements and recordings; pages,
elements and recordings of trashed notebooks are live rows, so they count) for 7 days. The app
checks this at startup at most once a day. A blob collected locally is fetched again lazily if a
record referencing it arrives later.

## Client algorithm

1. **Push**: read locally dirty rows in pages ordered by id (keyset pagination, so rows that stay
   dirty cannot stall the loop) and send them in requests of at most 1000 records and ~4 MiB of
   JSON. A single record too large for the server's body limit is skipped (it stays dirty). After
   success, clear the dirty flag of each row whose `updatedAt` has not changed since it was read.
2. **Pull**: from the stored `lastPulledSeq`, page through `/v1/pull`, applying each record locally
   with the same LWW rule, then persist `nextSince` in the same local transaction. Malformed
   records and unknown collections are skipped (never retried), so they cannot block sync.

Records echoed back from the client's own push are harmless (LWW makes them no-ops).

**Local versions.** `updatedAt` comes from the client's wall clock, but a local write always stamps
`max(now, previous updatedAt + 1)`. An edit therefore always beats the version it replaces, even if
that version came from a device whose clock runs ahead, and two writes to a row never share a
version (which the "unchanged since read" check of step 1 relies on).

**Switching servers.** When the server URL changes, the app resets `lastPulledSeq` to 0 and marks
every row (tombstones included) dirty, so the new server receives a complete copy.

## App collections (informational)

| collection  | data                                                                                   |
|-------------|----------------------------------------------------------------------------------------|
| `folders`   | `{name, parentId: string|null, color, createdAt}`                                       |
| `notebooks` | `{title, kind: "paged"|"canvas", paper, coverColor, createdAt, coverStyle?, editedAt?, folderId?, favorite?, trashedAt?, paperColor?}` |
| `pages`     | `{notebookId, sortKey, width, height, paper, paperColor?, bookmarked?, background?}`     |
| `strokes`   | `{surfaceId, tool, color, width, points (base64 little-endian Float32 x,y,pressure triples), createdAt, style?}` — `tool` ∈ `pen` (legacy), `ballpoint`, `fountain`, `brush`, `pencil`, `marker`, `highlighter` (current clients create only `ballpoint` and `highlighter`; the rest are kept for older strokes); unknown tools render as `pen`. Optional `style` = `{o: opacity, th: thinning, sl: streamline, ts?: taperStart, te?: taperEnd}` (missing → per-tool defaults; unknown keys ignored). |
| `elements`  | `{surfaceId, type, x, y, w, h, rotation, z, createdAt, data}` — a non-ink object on a surface. `x, y, w, h` is the unrotated box in world units, `rotation` is clockwise radians about its centre, `z` the stacking order among elements (missing → `createdAt`). `type` = `text` (`data` = `{text, size, color, bold, italic, align: "left"|"center"|"right"}`) or `image` (`data` = `{blob, width, height, crop?}`, see below). Elements with `z < 0` are drawn beneath the ink, the others above it. Unknown types are stored and synced unchanged but not rendered; unknown `data` keys survive local edits. |
| `recordings` | `{notebookId, blob, durationMs, startedAt, title, mime, segments}` — an audio recording of a notebook. `blob` is the `<sha256>` of the audio ([blob](#blobs); current clients write `audio/mp4` AAC, or `audio/webm` Opus in browsers without AAC, as given by `mime`; missing → `audio/mp4`). `startedAt` is the wall time (epoch ms) recording began, `durationMs` the audio length; `segments` = `[[startedAt, durationMs], …]` are the stretches captured between pauses, mapping audio time to wall time so ink (`strokes.createdAt`) can be replayed with it (missing/empty → one segment `[startedAt, durationMs]`; malformed entries are dropped). Deleting a notebook tombstones its recordings. |

**Not synced: the search index.** Full-text search (`search_docs`, `search_fts`, and the PDF text
cache `pdf_text`) is derived on each device from the collections above and the PDF blobs, and is
updated when records are applied by sync like any local write. Nothing about it travels over the
wire, so search needs no protocol change.

Fields marked `?` were added after v1 and may be missing in records from older clients; readers
keep the local row's value for a missing field (so an old client renaming a notebook does not move,
unstar or restore it), and for a row not seen before fall back to defaults (`coverStyle` "plain",
`editedAt` = `updatedAt`, no folder, not favourite, not trashed). Unknown `coverStyle` values read as
"plain".

**Library semantics.**
- `folders.parentId` is null for top-level folders. A folder whose parent is missing/deleted is shown
  at the top level; so is every folder in a parent cycle (possible after concurrent moves on two
  devices). Deleting a folder tombstones its whole subtree and moves the notebooks inside to the trash.
- `notebooks.folderId` pointing at a missing folder means "library root".
- `notebooks.trashedAt` (ms) puts a notebook in the trash; it stays a live record so it can be
  restored. "Delete forever" tombstones the notebook, its pages, strokes, elements and recordings.
- `paperColor` (canvas background; same values as on pages): missing → the local value, or
  `white` for a notebook new to this device; unknown → `white`.
- `editedAt` is the last content/title edit (used for "last edited" sorting); organisation changes
  (favourite, move, trash) only bump `updatedAt`.

**Image elements.** `data.blob` is the `<sha256>` of the encoded image ([blob](#blobs); PNG, JPEG or
WebP as written by current clients — readers decode whatever the platform supports and show a
placeholder otherwise, or while the blob is not on the device yet). `width` / `height` are the
image's natural size in pixels (0 = unknown). The optional `crop` = `{x, y, w, h}` is the visible part
in *normalised* image coordinates (0..1, independent of the decoded resolution); missing means the
whole image. The element's box (`x, y, w, h`, `rotation`) is where the cropped part is shown, so
aspect ratio and crop never need to agree with the box: the image is stretched to fill it. Clients
store images at most 4096 px on their long edge. New images get a negative `z` (beneath the ink);
"bring to front" gives an element a `z` above every other one (and so above the ink), "send to back"
one below every other.

**Paper and pages.** `paper` (on notebooks and pages) is one of `blank`, `lined` (wide ruled), `grid` (large grid),
`dotted` and, since the documents update, `collegeRuled`, `narrowRuled`, `gridSmall`, `cornell`,
`music`, `isometric`. Unknown values are shown as `blank` but kept as-is in storage, so editing
other fields of the page on an older device does not erase a newer device's template.

Optional `pages` fields (`?` above; absent on data written by older app versions). As for
notebooks, a missing field keeps the local page's value; the defaults below apply to a page new to
this device:

- `paperColor`: string, `white` | `cream` | `grey` | `dark`; missing → `white` (see above), unknown → shown as `white`.
- `bookmarked`: bool; missing → `false`.
- `background`: object or `null`. `{"type": "pdf", "blob": "<sha256>", "page": <int>}` renders
  page `page` (0-based) of the PDF stored as blob `<sha256>` behind the strokes. Backgrounds with
  an unknown `type` are ignored (the page is shown without background).
