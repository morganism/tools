// Service Worker for non-blocking operations
// Handles caching and background tasks

const CACHE_NAME = 'apple-portfolio-v1';
const urlsToCache = [
  '/',
  '/index.html',
  '/src/main.tsx',
  '/src/index.css',
];

// Install event - cache resources
self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then((cache) => {
        console.log('Service Worker: Caching files');
        return cache.addAll(urlsToCache);
      })
      .catch((error) => {
        console.log('Service Worker: Cache failed', error);
      })
  );
});

// Activate event - clean up old caches
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((cacheNames) => {
      return Promise.all(
        cacheNames.map((cache) => {
          if (cache !== CACHE_NAME) {
            console.log('Service Worker: Clearing old cache');
            return caches.delete(cache);
          }
        })
      );
    })
  );
});

// Fetch event - serve from cache, fallback to network
self.addEventListener('fetch', (event) => {
  event.respondWith(
    caches.match(event.request)
      .then((response) => {
        // Return cached version or fetch from network
        return response || fetch(event.request);
      })
      .catch(() => {
        // Fallback for offline
        console.log('Service Worker: Fetch failed, offline mode');
      })
  );
});

// Background sync for form submissions
self.addEventListener('sync', (event) => {
  if (event.tag === 'sync-forms') {
    event.waitUntil(syncForms());
  }
});

async function syncForms() {
  // Handle background form synchronization
  console.log('Service Worker: Syncing forms in background');
  // This would typically sync any pending form submissions
  return Promise.resolve();
}

// Push notifications (if needed in future)
self.addEventListener('push', (event) => {
  const data = event.data ? event.data.json() : {};
  const title = data.title || 'New Notification';
  const options = {
    body: data.body || 'You have a new message',
    icon: '/icon.png',
    badge: '/badge.png',
  };

  event.waitUntil(
    self.registration.showNotification(title, options)
  );
});

// Message handling for communication with main thread
self.addEventListener('message', (event) => {
  if (event.data && event.data.type === 'SKIP_WAITING') {
    self.skipWaiting();
  }
  
  // Handle async operations requested from main thread
  if (event.data && event.data.type === 'ASYNC_OPERATION') {
    handleAsyncOperation(event.data.payload)
      .then((result) => {
        event.ports[0].postMessage({ success: true, result });
      })
      .catch((error) => {
        event.ports[0].postMessage({ success: false, error: error.message });
      });
  }
});

async function handleAsyncOperation(payload) {
  // Simulate non-blocking async operation
  return new Promise((resolve) => {
    setTimeout(() => {
      resolve({ processed: true, data: payload });
    }, 100);
  });
}
