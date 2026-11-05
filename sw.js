const CACHE_NAME = 'splittrip-shell-r14-7-32-1';
const APP_SHELL = [
  './index.html',
  './manifest.webmanifest',
  './favicon.svg',
  './favicon.svg',
  './icons/icon-192.png',
  './icons/icon-512.png',
  './icons/icon-512-maskable.png'
];
self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);
    await cache.addAll(APP_SHELL);
  })());
});
self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter(key => key.startsWith('splittrip-shell-') && key !== CACHE_NAME).map(key => caches.delete(key)));
    await self.clients.claim();
  })());
});
self.addEventListener('message', event => {
  if (event.data && event.data.type === 'SKIP_WAITING') self.skipWaiting();
});
self.addEventListener('fetch', event => {
  const request = event.request;
  const url = new URL(request.url);
  // Never intercept Supabase, third-party, non-GET, or cross-origin traffic.
  if (request.method !== 'GET' || url.origin !== self.location.origin) return;
  if (url.pathname.includes('/rest/v1/') || url.pathname.includes('/auth/v1/') || url.pathname.includes('/storage/v1/')) return;
  if (request.mode === 'navigate') {
    event.respondWith((async () => {
      try {
        const response = await fetch(request);
        if (response && response.ok) {
          const cache = await caches.open(CACHE_NAME);
          cache.put('./index.html', response.clone());
        }
        return response;
      } catch (error) {
        const cache = await caches.open(CACHE_NAME);
        return (await cache.match('./index.html')) || Response.error();
      }
    })());
    return;
  }
  // Cache only the explicitly versioned app shell assets; leave all other requests alone.
  if (APP_SHELL.some(path => new URL(path, self.registration.scope).href === request.url)) {
    event.respondWith((async () => (await caches.match(request)) || fetch(request))());
  }
});
