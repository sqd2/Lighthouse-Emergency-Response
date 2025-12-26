import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../models/emergency_alert.dart';
import '../models/call.dart';
import '../services/alert_history_service.dart';
import 'alert_list_item.dart';
import 'date_range_filter.dart';
import 'chat_screen.dart';
import 'call_button.dart';
import 'emergency_alert_widget.dart';

/// Side panel for dispatchers showing alerts and history
class DispatcherSidePanel extends StatefulWidget {
  final Position? userLocation;
  final Function(EmergencyAlert) onNavigateToAlert;
  final Future<void> Function(String alertId) onAcceptAlert;

  const DispatcherSidePanel({
    super.key,
    this.userLocation,
    required this.onNavigateToAlert,
    required this.onAcceptAlert,
  });

  @override
  State<DispatcherSidePanel> createState() => _DispatcherSidePanelState();
}

class _DispatcherSidePanelState extends State<DispatcherSidePanel> {
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime _endDate = DateTime.now();
  int _selectedTab = 0; // 0=current, 1=pending, 2=past

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Container(
        width: 300,
        color: Colors.grey[100],
        child: const Center(child: Text('Not logged in')),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Colors.grey[300]!)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue[700],
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.dashboard, color: Colors.white),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Dispatcher Dashboard',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (_selectedTab == 2)
                  DateRangeFilter(
                    startDate: _startDate,
                    endDate: _endDate,
                    onChanged: (range) {
                      setState(() {
                        _startDate = range.start;
                        _endDate = range.end;
                      });
                    },
                  ),
              ],
            ),
          ),

          // Tab bar
          Container(
            decoration: BoxDecoration(
              color: Colors.grey[100],
              border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
            ),
            child: Row(
              children: [
                _buildTab(0, 'Current', Icons.notification_important),
                _buildTab(1, 'Pending', Icons.pending_actions),
                _buildTab(2, 'History', Icons.history),
              ],
            ),
          ),

          // Content
          Expanded(
            child: IndexedStack(
              index: _selectedTab,
              children: [
                _buildCurrentTab(user.uid),
                _buildPendingTab(user.uid),
                _buildHistoryTab(user.uid),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(int index, String label, IconData icon) {
    final isSelected = _selectedTab == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : null,
            border: isSelected
                ? const Border(bottom: BorderSide(color: Colors.blue, width: 2))
                : null,
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? Colors.blue : Colors.grey[600],
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? Colors.blue : Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentTab(String dispatcherId) {
    return StreamBuilder<List<EmergencyAlert>>(
      stream: AlertHistoryService.getDispatcherActiveAlerts(dispatcherId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final alerts = snapshot.data ?? [];

        if (alerts.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No Active Alerts',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Check pending tab to accept new alerts',
                    style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        final currentAlert = alerts.first;

        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AlertListItem(
                  alert: currentAlert,
                  userLocation: widget.userLocation,
                  isCurrentAlert: true,
                  showActions: true,
                  onTap: () => _showAlertDetails(currentAlert),
                  onChatTap: () => _openChat(currentAlert),
                  onNavigateTap: () => widget.onNavigateToAlert(currentAlert),
                ),
                const SizedBox(height: 8),
                _buildQuickActions(currentAlert),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPendingTab(String dispatcherId) {
    return StreamBuilder<List<EmergencyAlert>>(
      stream: AlertHistoryService.getPendingAlerts(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final alerts = snapshot.data ?? [];

        if (alerts.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No Pending Alerts',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'All alerts have been assigned',
                    style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
          );
        }

        return FutureBuilder<bool>(
          future: AlertHistoryService.hasActiveAlerts(dispatcherId),
          builder: (context, hasActiveSnapshot) {
            final hasActive = hasActiveSnapshot.data ?? false;

            return ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: alerts.length,
              itemBuilder: (context, index) {
                final alert = alerts[index];
                return AlertListItem(
                  alert: alert,
                  userLocation: widget.userLocation,
                  showActions: true,
                  onTap: () => _showAlertDetails(alert),
                  onAcceptTap: hasActive
                      ? null // Disable if already has active alert
                      : () => _acceptPendingAlert(alert),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildHistoryTab(String dispatcherId) {
    return StreamBuilder<List<EmergencyAlert>>(
      stream: AlertHistoryService.getDispatcherPastAlerts(
        dispatcherId,
        startDate: _startDate,
        endDate: _endDate,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final alerts = snapshot.data ?? [];

        if (alerts.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No History',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No past alerts in selected date range',
                    style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: alerts.length,
          itemBuilder: (context, index) {
            final alert = alerts[index];
            return AlertListItem(
              alert: alert,
              userLocation: widget.userLocation,
              onTap: () => _showAlertDetails(alert),
              showActions: true,
              onChatTap: () => _openChat(alert),
            );
          },
        );
      },
    );
  }

  Widget _buildQuickActions(EmergencyAlert alert) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Quick Actions',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildActionChip(
                  'Chat',
                  Icons.chat,
                  Colors.blue,
                  () => _openChat(alert),
                ),
                // Video call button
                CallActionChip(
                  alertId: alert.id,
                  receiverId: alert.userId,
                  receiverName: alert.userEmail,
                  callType: Call.TYPE_VIDEO,
                  label: 'Video Call',
                  icon: Icons.videocam,
                  color: Colors.purple,
                ),
                // Audio call button
                CallActionChip(
                  alertId: alert.id,
                  receiverId: alert.userId,
                  receiverName: alert.userEmail,
                  callType: Call.TYPE_AUDIO,
                  label: 'Voice Call',
                  icon: Icons.phone,
                  color: Colors.green,
                ),
                _buildActionChip(
                  'Navigate',
                  Icons.navigation,
                  Colors.green,
                  () => widget.onNavigateToAlert(alert),
                ),
                if (alert.status == EmergencyAlert.STATUS_ACTIVE)
                  _buildActionChip(
                    'Mark Arrived',
                    Icons.location_on,
                    Colors.orange,
                    () => _markArrived(alert),
                  ),
                if (alert.status == EmergencyAlert.STATUS_ARRIVED ||
                    alert.status == EmergencyAlert.STATUS_ACTIVE)
                  _buildActionChip(
                    'Mark Resolved',
                    Icons.check_circle,
                    Colors.teal,
                    () => _markResolved(alert),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionChip(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return ActionChip(
      avatar: Icon(icon, size: 18, color: color),
      label: Text(label),
      onPressed: onTap,
      backgroundColor: color.withOpacity(0.1),
      side: BorderSide(color: color),
    );
  }

  void _showAlertDetails(EmergencyAlert alert) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => EmergencyAlertSheet(
        alert: alert,
        userLocation: widget.userLocation,
        onNavigate: () {
          Navigator.pop(context);
          widget.onNavigateToAlert(alert);
        },
        onAccepted: (alertId) => widget.onAcceptAlert(alertId),
      ),
    );
  }

  void _openChat(EmergencyAlert alert) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          alertId: alert.id,
          userRole: 'dispatcher',
          otherPartyEmail: alert.userEmail,
          otherPartyUserId: alert.userId,
        ),
      ),
    );
  }

  Future<void> _acceptPendingAlert(EmergencyAlert alert) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Accept Alert?'),
        content: Text('Do you want to accept this alert from ${alert.userEmail}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Accept'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Expanded(
                child: Text('Accepting alert and acquiring location...'),
              ),
            ],
          ),
        ),
      );

      try {
        await widget.onAcceptAlert(alert.id);

        if (mounted) {
          Navigator.pop(context); // Close loading dialog
          setState(() => _selectedTab = 0); // Switch to current tab

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Alert accepted successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          Navigator.pop(context); // Close loading dialog

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to accept alert: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _markArrived(EmergencyAlert alert) async {
    try {
      await FirebaseFirestore.instance
          .collection('emergency_alerts')
          .doc(alert.id)
          .update({
        'status': EmergencyAlert.STATUS_ARRIVED,
        'arrivedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Marked as arrived')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _markResolved(EmergencyAlert alert) async {
    final notesController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark as Resolved?'),
        content: TextField(
          controller: notesController,
          decoration: const InputDecoration(
            labelText: 'Resolution notes (optional)',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final updateData = {
          'status': EmergencyAlert.STATUS_RESOLVED,
          'resolvedAt': FieldValue.serverTimestamp(),
        };

        if (notesController.text.trim().isNotEmpty) {
          updateData['resolutionNotes'] = notesController.text.trim();
        }

        await FirebaseFirestore.instance
            .collection('emergency_alerts')
            .doc(alert.id)
            .update(updateData);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Alert marked as resolved')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      }
    }

    notesController.dispose();
  }
}
