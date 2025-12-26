import 'package:flutter/material.dart';
import '../models/call.dart';
import '../services/livekit_service.dart';
import 'call_screen.dart';

/// Reusable button widget for initiating voice or video calls
class CallButton extends StatefulWidget {
  final String alertId;
  final String receiverId;
  final String receiverName;
  final String callType; // Call.TYPE_VIDEO or Call.TYPE_AUDIO
  final IconData icon;
  final String tooltip;
  final Color? color;
  final bool enabled;

  const CallButton({
    super.key,
    required this.alertId,
    required this.receiverId,
    required this.receiverName,
    required this.callType,
    required this.icon,
    required this.tooltip,
    this.color,
    this.enabled = true,
  });

  @override
  State<CallButton> createState() => _CallButtonState();
}

class _CallButtonState extends State<CallButton> {
  bool _isInitiating = false;
  final _liveKitService = LiveKitService();

  Future<void> _initiateCall() async {
    if (!widget.enabled || _isInitiating) return;

    setState(() {
      _isInitiating = true;
    });

    try {
      // Initiate the call
      final call = await _liveKitService.initiateCall(
        alertId: widget.alertId,
        receiverId: widget.receiverId,
        receiverName: widget.receiverName,
        type: widget.callType,
      );

      if (call != null && mounted) {
        // Navigate to call screen
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => CallScreen(
              alertId: widget.alertId,
              call: call,
              isOutgoing: true,
            ),
          ),
        );
      } else {
        // Show error
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to initiate call'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[CallButton] Error initiating call: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isInitiating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: _isInitiating
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(widget.icon),
      color: widget.color,
      tooltip: widget.tooltip,
      onPressed: widget.enabled && !_isInitiating ? _initiateCall : null,
    );
  }
}

/// Action chip variant for call buttons (used in alert cards)
class CallActionChip extends StatefulWidget {
  final String alertId;
  final String receiverId;
  final String receiverName;
  final String callType;
  final String label;
  final IconData icon;
  final Color color;
  final bool enabled;

  const CallActionChip({
    super.key,
    required this.alertId,
    required this.receiverId,
    required this.receiverName,
    required this.callType,
    required this.label,
    required this.icon,
    required this.color,
    this.enabled = true,
  });

  @override
  State<CallActionChip> createState() => _CallActionChipState();
}

class _CallActionChipState extends State<CallActionChip> {
  bool _isInitiating = false;
  final _liveKitService = LiveKitService();

  Future<void> _initiateCall() async {
    if (!widget.enabled || _isInitiating) return;

    setState(() {
      _isInitiating = true;
    });

    try {
      final call = await _liveKitService.initiateCall(
        alertId: widget.alertId,
        receiverId: widget.receiverId,
        receiverName: widget.receiverName,
        type: widget.callType,
      );

      if (call != null && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => CallScreen(
              alertId: widget.alertId,
              call: call,
              isOutgoing: true,
            ),
          ),
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to initiate call'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[CallActionChip] Error initiating call: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isInitiating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: _isInitiating
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(widget.icon, size: 18, color: widget.color),
      label: Text(widget.label),
      onPressed: widget.enabled && !_isInitiating ? _initiateCall : null,
      backgroundColor: widget.color.withOpacity(0.1),
      side: BorderSide(color: widget.color),
    );
  }
}
