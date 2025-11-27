importScripts("https://www.gstatic.com/firebasejs/8.10.0/firebase-app.js");
importScripts("https://www.gstatic.com/firebasejs/8.10.0/firebase-messaging.js");

// Initialize the Firebase app in the service worker
firebase.initializeApp({
  apiKey: "GOOGLE_MAPS_API_KEY",
  authDomain: "lighthouse-2498c.firebaseapp.com",
  projectId: "lighthouse-2498c",
  storageBucket: "lighthouse-2498c.firebasestorage.app",
  messagingSenderId: "572669546401",
  appId: "1:572669546401:web:7830430c557c6edb1845e0"
});

// Retrieve an instance of Firebase Messaging so that it can handle background messages
const messaging = firebase.messaging();

// Handle background messages
messaging.onBackgroundMessage((payload) => {
  console.log('[firebase-messaging-sw.js] Received background message', payload);

  const notificationTitle = payload.notification?.title || 'New Notification';
  const notificationOptions = {
    body: payload.notification?.body || 'You have a new message',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png'
  };

  return self.registration.showNotification(notificationTitle, notificationOptions);
});
