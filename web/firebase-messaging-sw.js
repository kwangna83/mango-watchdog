importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');

firebase.initializeApp({
  // Replace these public Firebase Web values for the mango-watchdog project.
  apiKey: 'REPLACE_FIREBASE_WEB_API_KEY',
  authDomain: 'REPLACE_FIREBASE_WEB_AUTH_DOMAIN',
  projectId: 'REPLACE_FIREBASE_PROJECT_ID',
  storageBucket: 'REPLACE_FIREBASE_STORAGE_BUCKET',
  messagingSenderId: 'REPLACE_FIREBASE_MESSAGING_SENDER_ID',
  appId: 'REPLACE_FIREBASE_WEB_APP_ID',
});

const messaging = firebase.messaging();

self.addEventListener('install', () => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

messaging.onBackgroundMessage((message) => {
  const data = message.data || {};
  const unreadCount = Number.parseInt(data.unreadCount || '0', 10);
  if ('setAppBadge' in self.navigator) {
    if (unreadCount > 0) {
      self.navigator.setAppBadge(unreadCount).catch(() => {});
    } else {
      self.navigator.clearAppBadge().catch(() => {});
    }
  }
  if (message.notification) return;
  self.registration.showNotification(data.title || 'MangoTalk', {
    body: data.body || '새 메시지가 도착했어요.',
    icon: 'icons/Icon-192.png',
    badge: 'icons/Icon-192.png',
    data,
  });
});

self.addEventListener('message', (event) => {
  if (event.data?.type !== 'CLEAR_APP_BADGE') return;
  if ('clearAppBadge' in self.navigator) {
    event.waitUntil(self.navigator.clearAppBadge().catch(() => {}));
  }
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const roomId = event.notification.data?.roomId;
  const target = new URL('./', self.registration.scope);
  if (roomId) target.searchParams.set('room', roomId);
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((windows) => {
      for (const windowClient of windows) {
        if (windowClient.url.startsWith(self.registration.scope)) {
          windowClient.navigate(target.href);
          return windowClient.focus();
        }
      }
      return clients.openWindow(target.href);
    }),
  );
});
