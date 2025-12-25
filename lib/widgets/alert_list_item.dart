import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../models/emergency_alert.dart';
import 'status_badge.dart';

/// Compact list item for displaying alert summaries
class AlertListItem extends StatelessWidget {
  final EmergencyAlert alert;
  final Position? userLocation;
  final VoidCallback? onTap;
  final VoidCallback? onChatTap;
  final VoidCallback? onNavigateTap;
  final VoidCallback? onAcceptTap;
  final bool showActions;
  final bool isCurrentAlert;

  const AlertListItem({
    super.key,
    required this.alert,
    this.userLocation,
    this.onTap,
    this.onChatTap,
    this.onNavigateTap,
    this.onAcceptTap,
    this.showActions = false,
    this.isCurrentAlert = false,
  });

  @override
  Widget build(BuildContext context) {
    final distance = _calculateDistance();
    final timeAgo = alert.createdAt != null
        ? timeago.format(alert.createdAt!)
        : 'Unknown time';

    return Card(
      elevation: isCurrentAlert ? 4 : 1,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isCurrentAlert
            ? const BorderSide(color: Colors.blue, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        StatusBadge(status: alert.status, isCompact: true),
                        const SizedBox(width: 8),
                        if (isCurrentAlert)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'CURRENT',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    timeAgo,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // User info
              Row(
                children: [
                  Icon(Icons.person, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      alert.userEmail,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),

              // Services needed
              if (alert.services.isNotEmpty) ...[
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  children: alert.services.take(3).map((service) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _getServiceColor(service).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _getServiceColor(service)),
                      ),
                      child: Text(
                        service,
                        style: TextStyle(
                          fontSize: 10,
                          color: _getServiceColor(service),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],

              // Distance
              if (distance != null) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.location_on, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      distance,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ],

              // Description preview
              if (alert.description.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  alert.description,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              // Accepted by info (for citizens viewing their alerts)
              if (alert.acceptedByEmail != null && alert.acceptedByEmail!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.local_police, size: 14, color: Colors.green[700]),
                    const SizedBox(width: 4),
                    Text(
                      'Dispatcher: ${alert.acceptedByEmail}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.green[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],

              // Action buttons
              if (showActions) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (onChatTap != null)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onChatTap,
                          icon: const Icon(Icons.chat, size: 16),
                          label: const Text('Chat', style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      ),
                    if (onChatTap != null && onNavigateTap != null) const SizedBox(width: 8),
                    if (onNavigateTap != null)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onNavigateTap,
                          icon: const Icon(Icons.navigation, size: 16),
                          label: const Text('Navigate', style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      ),
                    if (onAcceptTap != null)
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: onAcceptTap,
                          icon: const Icon(Icons.check, size: 16),
                          label: const Text('Accept', style: TextStyle(fontSize: 12)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String? _calculateDistance() {
    if (userLocation == null) return null;

    final distance = Geolocator.distanceBetween(
      userLocation!.latitude,
      userLocation!.longitude,
      alert.lat,
      alert.lon,
    );

    if (distance < 1000) {
      return '${distance.toStringAsFixed(0)} m';
    } else {
      return '${(distance / 1000).toStringAsFixed(2)} km';
    }
  }

  Color _getServiceColor(String service) {
    switch (service.toLowerCase()) {
      case 'hospital':
      case 'ambulance':
        return Colors.red;
      case 'police':
        return Colors.blue;
      case 'fire':
        return Colors.orange;
      default:
        return Colors.purple;
    }
  }
}
