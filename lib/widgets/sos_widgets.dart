import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../places_service.dart';

/// SOS submission sheet for citizens
class SOSSheet extends StatefulWidget {
  final Position? userLocation;

  const SOSSheet({super.key, required this.userLocation});

  @override
  State<SOSSheet> createState() => _SOSSheetState();
}

class _SOSSheetState extends State<SOSSheet> {
  final _descriptionController = TextEditingController();
  final _selectedServices = <String>{};
  bool _submitting = false;

  final _emergencyServices = [
    'Hospital',
    'Police Station',
    'Fire Station',
    'Ambulance',
  ];

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submitSOS() async {
    // Validate
    if (_selectedServices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one emergency service'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_descriptionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please describe the emergency'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (widget.userLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to get your location. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // Create emergency alert in Firestore
      await FirebaseFirestore.instance.collection('emergency_alerts').add({
        'userId': user.uid,
        'userEmail': user.email ?? 'Unknown',
        'location': GeoPoint(
          widget.userLocation!.latitude,
          widget.userLocation!.longitude,
        ),
        'services': _selectedServices.toList(),
        'description': _descriptionController.text.trim(),
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;

      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SOS alert sent! Help is on the way.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send SOS: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade100,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.sos, color: Colors.red, size: 28),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Emergency SOS',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Services selection
                  const Text(
                    'Select Emergency Services *',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),

                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Service chips
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _emergencyServices.map((service) {
                              final isSelected = _selectedServices.contains(
                                service,
                              );
                              return FilterChip(
                                label: Text(service),
                                selected: isSelected,
                                onSelected: (selected) {
                                  setState(() {
                                    if (selected) {
                                      _selectedServices.add(service);
                                    } else {
                                      _selectedServices.remove(service);
                                    }
                                  });
                                },
                                selectedColor: Colors.red.shade100,
                                checkmarkColor: Colors.red,
                              );
                            }).toList(),
                          ),

                          const SizedBox(height: 24),

                          // Description
                          const Text(
                            'Describe the Emergency *',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),

                          TextField(
                            controller: _descriptionController,
                            maxLines: 4,
                            decoration: InputDecoration(
                              hintText:
                                  'e.g., Car accident, medical emergency, fire...',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade100,
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Submit button
                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: ElevatedButton(
                              onPressed: _submitting ? null : _submitSOS,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: _submitting
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text(
                                      'Send SOS Alert',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
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

/// Active SOS banner shown on citizen dashboard
class ActiveSOSBanner extends StatefulWidget {
  final String alertId;
  final Map<String, dynamic> alertData;

  const ActiveSOSBanner({
    super.key,
    required this.alertId,
    required this.alertData,
  });

  @override
  State<ActiveSOSBanner> createState() => _ActiveSOSBannerState();
}

class _ActiveSOSBannerState extends State<ActiveSOSBanner> {
  bool _cancelling = false;
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
    _updateTimer?.cancel();
    super.dispose();
  }

  Future<void> _cancelAlert() async {
    setState(() => _cancelling = true);

    try {
      await FirebaseFirestore.instance
          .collection('emergency_alerts')
          .doc(widget.alertId)
          .update({'status': 'cancelled'});

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SOS alert cancelled'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to cancel alert: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _cancelling = false);
      }
    }
  }

  void _showUpdateDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => UpdateSOSSheet(
        alertId: widget.alertId,
        currentData: widget.alertData,
      ),
    );
  }

  void _showDetailsDialog() {
    final services =
        (widget.alertData['services'] as List?)
            ?.map((s) => s.toString())
            .toList() ??
        [];
    final description = widget.alertData['description']?.toString() ?? '';
    final createdAt = (widget.alertData['createdAt'] as Timestamp?)?.toDate();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.sos, color: Colors.red),
            SizedBox(width: 8),
            Text('Active SOS Alert'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (createdAt != null)
              Text(
                'Sent ${_formatTimestamp(createdAt)}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            const SizedBox(height: 16),
            const Text(
              'Services Requested:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: services.map((service) {
                return Chip(
                  label: Text(service),
                  backgroundColor: Colors.red.shade50,
                  labelStyle: const TextStyle(fontSize: 12),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            const Text(
              'Description:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(description),
          ],
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

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final diff = now.difference(timestamp);

    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hours ago';
    return '${diff.inDays} days ago';
  }

  @override
  Widget build(BuildContext context) {
    final isAccepted = widget.alertData['acceptedBy'] != null;
    final acceptedByEmail = widget.alertData['acceptedByEmail'] as String?;
    final dispatcherLocation =
        widget.alertData['dispatcherLocation'] as GeoPoint?;
    final alertLocation = widget.alertData['location'] as GeoPoint?;
    final createdAt = (widget.alertData['createdAt'] as Timestamp?)?.toDate();

    // Calculate distance if dispatcher location is available
    String? distance;
    if (dispatcherLocation != null && alertLocation != null) {
      final distanceMeters = PlacesService.calculateDistance(
        dispatcherLocation.latitude,
        dispatcherLocation.longitude,
        alertLocation.latitude,
        alertLocation.longitude,
      );
      if (distanceMeters < 1000) {
        distance = '${distanceMeters.round()}m away';
      } else {
        distance = '${(distanceMeters / 1000).toStringAsFixed(1)}km away';
      }
    }

    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      color: isAccepted ? Colors.green.shade50 : Colors.red.shade50,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: isAccepted ? Colors.green : Colors.red,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isAccepted ? Colors.green : Colors.red,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isAccepted ? Icons.check_circle : Icons.emergency,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isAccepted ? 'Dispatcher En Route' : 'Active SOS Alert',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: isAccepted
                              ? Colors.green.shade700
                              : Colors.red,
                        ),
                      ),
                      if (createdAt != null)
                        Text(
                          'Sent ${_formatTimestamp(createdAt)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      Text(
                        isAccepted
                            ? acceptedByEmail ?? 'Unknown dispatcher'
                            : 'Help is on the way',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black87,
                        ),
                      ),
                      if (isAccepted && distance != null)
                        Text(
                          distance,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.green.shade900,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.info_outline,
                    color: isAccepted ? Colors.green : Colors.red,
                  ),
                  onPressed: _showDetailsDialog,
                  tooltip: 'View details',
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _showUpdateDialog,
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('Update'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _cancelling ? null : _cancelAlert,
                    icon: _cancelling
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.close, size: 16),
                    label: const Text('Cancel SOS'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Update SOS sheet for modifying active alerts
class UpdateSOSSheet extends StatefulWidget {
  final String alertId;
  final Map<String, dynamic> currentData;

  const UpdateSOSSheet({
    super.key,
    required this.alertId,
    required this.currentData,
  });

  @override
  State<UpdateSOSSheet> createState() => _UpdateSOSSheetState();
}

class _UpdateSOSSheetState extends State<UpdateSOSSheet> {
  late TextEditingController _descriptionController;
  late Set<String> _selectedServices;
  bool _updating = false;

  final _emergencyServices = [
    'Hospital',
    'Police Station',
    'Fire Station',
    'Ambulance',
  ];

  @override
  void initState() {
    super.initState();
    _descriptionController = TextEditingController(
      text: widget.currentData['description']?.toString() ?? '',
    );
    _selectedServices = Set<String>.from(
      (widget.currentData['services'] as List?)?.map((s) => s.toString()) ?? [],
    );
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _updateAlert() async {
    // Validate
    if (_selectedServices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one emergency service'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_descriptionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please describe the emergency'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _updating = true);

    try {
      await FirebaseFirestore.instance
          .collection('emergency_alerts')
          .doc(widget.alertId)
          .update({
            'services': _selectedServices.toList(),
            'description': _descriptionController.text.trim(),
            'updatedAt': FieldValue.serverTimestamp(),
          });

      if (!mounted) return;

      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SOS alert updated successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update alert: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _updating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.edit,
                          color: Colors.orange,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Update SOS Alert',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Services selection
                          const Text(
                            'Select Emergency Services *',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),

                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _emergencyServices.map((service) {
                              final isSelected = _selectedServices.contains(
                                service,
                              );
                              return FilterChip(
                                label: Text(service),
                                selected: isSelected,
                                onSelected: (selected) {
                                  setState(() {
                                    if (selected) {
                                      _selectedServices.add(service);
                                    } else {
                                      _selectedServices.remove(service);
                                    }
                                  });
                                },
                                selectedColor: Colors.orange.shade100,
                                checkmarkColor: Colors.orange,
                              );
                            }).toList(),
                          ),

                          const SizedBox(height: 24),

                          // Description
                          const Text(
                            'Describe the Emergency *',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),

                          TextField(
                            controller: _descriptionController,
                            maxLines: 4,
                            decoration: InputDecoration(
                              hintText:
                                  'e.g., Car accident, medical emergency, fire...',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              filled: true,
                              fillColor: Colors.grey.shade100,
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Update button
                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: ElevatedButton(
                              onPressed: _updating ? null : _updateAlert,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: _updating
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text(
                                      'Update SOS Alert',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
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
