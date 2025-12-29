import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:html' as html show window;
import 'edit_profile_screen.dart';
import 'medical_info_form_screen.dart';
import 'two_factor_settings_screen.dart';
import '../services/medical_info_service.dart';
import '../services/livekit_service.dart';

/// Settings page for citizen users
class CitizenSettingsScreen extends StatefulWidget {
  final bool debugMode;
  final Future<void> Function(bool) onDebugModeToggle;

  const CitizenSettingsScreen({
    Key? key,
    required this.debugMode,
    required this.onDebugModeToggle,
  }) : super(key: key);

  @override
  State<CitizenSettingsScreen> createState() => _CitizenSettingsScreenState();
}

class _CitizenSettingsScreenState extends State<CitizenSettingsScreen> {
  final user = FirebaseAuth.instance.currentUser;
  bool _isTogglingDebugMode = false;

  Future<void> _handleDebugModeToggle(bool value) async {
    if (_isTogglingDebugMode) return;

    setState(() {
      _isTogglingDebugMode = true;
    });

    try {
      await widget.onDebugModeToggle(value);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update debug mode: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTogglingDebugMode = false;
        });
      }
    }
  }

  Future<void> _logout(BuildContext context) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      debugPrint('[Logout] Starting cleanup...');

      // Clean up LiveKit service
      try {
        final liveKitService = LiveKitService();
        liveKitService.dispose();
        debugPrint('[Logout] LiveKit service disposed');
      } catch (e) {
        debugPrint('[Logout] Error disposing LiveKit service: $e');
      }

      // Sign out from Firebase
      await FirebaseAuth.instance.signOut();
      debugPrint('[Logout] Firebase signed out');

      if (!context.mounted) return;

      // Force page reload for PWA to clear all state
      if (kIsWeb) {
        debugPrint('[Logout] Reloading page to clear state...');
        html.window.location.reload();
      } else {
        Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
      }
    } catch (e) {
      debugPrint('[Logout] Error during logout: $e');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Logout failed: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Profile Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(user?.uid)
                    .snapshots(),
                builder: (context, snapshot) {
                  String displayName = 'Citizen';
                  if (snapshot.hasData && snapshot.data!.exists) {
                    final data = snapshot.data!.data() as Map<String, dynamic>?;
                    displayName = data?['name']?.toString() ?? 'Citizen';
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 30,
                            backgroundColor: Colors.red,
                            child: Text(
                              displayName.isNotEmpty ? displayName[0].toUpperCase() : 'C',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  displayName,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  user?.email ?? '',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.red[50],
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'Citizen',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.red,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const EditProfileScreen(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.edit),
                          label: const Text('Edit Profile'),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Medical Information Section
          Card(
            child: ListTile(
              leading: const Icon(Icons.medical_information, color: Colors.red),
              title: const Text(
                'Medical Information',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: const Text('Manage your health information'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                try {
                  // Load existing medical info
                  final existingInfo = await MedicalInfoService.getMedicalInfo();

                  if (!context.mounted) return;

                  // Navigate to form screen
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MedicalInfoFormScreen(
                        existingInfo: existingInfo,
                      ),
                    ),
                  );
                } catch (e) {
                  if (!context.mounted) return;

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error loading medical info: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
            ),
          ),

          const SizedBox(height: 16),

          // Two-Factor Authentication Section
          Card(
            child: ListTile(
              leading: const Icon(Icons.security, color: Colors.blue),
              title: const Text(
                'Two-Factor Authentication',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: const Text('Secure your account with 2FA'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const TwoFactorSettingsScreen(),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 16),

          // Debug Mode Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Debug Mode',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: widget.debugMode ? Colors.orange[50] : Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          widget.debugMode ? Icons.bug_report : Icons.bug_report_outlined,
                          color: widget.debugMode ? Colors.orange : Colors.grey,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.debugMode ? 'Enabled' : 'Disabled',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: widget.debugMode ? Colors.orange[800] : Colors.grey[800],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.debugMode
                                    ? 'Shows pins, alerts, debug info, and logs'
                                    : 'Hides pins, alerts, debug info, and logs',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                        _isTogglingDebugMode
                            ? const SizedBox(
                                width: 48,
                                height: 48,
                                child: Center(
                                  child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                ),
                              )
                            : Switch(
                                value: widget.debugMode,
                                onChanged: _handleDebugModeToggle,
                                activeColor: Colors.orange,
                              ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Logout Section
          Card(
            child: ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text(
                'Logout',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onTap: () => _logout(context),
            ),
          ),
        ],
      ),
    );
  }
}
