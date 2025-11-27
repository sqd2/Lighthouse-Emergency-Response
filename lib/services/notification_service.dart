import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Service to handle Firebase Cloud Messaging notifications
class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  /// Initialize notifications and request permissions
  static Future<void> initialize() async {
    try {
      // Request permission
      NotificationSettings settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      print('Notification permission status: ${settings.authorizationStatus}');

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
        print('User declined notification permission: ${settings.authorizationStatus}');
      }
    } catch (e) {
      print('Error initializing notifications: $e');
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
        // For web, get token with VAPID key
        print('Requesting FCM token for web...');
        token = await _messaging.getToken(
          vapidKey: 'BKv4RxnCncYJ6C4Pu5cgx6bMSw6wjC798s6e02Np9fSTLzaSrC8XTsESJuXNZDHQmR7ob6zYPqXlVmgMKN94eOA',
        );
        print('Web FCM token received: ${token?.substring(0, 20)}...');
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
