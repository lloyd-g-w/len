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
No auth. `200 {"status":"ok","protocol":1}`

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
| `notebooks` | `{title, kind: "paged"|"canvas", paper, coverColor, createdAt}`                         |
| `pages`     | `{notebookId, sortKey, width, height, paper}`                                            |
| `strokes`   | `{surfaceId, tool, color, width, points (base64 little-endian Float32 x,y,pressure triples), createdAt, style?}` — `tool` ∈ `pen` (legacy), `ballpoint`, `fountain`, `brush`, `pencil`, `marker`, `highlighter`; unknown tools render as `pen`. Optional `style` = `{o: opacity, th: thinning, sl: streamline, ts?: taperStart, te?: taperEnd}` (missing → per-tool defaults; unknown keys ignored). |
| `elements`  | `{surfaceId, type, x, y, w, h, rotation, z, createdAt, data}` — a non-ink object on a surface. `x, y, w, h` is the unrotated box in world units, `rotation` is clockwise radians about its centre, `z` the stacking order among elements (missing → `createdAt`). `type` = `text` (`data` = `{text, size, color, bold, italic, align: "left"|"center"|"right"}`); reserved: `image` (`data.blob` = content hash of a blob). Unknown types are stored and synced unchanged but not rendered; unknown `data` keys survive local edits. |
