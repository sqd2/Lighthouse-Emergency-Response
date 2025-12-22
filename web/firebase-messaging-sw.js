importScripts("https://www.gstatic.com/firebasejs/8.10.0/firebase-app.js");
importScripts("https://www.gstatic.com/firebasejs/8.10.0/firebase-messaging.js");

// Initialize the Firebase app in the service worker with Firebase-generated API key
firebase.initializeApp({
  apiKey: "AIzaSyBOawlsvCMxrDlC8fV2oUnja_fd3bXd4gY",
  authDomain: "lighthouse-2498c.firebaseapp.com",
  projectId: "lighthouse-2498c",
  storageBucket: "lighthouse-2498c.firebasestorage.app",
  messagingSenderId: "572669546401",
  appId: "1:572669546401:web:7830430c557c6edb1845e0",
  measurementId: "G-NET6W8XQD4"
});

// Retrieve an instance of Firebase Messaging so that it can handle background messages
const messaging = firebase.messaging();

// Handle background messages - coordinate with page to avoid duplicates
messaging.onBackgroundMessage(async (payload) => {
  console.log('[SW] Background message received:', payload);

  // Try to notify page first - let it handle the notification
  const clients = await self.clients.matchAll({
    type: 'window',
    includeUncontrolled: true
  });

  console.log('[SW] Found clients:', clients.length);

  if (clients.length > 0) {
    console.log('[SW] Page is open - sending message to page');

    for (const client of clients) {
      try {
        client.postMessage({
          type: 'FCM_MESSAGE',
          payload: payload
        });
        console.log('[SW] Message sent to page');
      } catch (error) {
        console.log('[SW] Failed to send to client:', error);
      }
    }

    console.log('[SW] Returning - page will handle notification');
    return; // CRITICAL: Return early to prevent showing notification
  }

  // No clients - page is closed, show notification from service worker
  console.log('[SW] Page is closed - showing notification from service worker');

  // Extract title and body from data field (data-only messages)
  const notificationTitle = payload.data?.title || payload.notification?.title || 'New Notification';
  const notificationBody = payload.data?.body || payload.notification?.body || 'You have a new message';

  const notificationOptions = {
    body: notificationBody,
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    tag: 'lighthouse-notif',
    requireInteraction: false,
    renotify: false
  };

  console.log('[SW] Showing notification:', notificationTitle);
  return self.registration.showNotification(notificationTitle, notificationOptions);
});

console.log('[SW] Service worker ready');
