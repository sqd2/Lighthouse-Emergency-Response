import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../models/emergency_alert.dart';
import 'dispatcher_side_panel.dart';

/// Bottom sheet variant of dispatcher side panel for mobile devices
class DispatcherPanelSheet extends StatelessWidget {
  final Position? userLocation;
  final Function(EmergencyAlert) onNavigateToAlert;
  final Future<void> Function(String alertId) onAcceptAlert;

  const DispatcherPanelSheet({
    super.key,
    this.userLocation,
    required this.onNavigateToAlert,
    required this.onAcceptAlert,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 10,
                offset: Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Panel content (expand to fill)
              Expanded(
                child: DispatcherSidePanel(
                  userLocation: userLocation,
                  onNavigateToAlert: onNavigateToAlert,
                  onAcceptAlert: onAcceptAlert,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Show the bottom sheet
  static void show(
    BuildContext context, {
    Position? userLocation,
    required Function(EmergencyAlert) onNavigateToAlert,
    required Future<void> Function(String alertId) onAcceptAlert,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DispatcherPanelSheet(
        userLocation: userLocation,
        onNavigateToAlert: onNavigateToAlert,
        onAcceptAlert: onAcceptAlert,
      ),
    );
  }
}
