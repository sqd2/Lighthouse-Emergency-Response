import 'dart:async';
import 'package:flutter/material.dart';
import '../models/call.dart';
import '../services/livekit_service.dart';
import '../config/livekit_config.dart';
import 'call_screen.dart';

/// Full-screen dialog for incoming calls
class IncomingCallDialog extends StatefulWidget {
  final String alertId;
  final Call call;

  const IncomingCallDialog({
    super.key,
    required this.alertId,
    required this.call,
  });

  @override
  State<IncomingCallDialog> createState() => _IncomingCallDialogState();
}

class _IncomingCallDialogState extends State<IncomingCallDialog>
    with SingleTickerProviderStateMixin {
  final _liveKitService = LiveKitService();
  Timer? _timeoutTimer;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    // Animation for pulsing effect
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Auto-dismiss after timeout
    _timeoutTimer = Timer(LiveKitConfig.incomingCallTimeout, () {
      if (mounted) {
        _missedCall();
      }
    });
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _acceptCall() async {
    _timeoutTimer?.cancel();

    // Show loading state
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    try {
      // Accept the call
      final success = await _liveKitService.acceptCall(
        widget.alertId,
        widget.call,
      );

      if (mounted) {
        // Close loading dialog
        Navigator.of(context).pop();

        if (success) {
          // Close incoming call dialog
          Navigator.of(context).pop();

          // Navigate to call screen
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => CallScreen(
                alertId: widget.alertId,
                call: widget.call,
                isOutgoing: false,
              ),
            ),
          );
        } else {
          // Show error
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to accept call'),
              backgroundColor: Colors.red,
            ),
          );
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      debugPrint('[IncomingCallDialog] Error accepting call: $e');
      if (mounted) {
        Navigator.of(context).pop(); // Close loading
        Navigator.of(context).pop(); // Close dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _rejectCall() async {
    _timeoutTimer?.cancel();

    await _liveKitService.rejectCall(widget.alertId, widget.call.id);

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _missedCall() async {
    _timeoutTimer?.cancel();

    // Mark as missed in Firestore
    await _liveKitService.rejectCall(widget.alertId, widget.call.id);

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Missed call from ${widget.call.callerName}'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isVideoCall = widget.call.type == Call.TYPE_VIDEO;

    return Material(
      color: Colors.black87,
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Caller icon with pulse animation
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _pulseAnimation.value,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isVideoCall ? Colors.purple : Colors.green,
                        boxShadow: [
                          BoxShadow(
                            color: (isVideoCall ? Colors.purple : Colors.green)
                                .withOpacity(0.3),
                            blurRadius: 30,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                      child: Icon(
                        isVideoCall ? Icons.videocam : Icons.phone,
                        size: 60,
                        color: Colors.white,
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 40),

              // Caller name
              Text(
                widget.call.callerName,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 8),

              // Call type and role
              Text(
                '${isVideoCall ? "Video" : "Voice"} call • ${widget.call.callerRole.toUpperCase()}',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.white.withOpacity(0.8),
                ),
              ),

              const SizedBox(height: 60),

              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Reject button
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FloatingActionButton(
                        heroTag: 'reject',
                        onPressed: _rejectCall,
                        backgroundColor: Colors.red,
                        child: const Icon(
                          Icons.call_end,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Decline',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),

                  // Accept button
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FloatingActionButton(
                        heroTag: 'accept',
                        onPressed: _acceptCall,
                        backgroundColor: Colors.green,
                        child: Icon(
                          isVideoCall ? Icons.videocam : Icons.phone,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Accept',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 40),

              // Timeout countdown (optional - could add this later)
              Text(
                'Ringing...',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Show incoming call dialog
void showIncomingCallDialog(
  BuildContext context,
  String alertId,
  Call call,
) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => IncomingCallDialog(
      alertId: alertId,
      call: call,
    ),
  );
}
