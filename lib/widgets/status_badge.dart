import 'package:flutter/material.dart';
import '../models/emergency_alert.dart';

/// Color-coded status badge for emergency alerts
class StatusBadge extends StatelessWidget {
  final String status;
  final bool isCompact;

  const StatusBadge({
    super.key,
    required this.status,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    final config = _getStatusConfig(status);

    if (isCompact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: config.color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: config.color, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(config.icon, size: 12, color: config.color),
            const SizedBox(width: 4),
            Text(
              config.label,
              style: TextStyle(
                color: config.color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return Chip(
      avatar: Icon(config.icon, size: 18, color: config.color),
      label: Text(
        config.label,
        style: TextStyle(
          color: config.color,
          fontWeight: FontWeight.w600,
        ),
      ),
      backgroundColor: config.color.withOpacity(0.1),
      side: BorderSide(color: config.color, width: 1.5),
    );
  }

  _StatusConfig _getStatusConfig(String status) {
    switch (status) {
      case EmergencyAlert.STATUS_PENDING:
        return _StatusConfig(
          label: 'Pending',
          color: Colors.orange,
          icon: Icons.access_time,
        );
      case EmergencyAlert.STATUS_ACTIVE:
        return _StatusConfig(
          label: 'En Route',
          color: Colors.green,
          icon: Icons.navigation,
        );
      case EmergencyAlert.STATUS_ARRIVED:
        return _StatusConfig(
          label: 'Arrived',
          color: Colors.blue,
          icon: Icons.location_on,
        );
      case EmergencyAlert.STATUS_RESOLVED:
        return _StatusConfig(
          label: 'Resolved',
          color: Colors.teal,
          icon: Icons.check_circle,
        );
      case EmergencyAlert.STATUS_CANCELLED:
        return _StatusConfig(
          label: 'Cancelled',
          color: Colors.grey,
          icon: Icons.cancel,
        );
      default:
        return _StatusConfig(
          label: 'Unknown',
          color: Colors.grey,
          icon: Icons.help_outline,
        );
    }
  }
}

class _StatusConfig {
  final String label;
  final Color color;
  final IconData icon;

  _StatusConfig({
    required this.label,
    required this.color,
    required this.icon,
  });
}
