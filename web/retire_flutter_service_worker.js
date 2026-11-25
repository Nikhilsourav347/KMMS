const flutterCacheNames = [
  'flutter-app-manifest',
  'flutter-temp-cache',
  'flutter-app-cache',
];

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    await Promise.all(flutterCacheNames.map((name) => caches.delete(name)));
    await self.registration.unregister();
    const pages = await self.clients.matchAll({
      type: 'window',
      includeUncontrolled: true,
    });
    for (const page of pages) {
      if (page.url.startsWith(self.registration.scope)) {
        await page.navigate(page.url);
      }
    }
  })());
});
