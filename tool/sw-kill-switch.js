// Kill switch, not a real service worker.
//
// The app is built with --pwa-strategy=none, so Flutter no longer generates a
// worker and nothing registers one. But browsers that loaded an older build
// still hold a registration for THIS url, and they keep serving its cached
// `main.dart.js` and tree-shaken icon fonts — which is how a newly shipped
// icon can be missing on a client while the live site is correct.
//
// Two non-fixes: deleting the file lets the hosting rewrite (`**` ->
// /index.html) answer the url with index.html as text/html, so the update
// check fails on the MIME type and the stale worker survives; and the empty
// file `--pwa-strategy=none` emits only replaces the worker once every old tab
// closes. Serving a real script that unregisters itself clears those clients
// now — the update check succeeds, this worker activates, drops every cache,
// and reloads open tabs onto the network.
//
// deploy-web.sh copies this over the empty file in build/web after the build.
self.addEventListener('install', () => self.skipWaiting());

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    await self.registration.unregister();
    await Promise.all((await caches.keys()).map((k) => caches.delete(k)));
    for (const client of await self.clients.matchAll({type: 'window'})) {
      try {
        client.navigate(client.url);
      } catch (_) {
        // A client this worker does not control cannot be navigated; it picks
        // up the new build on its next reload anyway.
      }
    }
  })());
});
