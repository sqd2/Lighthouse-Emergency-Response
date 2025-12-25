import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../models/emergency_alert.dart';
import 'medical_info_display.dart';
import 'chat_screen.dart';

/// Emergency alert bottom sheet for dispatchers
class EmergencyAlertSheet extends StatefulWidget {
  final EmergencyAlert alert;
  final Position? userLocation;
  final VoidCallback onNavigate;
  final Future<void> Function(String alertId)? onAccepted;

  const EmergencyAlertSheet({
    super.key,
    required this.alert,
    required this.userLocation,
    required this.onNavigate,
    this.onAccepted,
  });

  @override
  State<EmergencyAlertSheet> createState() => _EmergencyAlertSheetState();
}

class _EmergencyAlertSheetState extends State<EmergencyAlertSheet> {
  bool _resolving = false;
  bool _accepting = false;
  bool _markingArrived = false;
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

  /// Make phone call
  void _makePhoneCall(String phoneNumber) async {
    final Uri phoneUri = Uri(scheme: 'tel', path: phoneNumber);
    // In Flutter Web, this will open the phone dialer on mobile browsers
    // or show a browser prompt on desktop
    try {
      // Note: url_launcher package would be needed for actual implementation
      // For now, we show the phone number and allow user to copy it
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Call Citizen'),
            content: SelectableText(
              phoneNumber,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      print('Error making phone call: $e');
    }
  }

  /// Calculate distance between dispatcher and alert location
  String _calculateDistance() {
    if (widget.userLocation == null) {
      return 'Location unavailable';
    }

    final distance = Geolocator.distanceBetween(
      widget.userLocation!.latitude,
      widget.userLocation!.longitude,
      widget.alert.lat,
      widget.alert.lon,
    );

    // Convert to kilometers or meters
    if (distance < 1000) {
      return '${distance.toStringAsFixed(0)} m away';
    } else {
      return '${(distance / 1000).toStringAsFixed(1)} km away';
    }
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

      // PREVENT MULTIPLE ACTIVE ALERTS
      // Check if dispatcher already has an active alert
      print('[CHECK] Checking for existing active alerts...');
      final activeAlertsSnapshot = await FirebaseFirestore.instance
          .collection('emergency_alerts')
          .where('acceptedBy', isEqualTo: user.uid)
          .where('status', whereIn: [
            EmergencyAlert.STATUS_ACTIVE,
            EmergencyAlert.STATUS_ARRIVED,
          ])
          .limit(1)
          .get();

      if (activeAlertsSnapshot.docs.isNotEmpty) {
        print('[BLOCKED] Dispatcher already has an active alert');
        if (!mounted) return;

        setState(() => _accepting = false);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'You already have an active alert. Please resolve it before accepting a new one.',
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }

      print('[OK] No active alerts found. Proceeding with acceptance...');

      // Update alert to mark as accepted
      await FirebaseFirestore.instance
          .collection('emergency_alerts')
          .doc(widget.alert.id)
          .update({
        'status': EmergencyAlert.STATUS_ACTIVE,
        'acceptedBy': user.uid,
        'acceptedByEmail': user.email ?? 'Unknown',
        'acceptedAt': FieldValue.serverTimestamp(),
      });

      print('Alert marked as accepted in Firestore');

      // Start location sharing via dashboard (persists after sheet closes)
      if (widget.onAccepted != null) {
        print('🔄 Calling dashboard location sharing...');
        await widget.onAccepted!(widget.alert.id);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Alert accepted! Your location is being shared.'),
          backgroundColor: Colors.green,
        ),
      );

      // Auto-navigate to the alert (sheet can close, location tracking persists in dashboard)
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
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('🚀 STARTING DISPATCHER LOCATION UPDATES');
    print('   Alert ID: ${widget.alert.id}');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    try {
      // First, get current position to trigger permission request and get initial location
      print('⏳ Getting initial dispatcher location...');
      final currentPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      print('✅ Initial dispatcher location: ${currentPosition.latitude}, ${currentPosition.longitude}');

      // Send initial location to Firestore
      print('⏳ Sending initial location to emergency_alerts/${widget.alert.id}/dispatcherLocation...');
      await FirebaseFirestore.instance
          .collection('emergency_alerts')
          .doc(widget.alert.id)
          .update({
        'dispatcherLocation': GeoPoint(currentPosition.latitude, currentPosition.longitude),
        'dispatcherLocationUpdatedAt': FieldValue.serverTimestamp(),
      });

      print('✅ Initial dispatcher location written to Firestore!');
      print('   Path: emergency_alerts/${widget.alert.id}');
      print('   Field: dispatcherLocation = GeoPoint(${currentPosition.latitude}, ${currentPosition.longitude})');

      // Then start streaming location updates
      print('⏳ Starting location stream (updates every 5 meters)...');
      _locationUpdateSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5, // Update every 5 meters
        ),
      ).listen((Position position) {
        print('📍 Dispatcher moved! New position: ${position.latitude}, ${position.longitude}');

        // Update dispatcher location in Firestore
        FirebaseFirestore.instance
            .collection('emergency_alerts')
            .doc(widget.alert.id)
            .update({
          'dispatcherLocation': GeoPoint(position.latitude, position.longitude),
          'dispatcherLocationUpdatedAt': FieldValue.serverTimestamp(),
        }).then((_) {
          print('✅ Location updated in Firestore: ${position.latitude}, ${position.longitude}');
        }).catchError((error) {
          print('❌ ERROR updating dispatcher location: $error');
        });
      }, onError: (error) {
        print('❌ ERROR in location stream: $error');
      });

      print('✅ Location stream started successfully!');
    } catch (e) {
      print('❌ ERROR getting initial location: $e');
      print('   Stack trace: ${StackTrace.current}');
    }
  }

  Future<void> _markArrived() async {
    print('[MARK ARRIVED] Button clicked!');
    print('[MARK ARRIVED] Alert ID: ${widget.alert.id}');
    print('[MARK ARRIVED] Current status: ${widget.alert.status}');

    setState(() => _markingArrived = true);

    try {
      print('[MARK ARRIVED] Updating Firestore...');
      await FirebaseFirestore.instance
          .collection('emergency_alerts')
          .doc(widget.alert.id)
          .update({
        'status': EmergencyAlert.STATUS_ARRIVED,
        'arrivedAt': FieldValue.serverTimestamp(),
      });

      print('[MARK ARRIVED] ✅ Firestore update successful!');

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Marked as arrived at scene'),
          backgroundColor: Colors.blue,
        ),
      );
    } catch (e) {
      print('[MARK ARRIVED] ❌ Error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to mark arrival: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _markingArrived = false);
      }
    }
  }

  Future<void> _resolveAlert() async {
    // Show confirmation dialog with optional notes
    final TextEditingController notesController = TextEditingController();
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Mark as Resolved?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Are you sure you want to mark this alert as resolved?'),
              const SizedBox(height: 16),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(
                  labelText: 'Resolution notes (optional)',
                  hintText: 'e.g., Patient transported to hospital',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );

    // If user cancelled, don't proceed
    if (confirmed != true) {
      notesController.dispose();
      return;
    }

    final notes = notesController.text.trim();
    notesController.dispose();

    setState(() => _resolving = true);

    try {
      // Stop location updates
      _locationUpdateSubscription?.cancel();

      final updateData = {
        'status': EmergencyAlert.STATUS_RESOLVED,
        'resolvedAt': FieldValue.serverTimestamp(),
      };

      // Add notes if provided
      if (notes.isNotEmpty) {
        updateData['resolutionNotes'] = notes;
      }

      await FirebaseFirestore.instance
          .collection('emergency_alerts')
          .doc(widget.alert.id)
          .update(updateData);

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

                  // User info - fetch from Firestore
                  StreamBuilder<DocumentSnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .doc(widget.alert.userId)
                        .snapshots(),
                    builder: (context, userSnapshot) {
                      String displayName = widget.alert.userEmail;
                      String? phoneNumber;

                      if (userSnapshot.hasData && userSnapshot.data!.exists) {
                        final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
                        displayName = userData?['name'] ?? widget.alert.userEmail;
                        phoneNumber = userData?['phone'];
                      }

                      return Column(
                        children: [
                          _InfoRow(
                            icon: Icons.person,
                            label: 'Citizen',
                            value: displayName,
                          ),
                          if (phoneNumber != null && phoneNumber.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            _InfoRow(
                              icon: Icons.phone,
                              label: 'Phone',
                              value: phoneNumber!,
                              isClickable: true,
                              onTap: () => _makePhoneCall(phoneNumber!),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),

                  // Location
                  _InfoRow(
                    icon: Icons.location_on,
                    label: 'Location',
                    value: '${widget.alert.lat.toStringAsFixed(6)}, ${widget.alert.lon.toStringAsFixed(6)}',
                  ),
                  const SizedBox(height: 12),

                  // Distance
                  _InfoRow(
                    icon: Icons.social_distance,
                    label: 'Distance',
                    value: _calculateDistance(),
                    valueColor: Colors.blue,
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

                  const SizedBox(height: 16),

                  // Medical Information
                  MedicalInfoDisplay(
                    encryptedMedicalData: alertData?['medicalInfo'] as Map<String, dynamic>?,
                  ),

                  const SizedBox(height: 16),

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

                  // Chat button (shown when accepted by this dispatcher)
                  if (acceptedByMe)
                    Column(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChatScreen(
                                    alertId: widget.alert.id,
                                    userRole: 'dispatcher',
                                    otherPartyEmail: widget.alert.userEmail,
                                    otherPartyUserId: widget.alert.userId,
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.chat_bubble_outline),
                            label: const Text('Chat with Citizen'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.blue,
                              side: const BorderSide(color: Colors.blue),
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
                    // Show Close, Mark Arrived, and Resolve buttons if accepted
                    Column(
                      children: [
                        // If status is 'active' and accepted by me, show Mark Arrived button
                        if (acceptedByMe && widget.alert.status == EmergencyAlert.STATUS_ACTIVE)
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _markingArrived ? null : _markArrived,
                              icon: _markingArrived
                                  ? const SizedBox(
                                      height: 16,
                                      width: 16,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.location_on, color: Colors.white),
                              label: Text(
                                _markingArrived ? 'Marking...' : 'Mark as Arrived',
                                style: const TextStyle(color: Colors.white, fontSize: 16),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                            ),
                          ),
                        if (acceptedByMe && widget.alert.status == EmergencyAlert.STATUS_ACTIVE)
                          const SizedBox(height: 12),
                        // Row with Close and Resolve buttons
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Close'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Only show Resolve button if arrived or if status allows
                            if (acceptedByMe && (widget.alert.status == EmergencyAlert.STATUS_ARRIVED || widget.alert.status == EmergencyAlert.STATUS_ACTIVE))
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
  final Color? valueColor;
  final bool isClickable;
  final VoidCallback? onTap;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.isClickable = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: isClickable ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: isClickable ? Colors.blue : Colors.grey),
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          value,
                          style: TextStyle(
                            fontSize: 14,
                            color: isClickable ? Colors.blue : valueColor,
                            fontWeight: FontWeight.w500,
                            decoration: isClickable ? TextDecoration.underline : null,
                          ),
                        ),
                      ),
                      if (isClickable)
                        const Icon(Icons.call, size: 16, color: Colors.blue),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
