import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../models/emergency_alert.dart';

/// Emergency alert bottom sheet for dispatchers
class EmergencyAlertSheet extends StatefulWidget {
  final EmergencyAlert alert;
  final Position? userLocation;
  final VoidCallback onNavigate;

  const EmergencyAlertSheet({
    super.key,
    required this.alert,
    required this.userLocation,
    required this.onNavigate,
  });

  @override
  State<EmergencyAlertSheet> createState() => _EmergencyAlertSheetState();
}

class _EmergencyAlertSheetState extends State<EmergencyAlertSheet> {
  bool _resolving = false;
  bool _accepting = false;
  StreamSubscription<Position>? _locationUpdateSubscription;
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    // Update elapsed time every minute
    _updateTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _locationUpdateSubscription?.cancel();
    _updateTimer?.cancel();
    super.dispose();
  }

  Future<void> _acceptAlert() async {
    print('===== ACCEPTING ALERT =====');
    setState(() => _accepting = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('Not authenticated');
      }

      print('User: ${user.email} (${user.uid})');
      print('Alert ID: ${widget.alert.id}');

      // Update alert to mark as accepted
      await FirebaseFirestore.instance
          .collection('emergency_alerts')
          .doc(widget.alert.id)
          .update({
        'acceptedBy': user.uid,
        'acceptedByEmail': user.email ?? 'Unknown',
        'acceptedAt': FieldValue.serverTimestamp(),
      });

      print('Alert marked as accepted in Firestore');

      // Start updating dispatcher location in real-time
      _startLocationUpdates();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Alert accepted! Your location is being shared.'),
          backgroundColor: Colors.green,
        ),
      );

      // Auto-navigate to the alert
      widget.onNavigate();
    } catch (e) {
      print('Error accepting alert: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to accept alert: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _accepting = false);
      }
    }
  }

  Future<void> _startLocationUpdates() async {
    print('===== STARTING DISPATCHER LOCATION UPDATES =====');
    print('Alert ID: ${widget.alert.id}');

    try {
      // First, get current position to trigger permission request and get initial location
      print('Getting initial dispatcher location...');
      final currentPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      print('Initial dispatcher location: ${currentPosition.latitude}, ${currentPosition.longitude}');

      // Send initial location to Firestore
      await FirebaseFirestore.instance
          .collection('emergency_alerts')
          .doc(widget.alert.id)
          .update({
        'dispatcherLocation': GeoPoint(currentPosition.latitude, currentPosition.longitude),
        'dispatcherLocationUpdatedAt': FieldValue.serverTimestamp(),
      });

      print('Initial dispatcher location sent to Firestore');

      // Then start streaming location updates
      _locationUpdateSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5, // Update every 5 meters
        ),
      ).listen((Position position) {
        print('Dispatcher location update: ${position.latitude}, ${position.longitude}');

        // Update dispatcher location in Firestore
        FirebaseFirestore.instance
            .collection('emergency_alerts')
            .doc(widget.alert.id)
            .update({
          'dispatcherLocation': GeoPoint(position.latitude, position.longitude),
          'dispatcherLocationUpdatedAt': FieldValue.serverTimestamp(),
        }).then((_) {
          print('Dispatcher location updated in Firestore successfully');
        }).catchError((error) {
          print('Error updating dispatcher location: $error');
        });
      }, onError: (error) {
        print('Error in location stream: $error');
      });
    } catch (e) {
      print('Error getting initial location: $e');
    }
  }

  Future<void> _resolveAlert() async {
    setState(() => _resolving = true);

    try {
      // Stop location updates
      _locationUpdateSubscription?.cancel();

      await FirebaseFirestore.instance
          .collection('emergency_alerts')
          .doc(widget.alert.id)
          .update({'status': 'resolved'});

      if (!mounted) return;

      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Alert marked as resolved'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to resolve alert: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _resolving = false);
      }
    }
  }

  String _formatTimestamp(DateTime? timestamp) {
    if (timestamp == null) return 'Unknown';
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hours ago';
    return '${diff.inDays} days ago';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('emergency_alerts')
          .doc(widget.alert.id)
          .snapshots(),
      builder: (context, snapshot) {
        final alertData = snapshot.data?.data() as Map<String, dynamic>?;
        final isAccepted = alertData?['acceptedBy'] != null;
        final acceptedByEmail = alertData?['acceptedByEmail'] as String?;
        final currentUser = FirebaseAuth.instance.currentUser;
        final acceptedByMe = isAccepted && alertData?['acceptedBy'] == currentUser?.uid;

        return SafeArea(
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Accepted status banner
                  if (isAccepted)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: acceptedByMe ? Colors.blue.shade50 : Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: acceptedByMe ? Colors.blue : Colors.orange,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            acceptedByMe ? Icons.check_circle : Icons.info,
                            color: acceptedByMe ? Colors.blue : Colors.orange,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              acceptedByMe
                                  ? 'You accepted this alert'
                                  : 'Accepted by $acceptedByEmail',
                              style: TextStyle(
                                color: acceptedByMe ? Colors.blue.shade900 : Colors.orange.shade900,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade100,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.emergency, color: Colors.red, size: 28),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Emergency Alert',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              _formatTimestamp(widget.alert.createdAt),
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 16),

                  // User info
                  _InfoRow(
                    icon: Icons.person,
                    label: 'Reported by',
                    value: widget.alert.userEmail,
                  ),
                  const SizedBox(height: 12),

                  // Location
                  _InfoRow(
                    icon: Icons.location_on,
                    label: 'Location',
                    value: '${widget.alert.lat.toStringAsFixed(6)}, ${widget.alert.lon.toStringAsFixed(6)}',
                  ),
                  const SizedBox(height: 12),

                  // Services needed
                  const Row(
                    children: [
                      Icon(Icons.local_hospital, size: 20, color: Colors.red),
                      SizedBox(width: 8),
                      Text(
                        'Services Needed',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: widget.alert.services.map((service) {
                      return Chip(
                        label: Text(service),
                        backgroundColor: Colors.red.shade50,
                        labelStyle: const TextStyle(fontSize: 12),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 16),

                  // Description
                  const Row(
                    children: [
                      Icon(Icons.description, size: 20, color: Colors.grey),
                      SizedBox(width: 8),
                      Text(
                        'Description',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      widget.alert.description,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Navigate button
                  if (widget.userLocation != null)
                    Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: widget.onNavigate,
                            icon: const Icon(Icons.directions, color: Colors.white),
                            label: const Text(
                              'Navigate to Location',
                              style: TextStyle(color: Colors.white),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),

                  // Action buttons
                  if (!isAccepted)
                    // Show Accept button if not accepted
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _accepting ? null : _acceptAlert,
                        icon: _accepting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check_circle, color: Colors.white),
                        label: Text(
                          _accepting ? 'Accepting...' : 'Accept & Navigate',
                          style: const TextStyle(color: Colors.white, fontSize: 16),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    )
                  else
                    // Show Close and Resolve buttons if accepted
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Close'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        if (acceptedByMe)
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _resolving ? null : _resolveAlert,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                              ),
                              child: _resolving
                                  ? const SizedBox(
                                      height: 16,
                                      width: 16,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text(
                                      'Mark Resolved',
                                      style: TextStyle(color: Colors.white),
                                    ),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Helper widget for displaying info rows
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.grey),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
