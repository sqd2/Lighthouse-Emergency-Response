import 'dart:async';
import 'dart:js' as js;

/// Web-specific FCM token handling using JavaScript interop
class FCMWeb {
  /// Check browser notification permission without requesting
  static Future<String> checkBrowserPermission() async {
    try {
      final result = await _callAsyncJS('''
        (async function() {
          return Notification.permission;
        })()
      ''');
      return result?.toString() ?? 'default';
    } catch (e) {
      print('FCMWeb.checkBrowserPermission error: $e');
      return 'default';
    }
  }

  /// Request notification permission via browser API
  static Future<String> requestBrowserPermission() async {
    try {
      final result = await _callAsyncJS('''
        (async function() {
          console.log('=== Requesting Browser Notification Permission ===');
          console.log('Current permission:', Notification.permission);

          if (Notification.permission === 'granted') {
            console.log('Already granted');
            return 'granted';
          }

          try {
            const permission = await Notification.requestPermission();
            console.log('Permission result:', permission);
            return permission;
          } catch (error) {
            console.error('Error requesting permission:', error);
            return 'error';
          }
        })()
      ''');

      print('Browser permission result: $result');
      return result?.toString() ?? 'error';
    } catch (e) {
      print('FCMWeb.requestBrowserPermission error: $e');
      return 'error';
    }
  }

  /// Test notification - call this to verify notifications work
  static Future<void> testNotification() async {
    try {
      await _callAsyncJS('''
        (async function() {
          console.log('=== Testing Notification ===');

          // Check permission
          console.log('Current permission:', Notification.permission);

          if (Notification.permission !== 'granted') {
            console.log('Requesting permission...');
            const permission = await Notification.requestPermission();
            console.log('Permission result:', permission);
          }

          if (Notification.permission === 'granted') {
            console.log('Creating test notification...');
            const notification = new Notification('Test Notification', {
              body: 'This is a test notification from Lighthouse',
              icon: '/icons/Icon-192.png',
              badge: '/icons/Icon-192.png'
            });

            setTimeout(() => notification.close(), 5000);
            console.log('✅ Test notification shown');
          } else {
            console.error('❌ Notification permission denied');
          }
        })()
      ''');
    } catch (e) {
      print('FCMWeb.testNotification error: $e');
    }
  }

  /// Show a browser notification on web
  static Future<void> showNotification(String title, String body) async {
    try {
      await _callAsyncJS('''
        (async function() {
          try {
            // Check if notifications are supported
            if (!("Notification" in window)) {
              console.log('This browser does not support notifications');
              return;
            }

            // Check permission
            if (Notification.permission === 'granted') {
              // Show notification
              const notification = new Notification('$title', {
                body: '$body',
                icon: '/icons/Icon-192.png',
                badge: '/icons/Icon-192.png',
                tag: 'lighthouse-notification',
                requireInteraction: false
              });

              // Auto close after 5 seconds
              setTimeout(() => notification.close(), 5000);

              console.log('Notification shown:', '$title');
            } else {
              console.log('Notification permission not granted');
            }
          } catch (error) {
            console.error('Error showing notification:', error);
          }
        })()
      ''');
    } catch (e) {
      print('FCMWeb.showNotification error: $e');
    }
  }

  /// Set up foreground message listener using Firebase JS SDK
  static Future<void> setupForegroundListener() async {
    try {
      await _callAsyncJS('''
        (async function() {
          try {
            console.log('=== Setting up FCM foreground listener ===');

            // Check if listener already exists
            if (window.fcmListenerActive) {
              console.log('⚠️ Foreground listener already active, skipping setup');
              return;
            }

            if (typeof firebase === 'undefined') {
              console.error('❌ Firebase SDK not loaded');
              return;
            }
            console.log('✅ Firebase SDK is loaded');

            // Wait for service worker to be ready
            const registration = await navigator.serviceWorker.ready;
            console.log('✅ Service worker ready:', registration.scope);

            // Store messaging instance globally for debugging
            if (!window.fcmMessaging) {
              window.fcmMessaging = firebase.messaging();
              console.log('✅ Created new messaging instance');
            }
            const messaging = window.fcmMessaging;
            console.log('✅ Using messaging instance');

            // Check notification permission
            console.log('Notification permission:', Notification.permission);

            // Set up a test function to verify listener works
            window.testFCMListener = () => {
              console.log('Testing if FCM listener is active...');
              console.log('Messaging instance exists:', !!window.fcmMessaging);
            };
            console.log('✅ Test function available: window.testFCMListener()');

            // Function to show notification (used by both listeners)
            const showNotification = (title, body) => {
              console.log('[PAGE] 📬 Showing notification:', title, body);

              if (Notification.permission === 'granted') {
                try {
                  console.log('[PAGE] 🎯 Creating notification...');
                  const notification = new Notification(title, {
                    body: body,
                    icon: '/icons/Icon-192.png',
                    badge: '/icons/Icon-192.png',
                    tag: 'lighthouse-notif',
                    requireInteraction: false,
                    silent: false,
                    renotify: false
                  });

                  notification.onclick = function() {
                    console.log('[PAGE] Notification clicked');
                    window.focus();
                    notification.close();
                  };

                  // Auto close after 10 seconds
                  setTimeout(() => notification.close(), 10000);

                  console.log('[PAGE] ✅ Notification displayed successfully');
                } catch (notifError) {
                  console.error('[PAGE] ❌ Error creating notification:', notifError);
                }
              } else {
                console.error('[PAGE] ❌ Permission not granted:', Notification.permission);
              }
            };

            // Handle foreground messages directly from Firebase onMessage
            console.log('⏳ Setting up Firebase onMessage listener...');
            messaging.onMessage((payload) => {
              console.log('[PAGE] 🔔 Foreground message received via Firebase onMessage!', payload);

              // Extract title and body from data field (data-only messages)
              const title = payload.data?.title || payload.notification?.title || 'Lighthouse';
              const body = payload.data?.body || payload.notification?.body || 'New notification';

              showNotification(title, body);
            });
            console.log('✅ Firebase onMessage listener registered');

            // Also handle messages forwarded from service worker
            console.log('⏳ Setting up service worker postMessage listener...');
            if (!window.fcmMessageHandler) {
              console.log('[PAGE] Creating service worker message handler');
              window.fcmMessageHandler = (event) => {
                console.log('[PAGE] 📨 Service worker message received:', event.data);

                if (event.data && event.data.type === 'FCM_MESSAGE') {
                  console.log('[PAGE] 🔔 Processing FCM message from service worker');

                  const payload = event.data.payload;
                  // Extract title and body from data field (data-only messages)
                  const title = payload.data?.title || payload.notification?.title || 'Lighthouse';
                  const body = payload.data?.body || payload.notification?.body || 'New notification';

                  showNotification(title, body);
                } else {
                  console.log('[PAGE] ⚠️ Not an FCM_MESSAGE, ignoring');
                }
              };

              navigator.serviceWorker.addEventListener('message', window.fcmMessageHandler);
              console.log('✅ Service worker postMessage listener registered');
            } else {
              console.log('⚠️ Service worker message handler already exists');
            }

            // Mark listener as active
            window.fcmListenerActive = true;
            console.log('✅ Foreground message listener set up successfully');
            console.log('');
            console.log('📋 To verify listener is working:');
            console.log('   1. Run: window.testFCMListener()');
            console.log('   2. Send a test notification');
            console.log('   3. Look for "🔔 Foreground message received!"');
            console.log('');
          } catch (error) {
            console.error('❌ Error setting up foreground listener:', error.name, error.message);
            console.error('Stack:', error.stack);
          }
        })()
      ''');
    } catch (e) {
      print('FCMWeb.setupForegroundListener error: $e');
    }
  }

  /// Get FCM token using JavaScript SDK
  static Future<String?> getToken(String vapidKey) async {
    try {
      // Initialize Firebase Messaging in JavaScript
      final result = await _callAsyncJS('''
        (async function() {
          try {
            // Detect browser
            const isOpera = (!!window.opr && !!opr.addons) || !!window.opera || navigator.userAgent.indexOf(' OPR/') >= 0;
            if (isOpera) {
              console.warn('⚠️ Opera browser detected - push notifications may have issues');
              console.warn('Please try: 1) Check opera://settings/content/notifications 2) Disable ad blocker 3) Disable VPN');
            }

            // Wait for service worker to be ready
            const registration = await navigator.serviceWorker.ready;
            console.log('✅ Service worker is ready:', registration.scope);

            // Import Firebase libraries if not already loaded
            if (typeof firebase === 'undefined') {
              console.error('❌ Firebase not loaded');
              return null;
            }

            console.log('✅ Firebase SDK loaded');

            // Get or create messaging instance (reuse global instance if it exists)
            if (!window.fcmMessaging) {
              window.fcmMessaging = firebase.messaging();
              console.log('✅ Created new messaging instance');
            }
            const messaging = window.fcmMessaging;
            console.log('✅ Using messaging instance (same as listener)');

            // Check permission (do NOT request here - iOS requires user gesture)
            console.log('Notification permission:', Notification.permission);

            if (Notification.permission !== 'granted') {
              console.log('❌ Notification permission not granted:', Notification.permission);
              console.log('⚠️ Permission must be granted first via requestBrowserPermission()');
              return null;
            }

            console.log('⏳ Requesting FCM token from Firebase with VAPID key...');

            // Get token with VAPID key and service worker registration
            const token = await messaging.getToken({
              vapidKey: '$vapidKey',
              serviceWorkerRegistration: registration
            });

            if (token) {
              console.log('✅ FCM Token obtained successfully!');
              console.log('📋 Full FCM Token:', token);
              return token;
            } else {
              console.log('❌ No token returned from Firebase');
              return null;
            }
          } catch (error) {
            console.error('❌ Error getting FCM token:', error.name, '-', error.message);
            console.error('Error details:', error);

            // Provide helpful error messages
            if (error.name === 'AbortError' && error.message.includes('push service error')) {
              console.error('🔧 Push service error detected. Possible causes:');
              console.error('   1. Browser blocking push notifications (check settings)');
              console.error('   2. Ad blocker interfering (disable for this site)');
              console.error('   3. VPN/proxy issues (disable temporarily)');
              console.error('   4. Browser not fully supporting Web Push (try Chrome/Edge)');
            }

            return null;
          }
        })()
      ''');

      return result as String?;
    } catch (e) {
      print('FCMWeb.getToken error: $e');
      return null;
    }
  }

  /// Execute async JavaScript and wait for result
  static Future<dynamic> _callAsyncJS(String script) async {
    final completer = Completer<dynamic>();

    try {
      final promise = js.context.callMethod('eval', [script]);

      // Convert JS Promise to Dart Future
      final thenFunc = js.allowInterop((result) {
        completer.complete(result);
      });

      final catchFunc = js.allowInterop((error) {
        completer.completeError(error);
      });

      promise.callMethod('then', [thenFunc]).callMethod('catch', [catchFunc]);
    } catch (e) {
      completer.completeError(e);
    }

    return completer.future;
  }
}
