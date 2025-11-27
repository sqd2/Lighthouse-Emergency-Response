import 'dart:async';
import 'dart:js' as js;

/// Web-specific FCM token handling using JavaScript interop
class FCMWeb {
  /// Get FCM token using JavaScript SDK
  static Future<String?> getToken(String vapidKey) async {
    try {
      // Initialize Firebase Messaging in JavaScript
      final result = await _callAsyncJS('''
        (async function() {
          try {
            // Wait for service worker to be ready
            const registration = await navigator.serviceWorker.ready;
            console.log('Service worker is ready');

            // Import Firebase libraries if not already loaded
            if (typeof firebase === 'undefined') {
              console.error('Firebase not loaded');
              return null;
            }

            // Get messaging instance
            const messaging = firebase.messaging();

            // Request permission
            const permission = await Notification.requestPermission();
            console.log('Notification permission:', permission);

            if (permission !== 'granted') {
              console.log('Notification permission denied');
              return null;
            }

            // Get token
            const token = await messaging.getToken({
              vapidKey: '$vapidKey',
              serviceWorkerRegistration: registration
            });

            console.log('FCM Token obtained:', token ? token.substring(0, 20) + '...' : 'null');
            return token;
          } catch (error) {
            console.error('Error getting FCM token:', error);
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
