# Len Sync Protocol — v1

The server is a **generic last-write-wins record store with a change feed**. It knows nothing about
notebooks or strokes; it just stores opaque JSON records grouped by `collection`. This keeps the
server tiny and lets the app evolve its data model without server changes.

**Compatibility.** Len is pre-release: this document describes the one current format, and
changes to it need no compatibility with earlier builds (all devices are expected to run the same
version). Once Len ships, changes must stay compatible in both directions: new fields optional with
defaults, unknown fields and values tolerated.

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
`200 {"status":"ok","protocol":1,"maxBlobBytes":209715200,"blobsCollectedAt":0}`

`maxBlobBytes` is the largest blob the server accepts (`LEN_BLOB_MAX_BYTES`), so clients can skip
blobs that are too large without sending them. `blobsCollectedAt` is when (ms since epoch) the
server last deleted blobs by [garbage collection](#blob-garbage-collection), 0 if never. Clients
ignore unknown fields here, and treat an answer without these fields (e.g. from a proxy) as "not
known".

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
server stops adding records once their payloads (the UTF-8 bytes of their stored `data` JSON) add
up to 8 MiB (always returning at least one), so responses stay bounded when records are large.
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
  streamed body exceeds it; nothing is stored and the connection is closed (a client still
  sending may see the connection reset instead of the answer). Retrying the same blob is
  pointless until the limit changes (a reverse proxy in front of the server may also answer `413`
  with its own, smaller limit).
- A **stalled** upload — no body data for `LEN_BLOB_IDLE_TIMEOUT` seconds (default 60) — is
  abandoned: nothing is stored, the temporary file is removed and the connection is closed (the
  server may answer `408 {"error": "upload stalled"}` first). Clients retry later.

The server hashes while streaming to a temporary file, flushes it to disk (`fsync`) and atomically
renames it into place, then flushes the directory, so a blob is only ever visible complete and
verified (also after a crash or power loss), and concurrent uploads of the same blob are safe. Temporary files
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
- When the server URL changes, the "uploaded" and "too large" marks are reset along with
  `lastPulledSeq`.
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
once no live local row references it (page backgrounds, image templates of pages, image elements, recordings (audio parts and waveform) and the user's
templates; pages, elements and recordings of trashed notebooks are live rows, so they count) for 7 days. The app
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
| `folders`   | `{name, parentId: string|null, color, createdAt}` |
| `notebooks` | `{title, kind: "paged"|"canvas", paper, paperData: object, paperColor, coverColor, createdAt, editedAt, folderId: string|null, favorite: bool, trashedAt: int|null}` |
| `pages`     | `{notebookId, sortKey, width, height, paper, paperData: object, paperColor, bookmarked: bool, background: object|null}` — see [Paper and pages](#paper-and-pages) |
| `templates` | `{name, blob, width, height, createdAt}` — one of the user's own templates ("My templates"): `blob` is the `<sha256>` of a PNG or JPEG image ([blob](#blobs)), `width` / `height` (> 0) the size in world units (96 per inch) of pages made from it. Pages made from a template copy its blob into their `paperData`, so renaming or deleting (tombstoning) a template never changes existing pages. |
| `strokes`   | `{surfaceId, tool, color, width, points (base64 little-endian Float32 x,y,pressure triples), createdAt, style}` — `tool` ∈ `ballpoint` (the pen), `highlighter`. `style` = `{o: opacity, th: thinning, sl: streamline, u?: unit, e: ends, ts?: taperStart, te?: taperEnd, cs?: cutStart, ce?: cutEnd}` (`o`, `th`, `sl` in 0..1; `u`: world units per screen pixel when written, i.e. 1 / zoom; absent → estimated from the points). `e` is required: `round`, `flat` or `taper`; `ts` and `te` are required for `taper` only, each 0..24 multiples of stroke width (0 means round at that end). `cs` and `ce` mark ends cut by the pixel eraser (absent for the pen's own ends): `cs` (0 < cs ≤ 1) is where the first resampled point of the centre line lies after the first point, in resampling steps, so a fragment resamples where the stroke it was cut from did; `ce` is `true`. Cut ends have no pen-down/up hook trimmed. Unknown keys ignored. The highlighter has flat caps regardless of pen settings. `createdAt` is the wall time (epoch ms) the stroke was *begun* (pen down), not finished: strokes are painted in this order, and audio replay shows a stroke from the moment writing it started. |
| `elements`  | `{surfaceId, type, x, y, w, h, rotation, z, createdAt, data}` — a non-ink object on a surface. `x, y, w, h` is the unrotated box in world units, `rotation` is clockwise radians about its centre, `z` the stacking order among elements. `type` = `text` (`data` = `{text, spans, paras, font, size, color, align, autoWidth}`, see [Text boxes](#text-boxes)), `image` (`data` = `{blob, width, height, crop?}`, see below) or `link` (`data` = `{target}`, see [Links](#links)). Elements with `z < 0` are drawn beneath the ink, the others above it. Unknown types are stored and synced unchanged but not rendered; unknown `data` keys survive local edits. |
| `recordings` | `{notebookId, audio, durationMs, startedAt, title, mime, segments, waveform, trimStartMs, trimEndMs}` — an audio recording of a notebook. `audio` = `[[<sha256>, durationMs], …]` (never empty) are the parts of the audio in order, each a [blob](#blobs) of `mime`: `audio/aac` (raw AAC in ADTS frames; parts join by concatenation into one stream), `audio/mp4` AAC or `audio/webm` Opus (recorded in browsers; each part a complete file, played one after the other). A recording being made gains a part every few minutes, so the record is updated (and its finished parts uploaded) while recording continues. `durationMs` is the audio length (the sum of the parts); `startedAt` is the wall time (epoch ms) recording began; `segments` = `[[startedAt, durationMs], …]` are the stretches captured between pauses, mapping audio time to wall time so ink (`strokes.createdAt`) can be replayed with it (empty → one segment `[startedAt, durationMs]`); ink and elements are replayed from their `createdAt`. `waveform` is `""` (none) or the `<sha256>` of the recording's [waveform](#waveforms) blob. `trimStartMs` / `trimEndMs` (ints, `0 ≤ trimStartMs ≤ trimEndMs ≤ durationMs`, else malformed) are the audio kept by a non-destructive trim, positions in the whole audio: `0` and `durationMs` when untrimmed (a recording being made stays untrimmed). Clients play, list, replay and export only the kept range; the parts keep all the audio, so trimming back restores it. Deleting a notebook tombstones its recordings. |
| `outline`   | `{notebookId, pageId, parentId: string|null, title, createdAt}` — an entry of a notebook's own outline (table of contents) leading to page `pageId`. Entries nest by `parentId` (null = top level). There is no stored order: siblings are shown in the order of their pages in the notebook (then by `createdAt`), so reordering pages reorders the outline and concurrent additions never conflict. An entry whose parent is missing, or that is part of a parent cycle, is shown at the top level; one whose page was deleted is shown as such (deleting a page keeps its entries, so undoing the deletion restores them). Deleting an entry moves its children to its parent. |

**Not synced: the search index.** Full-text search (`search_docs`, `search_fts`, and the PDF text
cache `pdf_text`) is derived on each device from the collections above and the PDF blobs, and is
updated when records are applied by sync like any local write. Nothing about it travels over the
wire, so search needs no protocol change.

**Validation.** Every field listed for a collection is required (fields typed `…|null` must be
present, possibly `null`), and enumerated values must be ones listed here. A record that is missing
a field, has a value of the wrong type or an unknown enumerated value is malformed: the client skips
it (see [Client algorithm](#client-algorithm)). Unknown extra fields are ignored. Exceptions: an
element's `type` and the contents of its `data` are open (see its row), and `strokes` (see its row).

Enumerated values: `kind` as above (notebooks); `paper` and `paperColor` see [Paper and pages](#paper-and-pages);
`color`, `coverColor` are ARGB ints.

**Library semantics.**
- `folders.parentId` is null for top-level folders. A folder whose parent is missing/deleted is shown
  at the top level; so is every folder in a parent cycle (possible after concurrent moves on two
  devices). Deleting a folder tombstones its whole subtree and moves the notebooks inside to the trash.
- `notebooks.folderId` pointing at a missing folder means "library root".
- `notebooks.trashedAt` (ms) puts a notebook in the trash; it stays a live record so it can be
  restored. "Delete forever" tombstones the notebook, its pages, strokes, elements, recordings and
  outline entries. Duplicating a notebook copies its outline (onto the copied pages).
- `notebooks.paperColor` is the background of a canvas (same values as on pages);
  `notebooks.paper` + `paperData` its pattern.
- `editedAt` is the last content/title edit (used for "last edited" sorting); organisation changes
  (favourite, move, trash) only bump `updatedAt`.

**Text boxes.** `text` is the plain text (lines separated by `\n`; what search indexes);
`font` ∈ `inter`, `lora`, `mono`, `caveat` (the bundled fonts), `size` the body font size in world
units (6–400), `color` an ARGB int, `align` ∈ `left`, `center`, `right`, and `autoWidth` whether the
box grows with its text (`true`) or wraps at its width. Formatting is compact:

- `spans` = `[[start, end, style], …]` — character formatting of the UTF-16 range `[start, end)` of
  `text`, sorted, non-overlapping, never empty or unformatted. `style` holds only what is set:
  `b`, `i`, `u`, `s` (bold, italic, underline, strikethrough; `true`), `c` (colour) and `hl`
  (highlight, translucent) as ARGB ints, `sz` (size in world units), `f` (font, as `font`). Unset
  attributes take the box's.
- `paras` = `[para, …]` — empty when no line is formatted, else one object per line: `h` heading
  level (1 or 2), `l` list ∈ `bullet`, `number`, `check`, `x` ticked (`true`, checklists), `n` list
  indent level (1–4); `{}` is body text. Numbers are not stored (they count consecutive items).

Example: `{"text": "Todo\nmilk", "spans": [[0, 4, {"b": true}]], "paras": [{"h": 1}, {"l": "check",
"x": true}], "font": "inter", "size": 24, "color": 4280229663, "align": "left", "autoWidth": true}`.
Readers ignore spans and paragraph entries they cannot use and unknown keys (the contents of
`data` are open).

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

**Links.** A `link` element is an invisible region (its box, usually around content) that leads
somewhere when tapped; clients mark it with a subtle affordance but never draw it into thumbnails
or exports (PDF exports write it as a link annotation). `data.target` is either
`{"notebook": "<notebook id>", "page": "<page id>"}` — a page, found by id so reordering pages never
breaks the link; the notebook may be another one — or `{"url": "<address>"}` with an `http`,
`https` or `mailto` URL. Links are created beneath the ink (negative `z`). A link whose target is
missing or invalid is kept but does nothing (clients say the page was deleted).

**Waveforms.** A recording's loudness outline for the player's scrubber, captured from the
recorder's input level while recording (no decoding needed), stored as a blob of type
`application/x-len-waveform`: the bytes `0x4C 0x57` ("LW"), a version byte (`1`), the bucket
length in units of 10 ms (`10` = 100 ms), then one byte per bucket — the loudest level heard in
it, 0 (silence) … 255, on a decibel scale (−50 dBFS … 0). Buckets cover the audio from its start
(pauses are not part of the audio); a shorter waveform than the audio means silence at the end.
Readers ignore waveforms with another version or magic.

**Paper and pages.** `paper` names a template: `blank`, `dotted`, `narrowRuled`,
`collegeRuled`, `wideRuled`, `cornell`, `todo`, `meeting`, `dailyPlanner`, `weeklyPlanner`,
`monthlyCalendar`, `yearlyOverview`, `gridSmall`, `gridLarge`, `graph`, `engineering`, `isometric`, `music`,
`storyboard`, or `image` (a user's image template). On notebooks (the default for new pages and
the canvas background) it must be a template without parameters, i.e. not a planner and not
`image`, and its `paperData` is just `{"look": look}`. On pages, `paperData` holds the template's
parameters and its `look`, and must be valid for it:

- planners (`dailyPlanner`, `weeklyPlanner`, `monthlyCalendar`, `yearlyOverview`):
  `{"date": "YYYY-MM-DD", "weekStart": "monday"|"sunday", "locale": "<tag>"}`, all required.
  `date` is the first day of the page's period (the day; the first day of the week, a Monday or
  Sunday as `weekStart` says; the 1st of the month; 1 January). `locale` is the language the
  page is printed in, one of the BCP 47 tags `en-GB`, `en-US`, `cs`, `da`, `de`, `es`, `fr`,
  `it`, `nl`, `nb`, `pl`, `pt-BR`, `pt-PT`, `fi`, `sv`, `tr`, `el`, `ru`, `uk` (exactly as
  written). Planner links find the page with the same style, date, `weekStart` and `locale`,
  so the date is normalised to the period's start when written;
- `image`: `{"image": "<sha256>"}`, a PNG or JPEG [blob](#blobs) stretched over the page;
- every other template: nothing but the look.

Every `paperData` has a `look` (required): how the template is drawn, `{"spacing": mm|null,
"lineWeight": number, "dotSize": number, "patternColor": int|null, "patternOpacity": number,
"margin": bool, "header": bool}`, all fields required. `spacing` is the pattern pitch in
millimetres (line distance, grid cell, dot spacing, staff line distance; `null` = the template's
own; only ruled, Cornell, to-do and meeting pages, grids, isometric, dotted and music paper use
it); `lineWeight` and `dotSize` scale the default line thickness and dot size (0.5–3);
`patternColor` is the ARGB colour of lines and dots (`null` = derived from the paper colour);
`patternOpacity` (0.1–1) scales its opacity; `margin` whether ruled pages show their margin line;
`header` whether a page has a header area ruled off at the top (blank, dotted, ruled, grid,
graph and isometric pages). Readers clamp numbers to these ranges; a missing field or one of the
wrong type makes the record malformed. Example: `{"look": {"spacing": 5, "lineWeight": 1,
"dotSize": 1.5, "patternColor": null, "patternOpacity": 0.8, "margin": true, "header": false}}`.

`paperColor` is one of `white`, `cream`, `grey`, `dark`, or a custom colour `#RRGGBB` (six
upper-case hex digits).

- `bookmarked`: whether the page is bookmarked.
- `background`: `null`, or `{"type": "pdf", "blob": "<sha256>", "page": <int ≥ 0>}`, which renders
  page `page` (0-based) of the PDF stored as blob `<sha256>` behind the strokes. Any other value
  makes the record malformed.
