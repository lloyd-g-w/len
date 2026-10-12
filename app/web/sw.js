'use strict';
// Len's offline service worker: the installed app (PWA) opens without a
// network after its first visit.
//
// * Precache: the build's files (app shell, CanvasKit, sqlite3.wasm, PDFium
//   wasm, fonts, icons). `tool/web_precache.dart` writes PRECACHE below
//   after `flutter build web`, so every build has new bytes here and the
//   browser installs the new worker (and drops the old cache). Unprocessed
//   (e.g. `flutter run`): an empty list, runtime caching only.
// * Serving: cache first for the app's own static files (versioned with
//   the worker); navigations get the cached index.html. Fonts from
//   fonts.gstatic.com (Flutter's default and fallback fonts) are cached
//   in a cache that survives updates (their URLs are versioned).
// * Everything else (e.g. a sync server on the same origin) goes to the
//   network untouched.
// * Updates: a new worker takes over at once; the running page keeps its
//   loaded code, the next start uses the new build.

const PRECACHE = /* precache */ { version: 'dev', files: [] } /* end precache */;

const SHELL = 'len-shell-' + PRECACHE.version;
const FONTS = 'len-fonts-v1';
const FONT_HOSTS = ['fonts.gstatic.com', 'fonts.googleapis.com', 'www.gstatic.com'];
// Same-origin paths (relative to the worker's scope) cached on first use.
const STATIC = /^(?:$|index\.html$|flutter.*\.js$|main\.dart\.(?:js|mjs|wasm)$|manifest\.json$|favicon\.png$|sqlite3\.wasm$|(?:assets|canvaskit|icons)\/)/;

const scope = new URL(self.registration.scope);

self.addEventListener('install', (event) => {
  event.waitUntil(
    (async () => {
      const cache = await caches.open(SHELL);
      // `reload`: bypass the HTTP cache so a new build never stores old files.
      await cache.addAll(PRECACHE.files.map((f) => new Request(f, { cache: 'reload' })));
      await self.skipWaiting();
    })(),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      for (const key of await caches.keys()) {
        if (key.startsWith('len-') && key !== SHELL && key !== FONTS) await caches.delete(key);
      }
      await self.clients.claim();
    })(),
  );
});

/** The cache a GET of [url] belongs in, or null to leave it to the network. */
function cacheFor(url) {
  if (url.origin === scope.origin) {
    if (!url.pathname.startsWith(scope.pathname)) return null;
    return STATIC.test(url.pathname.slice(scope.pathname.length)) ? SHELL : null;
  }
  return FONT_HOSTS.includes(url.hostname) ? FONTS : null;
}

async function fromCacheOrNetwork(request, cacheName) {
  const cache = await caches.open(cacheName);
  const hit = await cache.match(request);
  if (hit) return hit;
  const response = await fetch(request);
  if (response.ok || response.type === 'opaque') {
    await cache.put(request, response.clone()).catch(() => {});
  }
  return response;
}

/** The app's page: cached index.html whatever the query (file handlers, ?…). */
async function page(request) {
  const cache = await caches.open(SHELL);
  const hit = (await cache.match(new URL('index.html', scope).href)) ?? (await cache.match(scope.href));
  if (hit) return hit;
  return fetch(request);
}

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (request.mode === 'navigate') {
    if (url.origin === scope.origin && cacheFor(url) === SHELL) event.respondWith(page(request));
    return;
  }
  const cacheName = cacheFor(url);
  if (cacheName) event.respondWith(fromCacheOrNetwork(request, cacheName));
});

// The page lists what it fetched before this worker controlled it.
self.addEventListener('message', (event) => {
  if (event.data?.type !== 'cache' || !Array.isArray(event.data.urls)) return;
  event.waitUntil(
    (async () => {
      for (const href of event.data.urls) {
        let url;
        try {
          url = new URL(href);
        } catch {
          continue;
        }
        const cacheName = cacheFor(url);
        if (!cacheName) continue;
        const cache = await caches.open(cacheName);
        if (await cache.match(url.href)) continue;
        try {
          const response = await fetch(url.href, url.origin === scope.origin ? {} : { mode: 'cors' });
          if (response.ok) await cache.put(url.href, response);
        } catch {
          // Offline or refused: cached on the next fetch instead.
        }
      }
    })(),
  );
});
