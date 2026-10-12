// WorshipStudio service worker: makes the app installable and usable offline.
//
// CACHE and SHELL below are development defaults: tool/postbuild.js rewrites
// them in build/web with the full file list and a hash of the build.
//
// Navigations are network-first (so a new deploy is picked up when online)
// with the cached shell as fallback. Everything else is served from cache
// and refreshed in the background, including the fonts Flutter fetches from
// fonts.gstatic.com and the Firebase SDK loaded from www.gstatic.com.

const CACHE = 'worship-studio-v1';
const SHELL = ['./', 'index.html', 'manifest.json', 'flutter_bootstrap.js', 'main.dart.js', 'favicon.png',
  'icons/Icon-192.png', 'icons/Icon-512.png'];
const RUNTIME_ORIGINS = ['https://fonts.gstatic.com', 'https://www.gstatic.com'];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE)
      // One missing file must not block installation.
      .then((cache) => Promise.all(SHELL.map((url) => cache.add(url).catch(() => null))))
      .then(() => self.skipWaiting()),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  );
});

async function fromNetwork(request) {
  const response = await fetch(request);
  if (response.ok) {
    const cache = await caches.open(CACHE);
    cache.put(request, response.clone());
  }
  return response;
}

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  const sameOrigin = url.origin === self.location.origin;
  if (!sameOrigin && !RUNTIME_ORIGINS.includes(url.origin)) return;
  if (sameOrigin && url.pathname.startsWith('/api/')) return; // backend calls are never cached

  if (request.mode === 'navigate') {
    event.respondWith(
      fromNetwork(request).catch(async () =>
        (await caches.match(request)) || (await caches.match('index.html')) || Response.error()),
    );
    return;
  }

  event.respondWith(
    caches.match(request).then((cached) => {
      const fresh = fromNetwork(request);
      if (cached) {
        fresh.catch(() => null); // background refresh; offline is fine
        return cached;
      }
      return fresh;
    }),
  );
});
