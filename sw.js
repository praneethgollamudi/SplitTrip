/* SplitTrip R14.7.33.3 — offline app-shell service worker */
const CACHE_NAME = 'splittrip-shell-r14-7-33-3';
const APP_SHELL = [
  './index.html',
  './manifest.webmanifest',
  './favicon.svg',
  './icons/icon-192.png',
  './icons/icon-512.png',
  './icons/icon-512-maskable.png'
];

self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);
    await cache.add('./index.html');
    await Promise.allSettled(
      APP_SHELL.filter(path => path !== './index.html')
        .map(path => cache.add(path))
    );
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(
      keys.filter(key => key.startsWith('splittrip-shell-') && key !== CACHE_NAME)
        .map(key => caches.delete(key))
    );
    await self.clients.claim();
  })());
});

self.addEventListener('message', event => {
  if (event.data?.type === 'SKIP_WAITING') self.skipWaiting();
});

self.addEventListener('fetch', event => {
  const request = event.request;
  const url = new URL(request.url);
  if (request.method !== 'GET' || url.origin !== self.location.origin) return;
  if (/\/(rest|auth|storage)\/v1\//.test(url.pathname)) return;

  if (request.mode === 'navigate') {
    event.respondWith((async () => {
      const cache = await caches.open(CACHE_NAME);
      try {
        const response = await fetch(request);
        if (response?.ok) await cache.put('./index.html', response.clone());
        return response;
      } catch {
        const cached = await cache.match('./index.html');
        return cached || new Response(
          '<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><title>SplitTrip</title><main style="font:16px system-ui;padding:2rem">SplitTrip is not cached yet. Connect once and open the app before using it offline.</main>',
          {status:503,headers:{'Content-Type':'text/html; charset=utf-8'}}
        );
      }
    })());
    return;
  }

  const shellUrls = APP_SHELL.map(path => new URL(path, self.registration.scope).href);
  if (shellUrls.includes(request.url)) {
    event.respondWith((async () => {
      const cached = await caches.match(request);
      return cached || fetch(request);
    })());
  }
});
