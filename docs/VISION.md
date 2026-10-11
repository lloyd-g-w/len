# Len — Product Vision

Len is a handwriting-first note-taking app in the spirit of **Notewise** and **GoodNotes**.

## Targets

- **Windows** (desktop)
- **Linux** (desktop)
- **Android** (phones + tablets; Samsung Galaxy Tab / S Pen is the primary stylus target)
- **Web** (any modern browser; installable PWA, data in the browser, same sync server)
- iOS / iPadOS are *not* required, but nothing should be done that rules them out (Flutter keeps the door open).

## Status

Pre-release. Breaking changes (data format, sync protocol, settings) are fine; no
backwards-compatibility code is wanted until the first release.

## Core requirements

1. **Excellent stylus support**
   - **Pen line-up (user decision): just a Pen (ballpoint) and a Highlighter**, plus the eraser.
     Fewer, better tools: quality of feel and look beats variety. One-tap quick colours and
     widths (GoodNotes / Notewise style) rather than many pen types.
   - UI/UX — especially for pens — is reviewed and polished continuously.
   - Pressure-sensitive, low-latency ink whose edges are perfectly smooth at any zoom.
   - Samsung S Pen first-class: pressure, side button (hold → temporary eraser), eraser end / inverted stylus.
   - Palm rejection: once a stylus is detected, fingers pan/zoom and only the stylus draws (toggleable).
   - Mouse and touch drawing still work on devices without a stylus.

2. **Two notebook kinds**
   - **Paged notebooks** — classic page-by-page notebooks with paper styles (blank, lined, grid, dotted).
   - **Infinite canvas** — a whiteboard that is *truly* infinite: never needs clearing, and cost scales
     with what is on screen, not with how much has been drawn overall.
     - Backed by a **sparse spatial structure** (chunked spatial hash) so only populated regions exist.
     - Strokes are loaded lazily from the database by region and rendered only when visible.

3. **Easy self-hosted cloud sync**
   - A tiny sync server shipped in this repo (`server/`), runnable with a single `docker compose up`.
   - Single SQLite file on the server; no external DB to manage.
   - Offline-first: the app works fully offline and syncs when a server is configured and reachable.
   - See [`SYNC_PROTOCOL.md`](SYNC_PROTOCOL.md).

4. **Nice, calm UI**
   - Library of notebooks with covers; a floating, uncluttered toolbar in the editor.
   - Light and dark themes.

5. **Clean, maintainable code**
   - Clear layering (domain → data → ink engine → features/UI), small files, unit tests for core logic.
   - `flutter analyze` must be clean.

## MVP scope (v0.1)

- Library: create / rename / delete paged notebooks and infinite canvases.
- Editor: pen, highlighter, stroke eraser, colour + width, undo/redo, pan/zoom (touch, trackpad, mouse wheel).
- Paged notebooks: add pages, navigate pages, paper styles.
- Infinite canvas: chunked sparse storage + lazy loading + per-chunk render caching.
- Local persistence (SQLite).
- Sync: settings screen (server URL + token), manual "Sync now" + periodic sync.
- Server: Dart + SQLite, Docker image, shared-token auth.

## Later ideas

- Pixel / partial-stroke eraser, lasso select + move/resize, shapes, text boxes, images.
- PDF import and annotation, export to PDF/PNG.
- Level-of-detail rendering for extreme zoom-out on the infinite canvas.
- Folders / tags, search (handwriting recognition).
- Per-user accounts on the server, end-to-end encryption.
- Android low-latency front-buffer rendering: experimental overlay exists (setting), to be tuned on devices.
