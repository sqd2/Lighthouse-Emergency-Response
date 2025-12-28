import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/facility_pin.dart';

/// Facility details bottom sheet widget (shared by citizen and dispatcher dashboards)
class FacilityDetailsSheet extends StatelessWidget {
  final FacilityPin facility;
  final Position? userLocation;
  final VoidCallback? onNavigate;
  final VoidCallback? onDelete;
  final bool canDelete;

  const FacilityDetailsSheet({
    super.key,
    required this.facility,
    this.userLocation,
    this.onNavigate,
    this.onDelete,
    this.canDelete = false,
  });

  String _niceType(String t) {
    final s = t.trim();
    if (s.isEmpty) return 'Facility';
    return s[0].toUpperCase() + s.substring(1).toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    final meta = facility.meta ?? const <String, dynamic>{};
    final isGooglePlace = facility.source == 'google_places';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      "${_niceType(facility.type)} — ${facility.name}",
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (isGooglePlace)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'Google',
                        style: TextStyle(fontSize: 11, color: Colors.blue),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text("Lat: ${facility.lat.toStringAsFixed(6)}"),
              Text("Lon: ${facility.lon.toStringAsFixed(6)}"),
              const SizedBox(height: 8),

              // Google Places specific data
              if (isGooglePlace) ...[
                if (meta['address'] != null &&
                    meta['address'].toString().isNotEmpty)
                  Text("Address: ${meta['address']}"),
                if (meta['rating'] != null)
                  Row(
                    children: [
                      const Icon(Icons.star, size: 16, color: Colors.orange),
                      const SizedBox(width: 4),
                      Text("${meta['rating']} / 5"),
                      if (meta['userRatingsTotal'] != null)
                        Text(" (${meta['userRatingsTotal']} reviews)"),
                    ],
                  ),
                if (meta['isOpenNow'] != null)
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 16,
                        color: meta['isOpenNow'] ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        meta['isOpenNow'] ? 'Open now' : 'Closed',
                        style: TextStyle(
                          color: meta['isOpenNow'] ? Colors.green : Colors.red,
                        ),
                      ),
                    ],
                  ),
              ]
              // Manual facility specific data
              else ...[
                if (meta['contactPerson'] != null &&
                    meta['contactPerson'].toString().isNotEmpty)
                  Text("Contact: ${meta['contactPerson']}"),
                if (meta['contactNumber'] != null &&
                    meta['contactNumber'].toString().isNotEmpty)
                  Text("Phone: ${meta['contactNumber']}"),
                if (meta['description'] != null &&
                    meta['description'].toString().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text("Description: ${meta['description']}"),
                ],
                if (meta['services'] != null &&
                    meta['services'] is List &&
                    (meta['services'] as List).isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text("Services: ${(meta['services'] as List).join(', ')}"),
                ],
              ],

              const SizedBox(height: 16),

              // Navigate button (only shown if userLocation and onNavigate are provided)
              if (userLocation != null && onNavigate != null)
                Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: onNavigate,
                        icon: const Icon(Icons.directions, color: Colors.white),
                        label: const Text(
                          'Navigate to Facility',
                          style: TextStyle(color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),

              // Delete button (only shown for facilities the user can delete)
              if (canDelete && onDelete != null)
                Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          // Show confirmation dialog
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Delete Facility'),
                              content: Text(
                                'Are you sure you want to delete "${facility.name}"? This action cannot be undone.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context, false),
                                  child: const Text('Cancel'),
                                ),
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                  ),
                                  child: const Text(
                                    'Delete',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          );

                          if (confirm == true) {
                            Navigator.pop(context); // Close the facility details sheet
                            onDelete!();
                          }
                        },
                        icon: const Icon(Icons.delete, color: Colors.white),
                        label: const Text(
                          'Delete Facility',
                          style: TextStyle(color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Close"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
