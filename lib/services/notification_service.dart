import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'fcm_web.dart' if (dart.library.io) 'fcm_web_stub.dart';

/// Service to handle Firebase Cloud Messaging notifications
class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  static bool _isInitialized = false;
  static bool _listenerSetup = false;
  static bool _tokenSaveInProgress = false;
  static String? _lastSavedToken;

  /// Initialize notifications and request permissions
  static Future<void> initialize() async {
    if (_isInitialized) {
      print('[WARN] Notification Service already initialized, skipping...');
      return;
    }

    try {
      print('=== Initializing Notification Service ===');
      print('Platform: ${kIsWeb ? "Web" : "Mobile"}');
      _isInitialized = true;

      if (kIsWeb) {
        // On web, check browser permission directly via JS (don't request)
        print('Checking web notification permission via browser API...');
        final permission = await FCMWeb.checkBrowserPermission();
        print('Browser permission: $permission');

        if (permission == 'granted') {
          print('User already granted notification permission');
          print('Setting up notifications and refreshing token...');
          await _setupNotifications();
        } else {
          print('Notification permission not granted - user needs to tap Enable button');
        }
      } else {
        // On mobile, use Firebase Messaging API
        NotificationSettings settings = await _messaging.getNotificationSettings();
        print('Current notification permission: ${settings.authorizationStatus}');

        if (settings.authorizationStatus == AuthorizationStatus.authorized) {
          print('User already granted notification permission');
          await _setupNotifications();
        } else if (settings.authorizationStatus == AuthorizationStatus.notDetermined) {
          print('Notification permission not determined');
          await requestPermission();
        } else {
          print('Notification permission denied: ${settings.authorizationStatus}');
        }
      }
    } catch (e) {
      print('Error initializing notifications: $e');
    }
  }

  /// Request notification permission (call from button tap)
  static Future<bool> requestPermission() async {
    try {
      print('Requesting notification permission...');
      print('Platform: ${kIsWeb ? "Web" : "Mobile"}');

      if (kIsWeb) {
        // On web, request browser permission first
        print('Requesting browser notification permission via JS...');
        final browserPermission = await FCMWeb.requestBrowserPermission();
        print('Browser permission result: $browserPermission');

        if (browserPermission == 'granted') {
          print(' Browser permission granted, setting up FCM...');
          await _setupNotifications();
          return true;
        } else {
          print('[ERROR] Browser permission not granted: $browserPermission');
          return false;
        }
      } else {
        // On mobile, use Firebase Messaging API
        NotificationSettings settings = await _messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        );

        print('Notification permission status: ${settings.authorizationStatus}');

        if (settings.authorizationStatus == AuthorizationStatus.authorized) {
          print('User granted notification permission');
          await _setupNotifications();
          return true;
        } else {
          print('User declined notification permission: ${settings.authorizationStatus}');
          return false;
        }
      }
    } catch (e) {
      print('Error requesting notification permission: $e');
      print('Error stack trace: ${StackTrace.current}');
      return false;
    }
  }

  /// Setup notifications after permission granted
  static Future<void> _setupNotifications() async {
    try {
      // Set up foreground listener for web (only once)
      if (kIsWeb && !_listenerSetup) {
        print('Setting up foreground listener for the first time...');
        await FCMWeb.setupForegroundListener();
        _listenerSetup = true;
      } else if (kIsWeb && _listenerSetup) {
        print('[WARN] Foreground listener already set up, skipping...');
      }

      // Get and save FCM token
      await updateFCMToken();

      // Listen for token refresh
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        print('FCM token refreshed: $newToken');
        _saveFCMToken(newToken);
      });

      // Handle foreground messages (only for mobile, web uses JS SDK)
      if (!kIsWeb) {
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          print('Received foreground message: ${message.notification?.title}');
        });
      }
    } catch (e) {
      print('Error setting up notifications: $e');
    }
  }

  /// Check if notifications are enabled
  static Future<bool> areNotificationsEnabled() async {
    try {
      if (kIsWeb) {
        // On web, check browser permission directly (don't request)
        final permission = await FCMWeb.checkBrowserPermission();
        return permission == 'granted';
      } else {
        // On mobile, use Firebase Messaging API
        NotificationSettings settings = await _messaging.getNotificationSettings();
        return settings.authorizationStatus == AuthorizationStatus.authorized;
      }
    } catch (e) {
      print('Error checking notification status: $e');
      return false;
    }
  }

  /// Update FCM token for current user
  static Future<void> updateFCMToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print('No user logged in, skipping FCM token');
        return;
      }

      String? token;

      if (kIsWeb) {
        // For web, use JavaScript interop to get token
        print('Requesting FCM token for web using JavaScript SDK...');
        token = await FCMWeb.getToken(
          'BKv4RxnCncYJ6C4Pu5cgx6bMSw6wjC798s6e02Np9fSTLzaSrC8XTsESJuXNZDHQmR7ob6zYPqXlVmgMKN94eOA',
        );
        if (token != null) {
          print(' FCM Token obtained successfully!');
          print(' Full FCM Token (for Firebase test device): $token');
        } else {
          print('[ERROR] Failed to obtain FCM token');
        }
      } else {
        print('Requesting FCM token for mobile...');
        token = await _messaging.getToken();
        print('Mobile FCM token received');
      }

      if (token != null) {
        await _saveFCMToken(token);
      } else {
        print('No FCM token received');
      }
    } catch (e) {
      print('Error updating FCM token: $e');
    }
  }

  /// Save FCM token to Firestore
  static Future<void> _saveFCMToken(String token) async {
    // Prevent duplicate saves of the same token
    if (_tokenSaveInProgress) {
      print('[WARN] Token save already in progress, skipping duplicate...');
      return;
    }

    if (_lastSavedToken == token) {
      print('[WARN] Token already saved recently, skipping duplicate...');
      return;
    }

    _tokenSaveInProgress = true;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _tokenSaveInProgress = false;
        return;
      }

      // Create token object with metadata
      // Note: Can't use FieldValue.serverTimestamp() inside arrays
      final tokenData = {
        'token': token,
        'platform': kIsWeb ? 'web' : 'mobile',
        'lastUpdated': DateTime.now().millisecondsSinceEpoch,
      };

      final userDoc = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);

      // Get current tokens
      final snapshot = await userDoc.get();
      final data = snapshot.data();
      List<dynamic> currentTokens = data?['fcmTokens'] ?? [];

      // Remove any existing entries with the same token (to avoid duplicates)
      currentTokens.removeWhere((t) => t['token'] == token);

      // Add new token
      currentTokens.add(tokenData);

      // Save updated tokens array
      await userDoc.set({
        'fcmTokens': currentTokens,
        'lastTokenUpdate': FieldValue.serverTimestamp(),
        // Keep old fcmToken field for backward compatibility
        'fcmToken': token,
      }, SetOptions(merge: true));

      _lastSavedToken = token;

      print(' FCM token saved to array (${currentTokens.length} total devices)');
      print('   Token: ${token.substring(0, 20)}...');
      print('   Platform: ${kIsWeb ? "web" : "mobile"}');
    } catch (e) {
      print('Error saving FCM token: $e');
    } finally {
      _tokenSaveInProgress = false;
    }
  }

  /// Remove FCM token when user logs out
  static Future<void> removeFCMToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'fcmToken': FieldValue.delete(),
      });

      print('FCM token removed');
    } catch (e) {
      print('Error removing FCM token: $e');
    }
  }
}
