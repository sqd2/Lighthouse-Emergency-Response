import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Service to handle Firebase Cloud Messaging notifications
class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  /// Initialize notifications and request permissions
  static Future<void> initialize() async {
    // Request permission
    NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('User granted notification permission');

      // Get and save FCM token
      await updateFCMToken();

      // Listen for token refresh
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        print('FCM token refreshed: $newToken');
        _saveFCMToken(newToken);
      });

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        print('Received foreground message: ${message.notification?.title}');
        // Messages will be shown by browser notification API on web
      });
    } else {
      print('User declined notification permission');
    }
  }

  /// Update FCM token for current user
  static Future<void> updateFCMToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      String? token;

      if (kIsWeb) {
        // For web, try to get token
        // VAPID key should be added in Firebase Console: Project Settings > Cloud Messaging > Web Push certificates
        try {
          token = await _messaging.getToken();
        } catch (e) {
          print('Error getting web FCM token (VAPID key may be missing): $e');
          // Continue without token for now
        }
      } else {
        token = await _messaging.getToken();
      }

      if (token != null) {
        await _saveFCMToken(token);
      }
    } catch (e) {
      print('Error updating FCM token: $e');
    }
  }

  /// Save FCM token to Firestore
  static Future<void> _saveFCMToken(String token) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({
        'fcmToken': token,
        'lastTokenUpdate': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print('FCM token saved successfully');
    } catch (e) {
      print('Error saving FCM token: $e');
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
