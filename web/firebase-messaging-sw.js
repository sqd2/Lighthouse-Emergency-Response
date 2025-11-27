importScripts("https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js");

// Initialize the Firebase app in the service worker
firebase.initializeApp({
  apiKey: "AIzaSyCvvz3UmQXQR9PzRUeYlNu2wJqpxG8FvuQ",
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
  console.log('[firebase-messaging-sw.js] Received background message ', payload);

  const notificationTitle = payload.notification.title;
  const notificationOptions = {
    body: payload.notification.body,
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png'
  };

  self.registration.showNotification(notificationTitle, notificationOptions);
});
