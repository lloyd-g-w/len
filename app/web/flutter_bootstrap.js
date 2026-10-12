{{flutter_js}}
{{flutter_build_config}}

// No `serviceWorkerSettings`: Flutter's own service worker is deprecated (it
// only unregisters itself). Len registers its offline worker, sw.js, below.
_flutter.loader.load();

// Offline support for the installed app (see sw.js). Service workers need a
// secure context (https or localhost).
if ('serviceWorker' in navigator && window.isSecureContext) {
  navigator.serviceWorker
    .register('sw.js')
    .then(() => navigator.serviceWorker.ready)
    .then((registration) => {
      // Files this page fetched before the worker controlled it (the first
      // visit) — e.g. the default font from fonts.gstatic.com — are cached
      // now; later fetches are cached by the worker as they happen.
      const send = () =>
        registration.active?.postMessage({
          type: 'cache',
          urls: performance.getEntriesByType('resource').map((e) => e.name),
        });
      send();
      setTimeout(send, 10000);
    })
    .catch((e) => console.warn('Len: no offline support:', e));
}
