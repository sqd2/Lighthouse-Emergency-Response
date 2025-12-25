import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../models/emergency_alert.dart';
import '../services/alert_history_service.dart';
import 'alert_list_item.dart';
import 'date_range_filter.dart';
import 'chat_screen.dart';
import 'status_badge.dart';

/// Side panel for citizens showing their SOS alerts
class CitizenSidePanel extends StatefulWidget {
  final Position? userLocation;

  const CitizenSidePanel({
    super.key,
    this.userLocation,
  });

  @override
  State<CitizenSidePanel> createState() => _CitizenSidePanelState();
}

class _CitizenSidePanelState extends State<CitizenSidePanel> {
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime _endDate = DateTime.now();
  int _selectedTab = 0; // 0=current, 1=history

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Container(
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
              color: Colors.red[700],
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
                const Icon(Icons.sos, color: Colors.white),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'My SOS Alerts',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (_selectedTab == 1)
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
                _buildTab(1, 'History', Icons.history),
              ],
            ),
          ),

          // Content
          Expanded(
            child: IndexedStack(
              index: _selectedTab,
              children: [
                _buildCurrentTab(user.uid),
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
                ? const Border(bottom: BorderSide(color: Colors.red, width: 2))
                : null,
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? Colors.red : Colors.grey[600],
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? Colors.red : Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentTab(String citizenId) {
    return StreamBuilder<List<EmergencyAlert>>(
      stream: AlertHistoryService.getCitizenActiveAlerts(citizenId),
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
                    'No Active SOS',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap the SOS button to request help',
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
                _buildCurrentAlertCard(currentAlert),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCurrentAlertCard(EmergencyAlert alert) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.red, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.sos, color: Colors.red),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'ACTIVE SOS ALERT',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                ),
                StatusBadge(status: alert.status, isCompact: true),
              ],
            ),
            const Divider(height: 24),
            _buildInfoRow(Icons.access_time, 'Status', _getStatusText(alert)),
            if (alert.hasDispatcher) ...[
              const SizedBox(height: 12),
              _buildInfoRow(
                Icons.local_police,
                'Dispatcher',
                alert.acceptedByEmail ?? 'Unknown',
              ),
            ],
            if (alert.services.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildInfoRow(Icons.local_hospital, 'Services Requested', ''),
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: alert.services.map((service) {
                  return Chip(
                    label: Text(service, style: const TextStyle(fontSize: 11)),
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                if (alert.hasDispatcher)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openChat(alert),
                      icon: const Icon(Icons.chat, size: 18),
                      label: const Text('Chat'),
                    ),
                  ),
                if (alert.hasDispatcher) const SizedBox(width: 8),
                if (!alert.isResolved && !alert.isCancelled)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _cancelAlert(alert),
                      icon: const Icon(Icons.cancel, size: 18),
                      label: const Text('Cancel'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
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

  Widget _buildHistoryTab(String citizenId) {
    return StreamBuilder<List<EmergencyAlert>>(
      stream: AlertHistoryService.getCitizenPastAlerts(
        citizenId,
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
              showActions: alert.hasDispatcher,
              onChatTap: alert.hasDispatcher ? () => _openChat(alert) : null,
            );
          },
        );
      },
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (value.isNotEmpty)
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _getStatusText(EmergencyAlert alert) {
    switch (alert.status) {
      case EmergencyAlert.STATUS_PENDING:
        return 'Waiting for dispatcher...';
      case EmergencyAlert.STATUS_ACTIVE:
        return 'Dispatcher is en route';
      case EmergencyAlert.STATUS_ARRIVED:
        return 'Dispatcher has arrived at your location';
      case EmergencyAlert.STATUS_RESOLVED:
        return 'Alert resolved';
      case EmergencyAlert.STATUS_CANCELLED:
        return 'Alert cancelled';
      default:
        return 'Unknown status';
    }
  }

  void _openChat(EmergencyAlert alert) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          alertId: alert.id,
          userRole: 'citizen',
          otherPartyEmail: alert.acceptedByEmail ?? 'Dispatcher',
          otherPartyUserId: alert.acceptedBy,
        ),
      ),
    );
  }

  Future<void> _cancelAlert(EmergencyAlert alert) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel SOS Alert?'),
        content: const Text('Please select a reason for cancellation:'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'False Alarm'),
            child: const Text('False Alarm'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'Resolved on my own'),
            child: const Text('Resolved on my own'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'Help arrived from another source'),
            child: const Text('Other help arrived'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );

    if (reason == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('emergency_alerts')
          .doc(alert.id)
          .update({
        'status': EmergencyAlert.STATUS_CANCELLED,
        'cancelledAt': FieldValue.serverTimestamp(),
        'cancellationReason': reason,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('SOS alert cancelled')),
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

  void _showAlertDetails(EmergencyAlert alert) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Alert Details'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildInfoRow(Icons.access_time, 'Status', _getStatusText(alert)),
              if (alert.hasDispatcher) ...[
                const SizedBox(height: 12),
                _buildInfoRow(
                  Icons.local_police,
                  'Dispatcher',
                  alert.acceptedByEmail ?? 'Unknown',
                ),
              ],
              if (alert.description.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildInfoRow(Icons.description, 'Description', alert.description),
              ],
              if (alert.resolutionNotes != null && alert.resolutionNotes!.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildInfoRow(Icons.note, 'Resolution Notes', alert.resolutionNotes!),
              ],
            ],
          ),
        ),
        actions: [
          if (alert.hasDispatcher)
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _openChat(alert);
              },
              icon: const Icon(Icons.chat),
              label: const Text('Open Chat'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
