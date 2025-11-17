import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:ligthouse/screen/dispatcher_dashboard.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'screen/login_screen.dart';
import 'screen/citizen_dashboard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    debugPrint("Firebase initialization error: $e");
    // Continue anyway - the app will show error in UI
  }

  runApp(const LighthouseApp());
}

class LighthouseApp extends StatelessWidget {
  const LighthouseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Lighthouse',
      theme: ThemeData(primarySwatch: Colors.red),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

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
          return const LoginScreen();
        }

        final user = snapshot.data!;

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
