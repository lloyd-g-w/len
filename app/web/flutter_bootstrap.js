{{flutter_js}}
{{flutter_build_config}}

// One tab at a time has Len open (lib/platform/single_instance_web.dart).
// A reload of that tab asks for it back right away, before a waiting tab
// that got it meanwhile starts using it.
window.lenTab = { id: Math.random().toString(36).slice(2, 10), reclaim: false };
try {
  const navigation = performance.getEntriesByType('navigation')[0];
  if (sessionStorage.getItem('len-held') && navigation?.type === 'reload' && navigator.locks) {
    window.lenTab.reclaim = true;
    new BroadcastChannel('len-database').postMessage('take:' + window.lenTab.id);
  }
} catch (e) {
  // No session storage (blocked): the reload waits like any other tab.
}

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
