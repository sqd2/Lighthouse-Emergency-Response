import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:ligthouse/screen/dispatcher_dashboard.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:html' as html show window;

import 'screen/login_screen.dart';
import 'screen/citizen_dashboard.dart';
import 'models/call.dart';
import 'widgets/incoming_call_dialog.dart';
import 'services/livekit_service.dart';
import 'services/two_factor_gate.dart';

// Global navigator key for showing dialogs from anywhere
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Global flag to track if user is currently in a call
bool _isInCall = false;

// Functions to manage call state
void setInCall(bool value) {
  _isInCall = value;
  debugPrint('[CallState] isInCall set to: $value');
}

void main() async {
  // Wrap EVERYTHING in error handling
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    } catch (e) {
      debugPrint("Firebase initialization error: $e");
      // Continue anyway - the app will show error in UI
    }

    // Reset global call state on app launch
    _isInCall = false;
    debugPrint('[App] Initialized - isInCall reset to false');

    runApp(const LighthouseApp());
  }, (error, stack) {
    debugPrint('FATAL ERROR CAUGHT: $error');
    debugPrint('STACK: $stack');
    // Still try to run the app with error UI
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              const Text('Fatal Error', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  error.toString(),
                  style: const TextStyle(fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  // Force reload the page
                  if (kIsWeb) {
                    html.window.location.reload();
                  }
                },
                child: const Text('Reload Page'),
              ),
            ],
          ),
        ),
      ),
    ));
  });
}

class LighthouseApp extends StatefulWidget {
  const LighthouseApp({super.key});

  @override
  State<LighthouseApp> createState() => _LighthouseAppState();
}

class _LighthouseAppState extends State<LighthouseApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint('[App] Lifecycle state changed: $state');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Lighthouse',
      theme: ThemeData(
        primarySwatch: Colors.red,
        useMaterial3: false,
      ),
      home: const AuthGate(),
      builder: (context, widget) {
        // Error boundary - catch any rendering errors
        ErrorWidget.builder = (FlutterErrorDetails details) {
          debugPrint('ERROR CAUGHT: ${details.exception}');
          debugPrint('STACK: ${details.stack}');
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text('An error occurred'),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      details.exception.toString(),
                      style: const TextStyle(fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      // Force reload the page
                      if (kIsWeb) {
                        html.window.location.reload();
                      }
                    },
                    child: const Text('Reload Page'),
                  ),
                ],
              ),
            ),
          );
        };
        return widget ?? const SizedBox();
      },
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<QuerySnapshot>? _callListener;
  String? _currentUserId;

  @override
  void dispose() {
    _callListener?.cancel();
    super.dispose();
  }

  Future<String?> _getUserRole(User user) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        return doc.data()?['role'] as String?;
      }
    } catch (e) {
      debugPrint("Error fetching role: $e");
    }
    return null;
  }

  /// Set up global listener for incoming calls
  void _setupGlobalCallListener(String userId) {
    try {
      // Cancel existing listener if any
      _callListener?.cancel();

      _currentUserId = userId;

      debugPrint('[GlobalCallListener] Setting up for user: $userId');

      // Listen to all incoming calls for this user
      _callListener = FirebaseFirestore.instance
          .collectionGroup('calls')
          .where('receiverId', isEqualTo: userId)
          .where('status', isEqualTo: Call.STATUS_RINGING)
          .snapshots()
          .listen((snapshot) {
      debugPrint('[GlobalCallListener] Received snapshot with ${snapshot.docChanges.length} changes');

      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          debugPrint('[GlobalCallListener] New incoming call detected: ${change.doc.id}');

          // Don't show incoming call if already in a call
          if (_isInCall) {
            debugPrint('[GlobalCallListener] Already in a call, ignoring incoming call');
            continue;
          }

          final call = Call.fromFirestore(change.doc);

          // Extract alertId from the document path
          // Path format: emergency_alerts/{alertId}/calls/{callId}
          final pathSegments = change.doc.reference.path.split('/');
          debugPrint('[GlobalCallListener] Path: ${change.doc.reference.path}');
          debugPrint('[GlobalCallListener] Path segments: $pathSegments');

          if (pathSegments.length >= 4) {
            final alertId = pathSegments[1]; // Index 1 should be the alertId
            debugPrint('[GlobalCallListener] Showing dialog for alertId: $alertId, callId: ${call.id}');

            // Use Future.delayed to ensure we're not in a build cycle
            Future.delayed(Duration.zero, () {
              final context = navigatorKey.currentContext;
              if (context != null && !_isInCall) {
                debugPrint('[GlobalCallListener] Context available, showing dialog');
                showIncomingCallDialog(context, alertId, call);
              } else {
                debugPrint('[GlobalCallListener] ERROR: No context available or already in call!');
              }
            });
          } else {
            debugPrint('[GlobalCallListener] ERROR: Invalid path format');
          }
        }
      }
    }, onError: (error) {
      debugPrint('[GlobalCallListener] ERROR: $error');
    });
    } catch (e) {
      debugPrint('[GlobalCallListener] Fatal error setting up listener: $e');
      // Don't crash the app, just log the error
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // ⏳ waiting for auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Not logged in
        if (!snapshot.hasData) {
          // Cancel listener when logged out
          _callListener?.cancel();
          _currentUserId = null;
          TwoFactorGate.reset(); // Clear 2FA verification state
          return const LoginScreen();
        }

        final user = snapshot.data!;

        // Check if 2FA verification is pending - block navigation until complete
        if (TwoFactorGate.isVerifying) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Verifying two-factor authentication...'),
                ],
              ),
            ),
          );
        }

        // TEMPORARILY DISABLED - Global call listener causing PWA crashes
        // TODO: Re-enable with better error handling
        // if (_currentUserId != user.uid) {
        //   Future.delayed(const Duration(milliseconds: 500), () {
        //     if (mounted) {
        //       _setupGlobalCallListener(user.uid);
        //     }
        //   });
        // }

        // Logged in, fetch firestore data
        return FutureBuilder<String?>(
          future: _getUserRole(user),
          builder: (context, roleSnap) {
            if (roleSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final role = roleSnap.data ?? 'citizen';

            if (role == 'dispatcher') {
              return const DispatcherDashboard();
            } else {
              return const CitizenDashboard();
            }
          },
        );
      },
    );
  }
}
